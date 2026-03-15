import { type Abi, type AbiFunction, type AbiParameter, getAddress, toFunctionSelector } from "viem";
import { ContextProperties, DescriptorFormat as DF, lookupTypeCode, OpCodes, Scopes } from "./constants";
import type { DecodedPolicy, DecodedRule, Hex, Span } from "./decoder";
import { hexToBytes, readU24 } from "./decoder";

///////////////////////////////////////////////////////////////////////////
//                                TYPES
///////////////////////////////////////////////////////////////////////////

export type ExplainedPolicy = {
  selector: Hex;
  functionName: string | null;
  isSelectorless: boolean;
  params: ExplainedParam[];
  groups: ExplainedGroup[];
  span: Span;
};

export type ExplainedParam = {
  index: number;
  name: string | null;
  type: string;
  isDynamic: boolean;
  span: Span;
};

export type ExplainedGroup = {
  constraints: ExplainedConstraint[];
  span: Span;
};

export type ExplainedConstraint = {
  scope: string;
  path: Hex;
  pathLabel: string;
  targetType: string;
  rules: ExplainedRule[];
  span: Span;
};

export type ExplainedRule = {
  operator: string;
  negated: boolean;
  operands: string[];
  span: Span;
};

export type ExplainOptions = {
  abi?: Abi;
};

///////////////////////////////////////////////////////////////////////////
//                            REVERSE LOOKUPS
///////////////////////////////////////////////////////////////////////////

const scopeByCode = new Map<number, string>(Object.values(Scopes).map((scope) => [scope.code, scope.label]));

const opByCode = new Map<number, string>(
  Object.entries(OpCodes)
    .filter(([key]) => key !== "NOT")
    .map(([, entry]) => [entry.code, entry.label]),
);

const ctxPropByCode = new Map<number, string>(Object.values(ContextProperties).map((prop) => [prop.code, prop.label]));

const NOT_FLAG = OpCodes.NOT.code;

///////////////////////////////////////////////////////////////////////////
//                         DESCRIPTOR NAVIGATION
///////////////////////////////////////////////////////////////////////////

// Skip over a descriptor node and return the offset after it.
function skipNode(data: Uint8Array, offset: number): number {
  return lookupTypeCode(data[offset]).typeClass === "elementary"
    ? offset + DF.TYPECODE_SIZE
    : offset + (readU24(data, offset + DF.TYPECODE_SIZE) & DF.META_NODE_LENGTH_MASK);
}

// Parse a path hex string into an array of BE16 step values.
export function parsePathSteps(path: Hex): number[] {
  const hex = path.slice(2);
  const steps: number[] = [];
  for (let i = 0; i < hex.length; i += 4) {
    steps.push(parseInt(hex.slice(i, i + 4), 16));
  }
  return steps;
}

// Resolve a calldata-scope path against the descriptor and optional ABI.
function resolveCalldataPath(
  descBytes: Uint8Array,
  steps: number[],
  abiInputs?: readonly AbiParameter[],
): { pathLabel: string; targetType: string; leafTypeCode: number } {
  const paramIndex = steps[0];
  let abiParam: AbiParameter | undefined = abiInputs?.[paramIndex];

  // Skip to param N in the descriptor.
  let offset: number = DF.HEADER_SIZE;
  for (let i = 0; i < paramIndex; i++) {
    offset = skipNode(descBytes, offset);
  }

  let label = abiParam?.name ?? `arg(${paramIndex})`;

  // Navigate remaining steps into composite types.
  for (let step = 1; step < steps.length; step++) {
    const info = lookupTypeCode(descBytes[offset]);

    if (info.typeClass === "tuple") {
      const fieldIndex = steps[step];
      let child: number = offset + DF.TUPLE_HEADER_SIZE;
      for (let i = 0; i < fieldIndex; i++) {
        child = skipNode(descBytes, child);
      }
      offset = child;
      const childAbi = (abiParam as { components?: AbiParameter[] })?.components?.[fieldIndex];
      label += `.${childAbi?.name ?? `field(${fieldIndex})`}`;
      abiParam = childAbi;
    } else if (info.typeClass === "staticArray" || info.typeClass === "dynamicArray") {
      offset += DF.ARRAY_HEADER_SIZE;
      label += "[]";
      // ABI components for arrays describe the element's tuple fields.
    } else {
      break;
    }
  }

  const leafTypeCode = descBytes[offset];
  const leafInfo = lookupTypeCode(leafTypeCode);
  return { pathLabel: label, targetType: leafInfo.label, leafTypeCode };
}

// Resolve a context-scope path to its property label.
function resolveContextPath(steps: number[]): {
  pathLabel: string;
  targetType: string;
  leafTypeCode: number;
} {
  const propCode = steps[0];
  const label = ctxPropByCode.get(propCode) ?? `context(${propCode})`;
  // Context properties are all uint256 except msg.sender and tx.origin (address).
  const isAddress = propCode === ContextProperties.MSG_SENDER.code || propCode === ContextProperties.TX_ORIGIN.code;
  return {
    pathLabel: label,
    targetType: isAddress ? "address" : "uint256",
    leafTypeCode: isAddress ? 0x40 : 0x1f,
  };
}

///////////////////////////////////////////////////////////////////////////
//                          OPERAND DECODING
///////////////////////////////////////////////////////////////////////////

const TWO_POW_256 = 2n ** 256n;
const TWO_POW_255 = 2n ** 255n;

// Decode a single 32-byte ABI-encoded operand based on the target type code.
function decodeOperand(hex32: string, typeCode: number): string {
  const raw = BigInt(`0x${hex32}`);

  // address: lower 20 bytes.
  if (typeCode === 0x40) {
    const addr = `0x${hex32.slice(24)}`;
    try {
      return getAddress(addr);
    } catch {
      return addr;
    }
  }

  // bool.
  if (typeCode === 0x41) return raw === 0n ? "false" : "true";

  // int8–int256 (signed).
  if (typeCode >= 0x20 && typeCode <= 0x3f) {
    return raw >= TWO_POW_255 ? (raw - TWO_POW_256).toString() : raw.toString();
  }

  // uint8–uint256 (unsigned).
  if (typeCode >= 0x00 && typeCode <= 0x1f) return raw.toString();

  // bytesN: first N bytes.
  if (typeCode >= 0x50 && typeCode <= 0x6f) {
    const n = typeCode - 0x50 + 1;
    return `0x${hex32.slice(0, n * 2)}`;
  }

  // bytes, string, function, composites — keep as hex.
  return `0x${hex32}`;
}

// Decode operands from separate opCode and data fields.
function decodeOperandsFromFields(dataHex: Hex, typeCode: number, opBase: number): string[] {
  const hex = dataHex.slice(2); // strip "0x".

  // IN: multiple 32-byte values.
  if (opBase === OpCodes.IN.code) {
    const operands: string[] = [];
    for (let i = 0; i < hex.length; i += 64) {
      operands.push(decodeOperand(hex.slice(i, i + 64), typeCode));
    }
    return operands;
  }

  // BETWEEN / LENGTH_BETWEEN: two 32-byte values.
  if (opBase === OpCodes.BETWEEN.code || opBase === OpCodes.LENGTH_BETWEEN.code) {
    return [decodeOperand(hex.slice(0, 64), typeCode), decodeOperand(hex.slice(64, 128), typeCode)];
  }

  // Single operand (EQ, GT, LT, etc.).
  return [decodeOperand(hex.slice(0, 64), typeCode)];
}

///////////////////////////////////////////////////////////////////////////
//                            ABI MATCHING
///////////////////////////////////////////////////////////////////////////

// Find the ABI function entry that matches the given selector.
function findAbiFunction(abi: Abi, selector: Hex): AbiFunction | null {
  for (const item of abi) {
    if (item.type === "function") {
      if (toFunctionSelector(item) === selector) return item;
    }
  }
  return null;
}

///////////////////////////////////////////////////////////////////////////
//                              EXPLAINER
///////////////////////////////////////////////////////////////////////////

export function explainPolicy(decoded: DecodedPolicy, opts?: ExplainOptions): ExplainedPolicy {
  // Decode the embedded descriptor for type navigation.
  const descBytes = hexToBytes(decoded.descriptor.raw);

  // Resolve function name and ABI inputs.
  let functionName: string | null = null;
  let abiInputs: readonly AbiParameter[] | undefined;

  if (opts?.abi && !decoded.isSelectorless) {
    const matched = findAbiFunction(opts.abi, decoded.selector.value);
    if (matched) {
      functionName = matched.name;
      abiInputs = matched.inputs;
    }
  }

  // Build explained params from policy-level params (spans are policy-relative).
  const params: ExplainedParam[] = decoded.descriptor.params.map((param) => ({
    index: param.index,
    name: abiInputs?.[param.index]?.name ?? null,
    type: lookupTypeCode(param.typeCode).label,
    isDynamic: param.isDynamic,
    span: param.span,
  }));

  // Build explained groups with constraint grouping.
  const groups: ExplainedGroup[] = decoded.groups.map((group) => {
    // Group rules by (scope, path) into constraints.
    const constraintMap = new Map<string, { scope: number; path: Hex; rules: DecodedRule[]; span: Span }>();
    const constraintOrder: string[] = [];

    for (const rule of group.rules) {
      const key = `${rule.scope.value}:${rule.path.value}`;
      const existing = constraintMap.get(key);
      if (existing) {
        existing.rules.push(rule);
        existing.span.end = rule.span.end; // Rules are ordered by byte position.
      } else {
        constraintMap.set(key, {
          scope: rule.scope.value,
          path: rule.path.value,
          rules: [rule],
          span: { start: rule.span.start, end: rule.span.end },
        });
        constraintOrder.push(key);
      }
    }

    const constraints: ExplainedConstraint[] = constraintOrder.map((key) => {
      // biome-ignore lint/style/noNonNullAssertion: key comes from constraintOrder which is populated alongside constraintMap.
      const c = constraintMap.get(key)!;
      const steps = parsePathSteps(c.path);
      const scopeLabel = scopeByCode.get(c.scope) ?? `scope(${c.scope})`;
      const isContext = c.scope === Scopes.CONTEXT.code;
      const { pathLabel, targetType, leafTypeCode } = isContext
        ? resolveContextPath(steps)
        : resolveCalldataPath(descBytes, steps, abiInputs);

      const rules: ExplainedRule[] = c.rules.map((rule) => {
        const negated = (rule.opCode.value & NOT_FLAG) !== 0;
        const opBase = rule.opCode.value & ~NOT_FLAG;
        const baseLabel = opByCode.get(opBase) ?? `op(${opBase})`;
        const operator = negated && baseLabel === "==" ? "!=" : negated ? `not ${baseLabel}` : baseLabel;

        // Length operators always decode operands as uint256.
        const decodeTypeCode = opBase >= 0x20 && opBase <= 0x25 ? 0x1f : leafTypeCode;

        return {
          operator,
          negated,
          operands: decodeOperandsFromFields(rule.data.value, decodeTypeCode, opBase),
          span: rule.span,
        };
      });

      return {
        scope: scopeLabel,
        path: c.path,
        pathLabel,
        targetType,
        rules,
        span: c.span,
      };
    });

    return { constraints, span: group.span };
  });

  return {
    selector: decoded.selector.value,
    functionName,
    isSelectorless: decoded.isSelectorless,
    params,
    groups,
    span: decoded.span,
  };
}

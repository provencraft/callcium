import {
  DescriptorFormat as DF,
  Op,
  Scope,
  TypeCode,
  hexToBytes,
  lookupContextProperty,
  lookupOp,
  lookupScope,
  lookupTypeCode,
  parsePathSteps,
} from "@callcium/sdk";
import { type Abi, type AbiFunction, type AbiParameter, getAddress, toFunctionSelector } from "viem";
import type { DecodedPolicy, DecodedRule, Hex, Span } from "@callcium/sdk";

function readU24(data: Uint8Array, offset: number): number {
  return (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];
}

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
//                         DESCRIPTOR NAVIGATION
///////////////////////////////////////////////////////////////////////////

function skipNode(data: Uint8Array, offset: number): number {
  return lookupTypeCode(data[offset]).typeClass === "elementary"
    ? offset + DF.TYPECODE_SIZE
    : offset + (readU24(data, offset + DF.TYPECODE_SIZE) & DF.META_NODE_LENGTH_MASK);
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
  try {
    const prop = lookupContextProperty(propCode);
    return {
      pathLabel: prop.label,
      targetType: lookupTypeCode(prop.typeCode).label,
      leafTypeCode: prop.typeCode,
    };
  } catch {
    return { pathLabel: `context(${propCode})`, targetType: "uint256", leafTypeCode: TypeCode.UINT_MAX };
  }
}

///////////////////////////////////////////////////////////////////////////
//                          OPERAND DECODING
///////////////////////////////////////////////////////////////////////////

const TWO_POW_256 = 2n ** 256n;
const TWO_POW_255 = 2n ** 255n;

function decodeOperand(hex32: string, typeCode: number): string {
  const raw = BigInt(`0x${hex32}`);

  if (typeCode === TypeCode.ADDRESS) {
    const addr = `0x${hex32.slice(24)}`;
    try {
      return getAddress(addr);
    } catch {
      return addr;
    }
  }

  if (typeCode === TypeCode.BOOL) return raw === 0n ? "false" : "true";

  if (typeCode >= TypeCode.INT_MIN && typeCode <= TypeCode.INT_MAX) {
    return raw >= TWO_POW_255 ? (raw - TWO_POW_256).toString() : raw.toString();
  }

  if (typeCode >= TypeCode.UINT_MIN && typeCode <= TypeCode.UINT_MAX) return raw.toString();

  if (typeCode >= TypeCode.FIXED_BYTES_MIN && typeCode <= TypeCode.FIXED_BYTES_MAX) {
    const n = typeCode - TypeCode.FIXED_BYTES_MIN + 1;
    return `0x${hex32.slice(0, n * 2)}`;
  }

  return `0x${hex32}`;
}

function decodeOperandsFromFields(dataHex: Hex, typeCode: number, opBase: number): string[] {
  const hex = dataHex.slice(2);
  const { operands } = lookupOp(opBase);

  if (operands === "variadic") {
    const result: string[] = [];
    for (let i = 0; i < hex.length; i += 64) {
      result.push(decodeOperand(hex.slice(i, i + 64), typeCode));
    }
    return result;
  }

  if (operands === "range") {
    return [decodeOperand(hex.slice(0, 64), typeCode), decodeOperand(hex.slice(64, 128), typeCode)];
  }

  return [decodeOperand(hex.slice(0, 64), typeCode)];
}

///////////////////////////////////////////////////////////////////////////
//                            ABI MATCHING
///////////////////////////////////////////////////////////////////////////

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
      // oxlint-disable-next-line typescript/no-non-null-assertion -- key comes from constraintOrder which is populated alongside constraintMap.
      const c = constraintMap.get(key)!;
      const steps = parsePathSteps(c.path);
      const scopeLabel = lookupScope(c.scope).label;
      const isContext = c.scope === Scope.CONTEXT;
      const { pathLabel, targetType, leafTypeCode } = isContext
        ? resolveContextPath(steps)
        : resolveCalldataPath(descBytes, steps, abiInputs);

      const rules: ExplainedRule[] = c.rules.map((rule) => {
        const negated = (rule.opCode.value & Op.NOT) !== 0;
        const opBase = rule.opCode.value & ~Op.NOT;
        const baseLabel = lookupOp(opBase).label;
        const operator = negated && baseLabel === "==" ? "!=" : negated ? `not ${baseLabel}` : baseLabel;

        // Length operators always decode operands as uint256.
        const decodeTypeCode = opBase >= Op.LENGTH_EQ && opBase <= Op.LENGTH_BETWEEN ? TypeCode.UINT_MAX : leafTypeCode;

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

import {
  type ConstraintBuilder as SDKConstraintBuilder,
  Descriptor,
  DescriptorCoder,
  type Hex,
  type Issue,
  Op,
  PolicyBuilder,
  type ScalarValue,
  TypeCode,
  type TypeInfo,
  arg,
  baseFee,
  blockNumber,
  blockTimestamp,
  chainId,
  gasPrice,
  isOpAllowed,
  lookupTypeCode,
  msgSender,
  msgValue,
  txOrigin,
} from "@callcium/sdk";
import { type AbiFunction, parseAbiItem, toFunctionSignature } from "viem";
import { formatError } from "./format-error";
import { formatOpLabel } from "./format-path";

///////////////////////////////////////////////////////////////////////////
// Types
///////////////////////////////////////////////////////////////////////////

/** A parameter in the parsed function signature, with recursive type tree. */
export type ParamNode = {
  /** Index in the parent (arg index or field index). */
  index: number;
  /** Solidity type string (e.g., "address", "uint256", "tuple", "uint256[]"). */
  type: string;
  /** Human-readable name from ABI, if available. */
  name: string | null;
  /** Descriptor type info for operator compatibility queries. */
  typeInfo: TypeInfo;
  /** Tuple field children (only for tuple types). */
  children: ParamNode[] | null;
  /** Array element type (only for array types). */
  element: ParamNode | null;
};

/** A single operator + operand(s) within a constraint. */
export type OperatorRule = {
  operator: string;
  values: ScalarValue[];
};

/** User-configured constraint, ready to be translated to SDK calls. */
export type ConstraintConfig = {
  /** Stable identity for React keying. Assigned by the engine on creation. */
  id: string;
  scope: "calldata" | "context";
  /**
   * Path steps for calldata scope: arg index, then field/array indices. A quantifier
   * sentinel is its own step, immediately after the array it quantifies.
   */
  path?: number[];
  /** Context property name for context scope. */
  contextProperty?: keyof typeof CONTEXT_FACTORIES;
  /** Operator rules. At least one required. */
  rules: OperatorRule[];
};

/** A named constraint group (OR-branch). */
export type ConstraintGroup = {
  /** Stable identity for React keying. Assigned by the engine on creation. */
  id: string;
  constraints: ConstraintConfig[];
};

///////////////////////////////////////////////////////////////////////////
// Operator options
///////////////////////////////////////////////////////////////////////////

/** An operator option for the UI. */
export type OpOption = { value: string; label: string };

/** One selectable operator: its op code, its display polarity, and how it reaches the SDK builder. */
type OpMethod = {
  method: string;
  opCode: number;
  negated?: boolean;
  apply: (builder: SDKConstraintBuilder, values: ScalarValue[]) => void;
};

// Numeric operators take their operands as bigint | number; the UI parses them ahead of dispatch.
const num = (value: ScalarValue) => value as bigint | number;

const OP_METHODS: readonly OpMethod[] = [
  { method: "eq", opCode: Op.EQ, apply: (b, v) => b.eq(v[0]) },
  { method: "neq", opCode: Op.EQ, negated: true, apply: (b, v) => b.neq(v[0]) },
  { method: "eqCtx", opCode: Op.EQ_CTX, apply: (b, v) => b.eqCtx(Number(v[0])) },
  { method: "neqCtx", opCode: Op.EQ_CTX, negated: true, apply: (b, v) => b.neqCtx(Number(v[0])) },
  { method: "gt", opCode: Op.GT, apply: (b, v) => b.gt(num(v[0])) },
  { method: "lt", opCode: Op.LT, apply: (b, v) => b.lt(num(v[0])) },
  { method: "gte", opCode: Op.GTE, apply: (b, v) => b.gte(num(v[0])) },
  { method: "lte", opCode: Op.LTE, apply: (b, v) => b.lte(num(v[0])) },
  { method: "between", opCode: Op.BETWEEN, apply: (b, v) => b.between(num(v[0]), num(v[1])) },
  { method: "isIn", opCode: Op.IN, apply: (b, v) => b.isIn(v) },
  { method: "notIn", opCode: Op.IN, negated: true, apply: (b, v) => b.notIn(v) },
  { method: "bitmaskAll", opCode: Op.BITMASK_ALL, apply: (b, v) => b.bitmaskAll(v[0] as bigint) },
  { method: "bitmaskAny", opCode: Op.BITMASK_ANY, apply: (b, v) => b.bitmaskAny(v[0] as bigint) },
  { method: "bitmaskNone", opCode: Op.BITMASK_NONE, apply: (b, v) => b.bitmaskNone(v[0] as bigint) },
  { method: "lengthEq", opCode: Op.LENGTH_EQ, apply: (b, v) => b.lengthEq(num(v[0])) },
  { method: "lengthGt", opCode: Op.LENGTH_GT, apply: (b, v) => b.lengthGt(num(v[0])) },
  { method: "lengthLt", opCode: Op.LENGTH_LT, apply: (b, v) => b.lengthLt(num(v[0])) },
  { method: "lengthGte", opCode: Op.LENGTH_GTE, apply: (b, v) => b.lengthGte(num(v[0])) },
  { method: "lengthLte", opCode: Op.LENGTH_LTE, apply: (b, v) => b.lengthLte(num(v[0])) },
  { method: "lengthBetween", opCode: Op.LENGTH_BETWEEN, apply: (b, v) => b.lengthBetween(num(v[0]), num(v[1])) },
];

/** Look up the display label for an operator method name. */
export function getOperatorLabel(method: string): string {
  const entry = OP_METHODS.find((op) => op.method === method);
  if (!entry) return method;
  return formatOpLabel(entry.opCode, entry.negated ?? false);
}

/** Return the available operator options for a given type. */
export function getOperatorOptions(typeInfo: TypeInfo): OpOption[] {
  return OP_METHODS.filter((op) => isOpAllowed(op.opCode, typeInfo)).map((op) => ({
    value: op.method,
    label: formatOpLabel(op.opCode, op.negated ?? false),
  }));
}

/** Immutable session state — every mutation returns a new session. */
export type BuilderSession = {
  /** The raw signature string. */
  signature: string;
  /** Whether this is a selectorless policy. */
  isSelectorless: boolean;
  /** Parsed parameter tree. */
  params: ParamNode[];
  /** Constraint groups (OR-branches). */
  groups: ConstraintGroup[];
  /** Encoded policy hex, or null if there are errors or no constraints. */
  hex: Hex | null;
  /** Validation issues from PolicyValidator (warnings, info). */
  issues: Issue[];
  /** Structural and semantic errors (strings). */
  errors: string[];
  /** Parse error if the signature was invalid. */
  error?: string;
};

///////////////////////////////////////////////////////////////////////////
// Context property factory map
///////////////////////////////////////////////////////////////////////////

const CONTEXT_FACTORIES = {
  msgSender,
  msgValue,
  blockTimestamp,
  blockNumber,
  chainId,
  txOrigin,
  baseFee,
  gasPrice,
} as const;

///////////////////////////////////////////////////////////////////////////
// Descriptor tree walking
///////////////////////////////////////////////////////////////////////////

/** Advance past a descriptor node and return the offset after it. */
function skipNode(desc: Uint8Array, offset: number): number {
  return offset + Descriptor.nodeLength(desc, offset);
}

/** A minimal name tree extracted from viem's ABI parameter. */
export type NameTree = { name: string | null; components?: NameTree[] };

/** Walk a descriptor node and build a ParamNode tree. */
function walkDescNode(desc: Uint8Array, offset: number, index: number, nameTree: NameTree | null): ParamNode {
  const info = Descriptor.inspect(desc, offset);
  const typeCode = info.typeCode;
  const name = nameTree?.name ?? null;

  if (typeCode === TypeCode.TUPLE) {
    const fieldCount = Descriptor.tupleFieldCount(desc, offset);
    const children: ParamNode[] = [];
    let fieldOffset = Descriptor.tupleFieldOffset(desc, offset, 0);
    for (let i = 0; i < fieldCount; i++) {
      const childNameTree = nameTree?.components?.[i] ?? null;
      children.push(walkDescNode(desc, fieldOffset, i, childNameTree));
      fieldOffset = skipNode(desc, fieldOffset);
    }
    return {
      index,
      type: "tuple",
      name,
      typeInfo: info,
      children,
      element: null,
    };
  }

  if (typeCode === TypeCode.STATIC_ARRAY) {
    const length = Descriptor.staticArrayLength(desc, offset);
    // Array element inherits component names but not the array's own name.
    const elementNameTree: NameTree | null = nameTree?.components
      ? { name: null, components: nameTree.components }
      : null;
    const element = walkDescNode(desc, Descriptor.arrayElementOffset(offset), 0, elementNameTree);
    return {
      index,
      type: `${element.type}[${length}]`,
      name,
      typeInfo: info,
      children: null,
      element,
    };
  }

  if (typeCode === TypeCode.DYNAMIC_ARRAY) {
    const dynamicElementNameTree: NameTree | null = nameTree?.components
      ? { name: null, components: nameTree.components }
      : null;
    const element = walkDescNode(desc, Descriptor.arrayElementOffset(offset), 0, dynamicElementNameTree);
    return {
      index,
      type: `${element.type}[]`,
      name,
      typeInfo: info,
      children: null,
      element,
    };
  }

  // Elementary type.
  return {
    index,
    type: lookupTypeCode(typeCode).label,
    name,
    typeInfo: info,
    children: null,
    element: null,
  };
}

/** Parse a descriptor into a list of ParamNode trees. */
export function parseDescriptor(desc: Uint8Array, nameTrees: NameTree[] = []): ParamNode[] {
  const count = Descriptor.paramCount(desc);
  const params: ParamNode[] = [];
  for (let i = 0; i < count; i++) {
    const offset = Descriptor.paramOffset(desc, i);
    params.push(walkDescNode(desc, offset, i, nameTrees[i] ?? null));
  }
  return params;
}

///////////////////////////////////////////////////////////////////////////
// Constraint translation
///////////////////////////////////////////////////////////////////////////

/** Build an SDK ConstraintBuilder from a ConstraintConfig. */
function buildSDKConstraint(config: ConstraintConfig): SDKConstraintBuilder {
  if (config.rules.length === 0) {
    throw new Error("Constraint must have at least one operator rule.");
  }

  let builder: SDKConstraintBuilder;

  if (config.scope === "context") {
    if (!config.contextProperty || !(config.contextProperty in CONTEXT_FACTORIES)) {
      throw new Error("No context property selected");
    }
    const factory = CONTEXT_FACTORIES[config.contextProperty];
    builder = factory();
  } else {
    const steps = config.path!;
    builder = arg(steps[0], ...steps.slice(1));
  }

  for (const rule of config.rules) {
    const entry = OP_METHODS.find((op) => op.method === rule.operator);
    if (!entry) throw new Error(`Unknown operator: ${rule.operator}`);
    entry.apply(builder, rule.values);
  }

  return builder;
}

///////////////////////////////////////////////////////////////////////////
// Session rebuild
///////////////////////////////////////////////////////////////////////////

/** Rebuild a PolicyBuilder from session state and return hex + issues. */
function rebuild(session: BuilderSession): { hex: Hex | null; issues: Issue[]; errors: string[] } {
  const hasConstraints = session.groups.some((g) => g.constraints.length > 0);
  if (!hasConstraints || session.error !== undefined) {
    return { hex: null, issues: [], errors: [] };
  }

  const errors: string[] = [];
  let builder: PolicyBuilder;

  try {
    builder = session.isSelectorless
      ? PolicyBuilder.createRaw(session.signature)
      : PolicyBuilder.create(session.signature);
  } catch (e) {
    return { hex: null, issues: [], errors: [e instanceof Error ? e.message : String(e)] };
  }

  for (let gi = 0; gi < session.groups.length; gi++) {
    if (gi > 0) {
      try {
        builder.or();
      } catch (e) {
        errors.push(e instanceof Error ? e.message : String(e));
        continue;
      }
    }

    for (const config of session.groups[gi].constraints) {
      try {
        const sdkConstraint = buildSDKConstraint(config);
        builder.add(sdkConstraint);
      } catch (e) {
        errors.push(formatError(e));
      }
    }
  }

  if (errors.length > 0) {
    try {
      const issues = builder.validate();
      return { hex: null, issues, errors };
    } catch {
      return { hex: null, issues: [], errors };
    }
  }

  try {
    const issues = builder.validate();
    const hasErrors = issues.some((i) => i.severity === "error");
    // Strict build() rejects any issue; the exploratory builder still previews the
    // encoding for warning/info-level policies via the explicit escape hatch.
    const hex = hasErrors ? null : issues.length > 0 ? builder.buildUnsafe() : builder.build();
    return { hex, issues, errors: [] };
  } catch (e) {
    return { hex: null, issues: [], errors: [formatError(e)] };
  }
}

///////////////////////////////////////////////////////////////////////////
// Public API
///////////////////////////////////////////////////////////////////////////

/**
 * Parse a raw signature (with or without top-level names) via viem.
 * Returns the canonical types-only signature and the extracted top-level names.
 * For selectorless, the input is wrapped with a dummy function name and stripped afterwards.
 */
/** Recursively extract a name tree from a viem ABI parameter. */
export function toNameTree(param: {
  name?: string;
  components?: readonly { name?: string; components?: readonly any[] }[];
}): NameTree {
  return {
    name: param.name || null,
    components: param.components?.map(toNameTree),
  };
}

function parseRawSignature(raw: string, selectorless: boolean): { cleanSignature: string; nameTrees: NameTree[] } {
  const wrapped = selectorless ? `function __sl__(${raw})` : `function ${raw}`;
  const abiFunction = parseAbiItem(wrapped) as AbiFunction;
  const nameTrees = abiFunction.inputs.map(toNameTree);
  const canonical = toFunctionSignature(abiFunction);
  if (selectorless) {
    const open = canonical.indexOf("(");
    const close = canonical.lastIndexOf(")");
    return { cleanSignature: canonical.slice(open + 1, close), nameTrees };
  }
  return { cleanSignature: canonical, nameTrees };
}

/** Create a new builder session from a function signature (optionally with top-level names). */
export function createSession(signature: string, options?: { selectorless?: boolean }): BuilderSession {
  const selectorless = options?.selectorless ?? false;

  try {
    const { cleanSignature, nameTrees } = parseRawSignature(signature, selectorless);

    // Validate the signature by attempting to create a PolicyBuilder.
    if (selectorless) {
      PolicyBuilder.createRaw(cleanSignature);
    } else {
      PolicyBuilder.create(cleanSignature);
    }

    // Build descriptor directly.
    const types = selectorless
      ? cleanSignature
      : cleanSignature.slice(cleanSignature.indexOf("(") + 1, cleanSignature.lastIndexOf(")"));
    const desc = DescriptorCoder.fromTypes(types);
    const params = parseDescriptor(desc, nameTrees);

    return {
      signature: cleanSignature,
      isSelectorless: selectorless,
      params,
      groups: [{ id: crypto.randomUUID(), constraints: [] }],
      hex: null,
      issues: [],
      errors: [],
    };
  } catch (e) {
    return {
      signature,
      isSelectorless: selectorless,
      params: [],
      groups: [{ id: crypto.randomUUID(), constraints: [] }],
      hex: null,
      issues: [],
      errors: [],
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

/** Input config before the engine assigns an id. */
export type ConstraintInput = Omit<ConstraintConfig, "id">;

/** Add a constraint to a specific group. Returns a new session. */
export function addConstraint(session: BuilderSession, groupIndex: number, config: ConstraintInput): BuilderSession {
  const stamped: ConstraintConfig = { ...config, id: crypto.randomUUID() };
  const newGroups = session.groups.map((g, i) =>
    i === groupIndex ? { ...g, constraints: [...g.constraints, stamped] } : g,
  );
  const next: BuilderSession = { ...session, groups: newGroups };
  const { hex, issues, errors } = rebuild(next);
  return { ...next, hex, issues, errors };
}

/** Remove a constraint from a specific group. Returns a new session. */
export function removeConstraint(session: BuilderSession, groupIndex: number, constraintIndex: number): BuilderSession {
  const newGroups = session.groups.map((g, i) =>
    i === groupIndex ? { ...g, constraints: g.constraints.filter((_, ci) => ci !== constraintIndex) } : g,
  );
  const next: BuilderSession = { ...session, groups: newGroups };
  const { hex, issues, errors } = rebuild(next);
  return { ...next, hex, issues, errors };
}

/** Add a new empty constraint group. Returns a new session. */
export function addGroup(session: BuilderSession): BuilderSession {
  const newGroups = [...session.groups, { id: crypto.randomUUID(), constraints: [] }];
  return { ...session, groups: newGroups };
}

/** Remove a constraint group by index. Returns a new session. */
export function removeGroup(session: BuilderSession, groupIndex: number): BuilderSession {
  if (session.groups.length <= 1) return session;
  const newGroups = session.groups.filter((_, i) => i !== groupIndex);
  const next: BuilderSession = { ...session, groups: newGroups };
  const { hex, issues, errors } = rebuild(next);
  return { ...next, hex, issues, errors };
}

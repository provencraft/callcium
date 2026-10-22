import {
  CallciumError,
  type ConstraintBuilder as SDKConstraintBuilder,
  type DecodedNode,
  DescriptorCoder,
  type Hex,
  type Issue,
  Op,
  type Operands,
  PolicyBuilder,
  PolicyCoder,
  PolicyValidator,
  type Rule,
  type ScalarValue,
  Scope,
  Source,
  arg,
  baseFee,
  blockNumber,
  blockTimestamp,
  chainId,
  gasPrice,
  isOpAllowed,
  lookupOp,
  lookupTypeCode,
  msgSender,
  msgValue,
  parsePathSteps,
  txOrigin,
} from "@callcium/sdk";
import { type AbiFunction, parseAbiItem, toFunctionSignature } from "viem";
import { formatError } from "./format-error";
import { contextPropertyId, formatOpLabel, loopSteps } from "./format-path";

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
  /** Descriptor type code, for operator compatibility queries. */
  typeCode: number;
  /** True when the type is dynamically encoded. */
  isDynamic: boolean;
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
   * Path steps for calldata scope: arg index, then field/array indices. A quantifier sentinel is its own step,
   * immediately after the array it quantifies.
   */
  path?: number[];
  /** Context property name for context scope. */
  contextProperty?: keyof typeof CONTEXT_FACTORIES;
  /** Operator rules. At least one required. */
  rules: OperatorRule[];
};

/** A named constraint group (OR-branch). */
type ConstraintGroup = {
  /** Stable identity for React keying. Assigned by the engine on creation. */
  id: string;
  constraints: ConstraintConfig[];
};

///////////////////////////////////////////////////////////////////////////
// Operator options
///////////////////////////////////////////////////////////////////////////

/** An operator option for the UI. */
type OpOption = { value: string; label: string };

/** One selectable operator: its op code, its display polarity, and how it reaches the SDK builder. */
type OpMethod = {
  method: string;
  opCode: number;
  negated?: boolean;
  apply: (builder: SDKConstraintBuilder, values: ScalarValue[]) => void;
};

// The UI parses every numeric operand to a bigint before dispatch; this narrows the union it carries.
const big = (value: ScalarValue) => value as bigint;

/** The operator code comparing against a context property. */
const contextOp = (comparison: number) => comparison | (Source.CONTEXT << Op.SOURCE_SHIFT);

const OP_METHODS: readonly OpMethod[] = [
  { method: "eq", opCode: Op.EQ, apply: (b, v) => b.eq(v[0]) },
  { method: "neq", opCode: Op.EQ, negated: true, apply: (b, v) => b.neq(v[0]) },
  { method: "gt", opCode: Op.GT, apply: (b, v) => b.gt(big(v[0])) },
  { method: "lt", opCode: Op.LT, apply: (b, v) => b.lt(big(v[0])) },
  { method: "gte", opCode: Op.GTE, apply: (b, v) => b.gte(big(v[0])) },
  { method: "lte", opCode: Op.LTE, apply: (b, v) => b.lte(big(v[0])) },
  { method: "between", opCode: Op.BETWEEN, apply: (b, v) => b.between(big(v[0]), big(v[1])) },
  { method: "isIn", opCode: Op.IN, apply: (b, v) => b.isIn(v) },
  { method: "notIn", opCode: Op.IN, negated: true, apply: (b, v) => b.notIn(v) },
  { method: "eqCtx", opCode: contextOp(Op.EQ), apply: (b, v) => b.eqCtx(Number(v[0])) },
  { method: "neqCtx", opCode: contextOp(Op.EQ), negated: true, apply: (b, v) => b.neqCtx(Number(v[0])) },
  { method: "gtCtx", opCode: contextOp(Op.GT), apply: (b, v) => b.gtCtx(Number(v[0])) },
  { method: "ltCtx", opCode: contextOp(Op.LT), apply: (b, v) => b.ltCtx(Number(v[0])) },
  { method: "gteCtx", opCode: contextOp(Op.GTE), apply: (b, v) => b.gteCtx(Number(v[0])) },
  { method: "lteCtx", opCode: contextOp(Op.LTE), apply: (b, v) => b.lteCtx(Number(v[0])) },
  { method: "bitmaskAll", opCode: Op.BITMASK_ALL, apply: (b, v) => b.bitmaskAll(big(v[0])) },
  { method: "bitmaskAny", opCode: Op.BITMASK_ANY, apply: (b, v) => b.bitmaskAny(big(v[0])) },
  { method: "bitmaskNone", opCode: Op.BITMASK_NONE, apply: (b, v) => b.bitmaskNone(big(v[0])) },
  { method: "lengthEq", opCode: Op.LENGTH_EQ, apply: (b, v) => b.lengthEq(big(v[0])) },
  { method: "lengthGt", opCode: Op.LENGTH_GT, apply: (b, v) => b.lengthGt(big(v[0])) },
  { method: "lengthLt", opCode: Op.LENGTH_LT, apply: (b, v) => b.lengthLt(big(v[0])) },
  { method: "lengthGte", opCode: Op.LENGTH_GTE, apply: (b, v) => b.lengthGte(big(v[0])) },
  { method: "lengthLte", opCode: Op.LENGTH_LTE, apply: (b, v) => b.lengthLte(big(v[0])) },
  { method: "lengthBetween", opCode: Op.LENGTH_BETWEEN, apply: (b, v) => b.lengthBetween(big(v[0]), big(v[1])) },
];

/** Look up the operand arity for an operator method name. Unknown names read as single-operand. */
export function getOperatorArity(method: string): Operands {
  const entry = OP_METHODS.find((op) => op.method === method);
  if (!entry) return "single";
  return lookupOp(entry.opCode).operands;
}

/** Look up the display label for an operator method name. */
export function getOperatorLabel(method: string): string {
  const entry = OP_METHODS.find((op) => op.method === method);
  if (!entry) return method;
  return formatOpLabel(entry.opCode, entry.negated ?? false);
}

/** True for the operator methods whose operand names a context property instead of a value. */
export function isContextOperator(method: string): boolean {
  const entry = OP_METHODS.find((op) => op.method === method);
  return entry !== undefined && entry.opCode >> Op.SOURCE_SHIFT === Source.CONTEXT;
}

/** Return the available operator options for a target of the given type code. */
export function getOperatorOptions(typeCode: number): OpOption[] {
  return OP_METHODS.filter((op) => isOpAllowed(op.opCode, typeCode)).map((op) => ({
    value: op.method,
    label: formatOpLabel(op.opCode, op.negated ?? false),
  }));
}

/**
 * A validation issue placed in the session: `groupIndex` is the session group, and `steps` the full path of the rule it
 * names, a loop's quantifier step included; absent for an issue that names no rule.
 */
export type SessionIssue = Issue & { steps?: number[] };

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
  /** Validation issues from PolicyValidator, of every severity. */
  issues: SessionIssue[];
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

/** A minimal name tree extracted from viem's ABI parameter. */
type NameTree = { name: string | null; components?: NameTree[] };

/** Build a ParamNode tree from a descriptor node. */
function toParamNode(node: DecodedNode, index: number, nameTree: NameTree | null): ParamNode {
  const base = { index, name: nameTree?.name ?? null, typeCode: node.typeCode, isDynamic: node.isDynamic };
  // Array element inherits component names but not the array's own name.
  const elementNameTree: NameTree | null = nameTree?.components
    ? { name: null, components: nameTree.components }
    : null;

  switch (node.typeClass) {
    case "tuple":
      return {
        ...base,
        type: "tuple",
        children: node.fields.map((field, i) => toParamNode(field, i, nameTree?.components?.[i] ?? null)),
        element: null,
      };
    case "staticArray": {
      const element = toParamNode(node.element, 0, elementNameTree);
      return { ...base, type: `${element.type}[${node.length}]`, children: null, element };
    }
    case "dynamicArray": {
      const element = toParamNode(node.element, 0, elementNameTree);
      return { ...base, type: `${element.type}[]`, children: null, element };
    }
    case "elementary":
      return { ...base, type: lookupTypeCode(node.typeCode).label, children: null, element: null };
  }
}

/** Build one ParamNode tree per descriptor parameter. */
export function toParamNodes(params: DecodedNode[], nameTrees: NameTree[] = []): ParamNode[] {
  return params.map((param, i) => toParamNode(param, i, nameTrees[i] ?? null));
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

/** A builder for the session's signature. */
function newBuilder(session: BuilderSession): PolicyBuilder {
  return session.isSelectorless ? PolicyBuilder.createRaw(session.signature) : PolicyBuilder.create(session.signature);
}

/** Add each constraint of `group` to `builder`, recording the ones it refuses in `errors`. */
function addGroupConstraints(builder: PolicyBuilder, group: ConstraintGroup, errors: string[]): void {
  for (const config of group.constraints) {
    try {
      builder.add(buildSDKConstraint(config));
    } catch (e) {
      errors.push(formatError(e));
    }
  }
}

/** The full path of the rule an issue names, a loop's quantifier step included. */
function issueSteps(issue: Issue, rules: Rule[]): number[] | undefined {
  if (issue.ruleIndex === undefined || issue.path === undefined) return undefined;
  const rule = rules[issue.ruleIndex];
  if (rule.scope !== Scope.LOOP) return parsePathSteps(issue.path);
  const loop = loopSteps(rule.path, rule.quantifier);
  // A body test's path starts at the element.
  return issue.bodyRuleIndex === undefined ? loop : [...loop, ...parsePathSteps(issue.path)];
}

/** Validate one group of the session as a policy of its own. */
function groupIssues(session: BuilderSession, groupIndex: number): SessionIssue[] {
  try {
    const builder = newBuilder(session);
    addGroupConstraints(builder, session.groups[groupIndex], []);
    const blob = builder.buildUnsafe();
    const rules = PolicyCoder.decode(blob).groups[0];
    return PolicyValidator.validate(blob).map((issue) => ({ ...issue, groupIndex, steps: issueSteps(issue, rules) }));
  } catch (e) {
    if (!(e instanceof CallciumError)) throw e;
    return [];
  }
}

/** Rebuild a PolicyBuilder from session state and return hex + issues. */
function rebuild(session: BuilderSession): { hex: Hex | null; issues: SessionIssue[]; errors: string[] } {
  const hasConstraints = session.groups.some((g) => g.constraints.length > 0);
  if (!hasConstraints || session.error !== undefined) {
    return { hex: null, issues: [], errors: [] };
  }

  const errors: string[] = [];
  let builder: PolicyBuilder;

  try {
    builder = newBuilder(session);
  } catch (e) {
    return { hex: null, issues: [], errors: [formatError(e)] };
  }

  for (let gi = 0; gi < session.groups.length; gi++) {
    if (gi > 0) {
      try {
        builder.or();
      } catch (e) {
        errors.push(formatError(e));
        continue;
      }
    }
    addGroupConstraints(builder, session.groups[gi], errors);
  }

  // The policy's normal form sorts its groups and rules, so issue indices name no session position. Validation is
  // group-local: each group validates alone, and its issues are placed by their group and path.
  const issues = session.groups.flatMap((_, gi) => groupIssues(session, gi));
  if (errors.length > 0) return { hex: null, issues, errors };

  try {
    const hasErrors = issues.some((i) => i.severity === "error");
    // Strict build() rejects any issue; the exploratory builder still previews the encoding for warning/info-level
    // policies via the explicit escape hatch.
    const hex = hasErrors ? null : issues.length > 0 ? builder.buildUnsafe() : builder.build();
    return { hex, issues, errors: [] };
  } catch (e) {
    return { hex: null, issues: [], errors: [formatError(e)] };
  }
}

/** True when `issue` names a rule `config` adds: a test on its path, or the loop its path passes through. */
export function issueMatches(issue: SessionIssue, config: ConstraintInput): boolean {
  const { steps } = issue;
  if (steps === undefined) return false;
  if (config.scope === "context") {
    return issue.scope === Scope.CONTEXT && steps[0] === contextPropertyId(config.contextProperty ?? "");
  }
  const path = config.path ?? [];
  if (issue.scope === Scope.LOOP) return steps.every((step, i) => path[i] === step);
  return issue.scope === Scope.CALLDATA && steps.length === path.length && steps.every((step, i) => path[i] === step);
}

///////////////////////////////////////////////////////////////////////////
// Public API
///////////////////////////////////////////////////////////////////////////

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

/**
 * Parse a raw signature, with or without parameter names, via viem. Returns the canonical signature (types only when
 * selectorless) and one name tree per parameter.
 */
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
    const params = toParamNodes(DescriptorCoder.inspect(DescriptorCoder.fromTypes(types)).params, nameTrees);

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
      error: formatError(e),
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

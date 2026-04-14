///////////////////////////////////////////////////////////////////////////
// Primitives
///////////////////////////////////////////////////////////////////////////

/** Hex-encoded byte string, 0x-prefixed. */
export type Hex = `0x${string}`;

/** Ethereum address, 0x-prefixed. */
export type Address = `0x${string}`;

/** Byte range in a source blob. */
export type Span = { start: number; end: number };

///////////////////////////////////////////////////////////////////////////
// Descriptor AST (internal — not exported from index.ts)
///////////////////////////////////////////////////////////////////////////

/** Shared properties for all descriptor node variants. */
type DescNodeBase = {
  typeCode: number;
  isDynamic: boolean;
  /** ABI head size in bytes; 0 if dynamic. */
  staticSize: number;
  /** Byte range in the descriptor blob. Present after decoding. */
  span?: Span;
};

export type ElementaryNode = DescNodeBase & { type: "elementary" };

export type TupleNode = DescNodeBase & {
  type: "tuple";
  /** Tuple field descriptors, in declaration order. */
  fields: DescNode[];
};

export type StaticArrayNode = DescNodeBase & {
  type: "staticArray";
  /** The element type descriptor. */
  element: DescNode;
  /** Fixed number of elements declared in the type. */
  length: number;
};

export type DynamicArrayNode = DescNodeBase & {
  type: "dynamicArray";
  /** The element type descriptor. */
  element: DescNode;
};

/** Recursive AST node representing one type in a descriptor tree. */
export type DescNode = ElementaryNode | TupleNode | StaticArrayNode | DynamicArrayNode;

///////////////////////////////////////////////////////////////////////////
// Enforce
///////////////////////////////////////////////////////////////////////////

/**
 * Execution context for context-scoped rules.
 * Each property maps to a well-known EVM execution environment value.
 * Only the properties referenced by the policy need to be supplied.
 */
export type Context = {
  msgSender?: Address;
  msgValue?: bigint;
  blockTimestamp?: bigint;
  blockNumber?: bigint;
  chainId?: bigint;
  txOrigin?: Address;
};

/** Result of enforcing a policy: pass with matched group index, or fail with one violation per failed group. */
export type EnforceResult = { ok: true; matchedGroup: number } | { ok: false; violations: Violation[] };

/** Machine-readable reason code for an enforcement violation. */
export type ViolationCode =
  | "VALUE_MISMATCH"
  | "SELECTOR_MISMATCH"
  | "MISSING_SELECTOR"
  | "CALLDATA_OUT_OF_BOUNDS"
  | "ARRAY_INDEX_OUT_OF_BOUNDS"
  | "MISSING_CONTEXT"
  | "QUANTIFIER_LIMIT_EXCEEDED"
  | "QUANTIFIER_EMPTY_ARRAY";

/** Details of a single rule failure during enforcement. */
export type Violation = {
  /** Group index that failed. Absent for pre-group failures (e.g. selector mismatch). */
  group?: number;
  /** Rule index within the group. Absent for pre-rule failures. */
  rule?: number;
  code: ViolationCode;
  message: string;
  /** Rule path that was being evaluated when the violation occurred. */
  path?: Hex;
  /** The actual value found in calldata or context, for diagnostic display. */
  resolvedValue?: Hex;
};

///////////////////////////////////////////////////////////////////////////
// Canonical policy types
///////////////////////////////////////////////////////////////////////////

/** Canonical structured representation of a policy. */
export type PolicyData = {
  isSelectorless: boolean;
  selector: Hex;
  descriptor: Hex;
  groups: Constraint[][];
  span?: Span;
};

/** A collection of operators targeting a specific value. */
export type Constraint = {
  scope: number;
  path: Hex;
  operators: Hex[];
  span?: Span;
};

///////////////////////////////////////////////////////////////////////////
// Structural inspection types
///////////////////////////////////////////////////////////////////////////

/** A decoded value with its byte position in the source blob. */
export type Field<T> = { value: T; span: Span };

/** Structural representation of a decoded parameter within the descriptor. */
export type DecodedParam = {
  index: number;
  typeCode: number;
  isDynamic: boolean;
  staticSize: number;
  path: Hex;
  span: Span;
};

/** Structural representation of a decoded rule with per-field spans. */
export type DecodedRule = {
  ruleSize: Field<number>;
  scope: Field<number>;
  pathDepth: Field<number>;
  path: Field<Hex>;
  opCode: Field<number>;
  dataLength: Field<number>;
  data: Field<Hex>;
  span: Span;
};

/** Structural representation of a decoded group with metadata spans. */
export type DecodedGroup = {
  ruleCount: Field<number>;
  groupSize: Field<number>;
  rules: DecodedRule[];
  span: Span;
};

/** Structural representation of a decoded policy with full byte-level spans. */
export type DecodedPolicy = {
  header: Field<number>;
  selector: Field<Hex>;
  descLength: Field<number>;
  descriptor: { raw: Hex; header: Field<{ version: number; paramCount: number }>; params: DecodedParam[]; span: Span };
  groupCount: Field<number>;
  groups: DecodedGroup[];
  span: Span;
  version: number;
  isSelectorless: boolean;
};

///////////////////////////////////////////////////////////////////////////
// Validation issues
///////////////////////////////////////////////////////////////////////////

/** Severity of a validation issue. */
export type IssueSeverity = "info" | "warning" | "error";

/** Category of a validation issue. */
export type IssueCategory = "typeMismatch" | "contradiction" | "redundancy" | "vacuity";

/** A single validation issue found during policy analysis. */
export type Issue = {
  severity: IssueSeverity;
  category: IssueCategory;
  groupIndex: number;
  constraintIndex: number;
  code: string;
  value1: Hex;
  value2: Hex;
  message: string;
};

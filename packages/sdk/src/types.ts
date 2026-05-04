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

/** Subset of violation codes emitted by reader/navigation primitives. */
export type NavigationViolationCode = "CALLDATA_OUT_OF_BOUNDS" | "ARRAY_INDEX_OUT_OF_BOUNDS";

/** Calldata is shorter than the policy's selector slot. */
export type MissingSelectorViolation = {
  code: "MISSING_SELECTOR";
};

/** Calldata selector does not match the policy's expected selector. */
export type SelectorMismatchViolation = {
  code: "SELECTOR_MISMATCH";
  /** Selector declared by the policy. */
  expectedValue: Hex;
  /** Selector observed in the calldata. */
  resolvedValue: Hex;
};

/**
 * A context-scoped rule referenced a property not supplied in the execution context.
 *
 * `opCode` and `operandData` may be added in future versions as diagnostic context
 * without breaking the contract; consumers should tolerate their presence.
 */
export type MissingContextViolation = {
  code: "MISSING_CONTEXT";
  group: number;
  rule: number;
  scope: number;
  path: Hex;
  /** Declared type of the missing context property. */
  typeCode: number;
  opCode?: number;
  operandData?: Hex;
};

/**
 * A rule's operator returned false against the loaded value.
 *
 * Field combinations:
 * - `resolvedValue` present, `elementIndex` absent — scalar leaf or context value that failed the operator.
 * - `resolvedValue` present, `elementIndex` present — universal-quantifier per-element failure.
 * - `resolvedValue` absent, `elementIndex` absent — existential-aggregate failure (no element satisfied).
 * - `resolvedValue` absent, `elementIndex` present — per-element failure where the leaf could not be loaded.
 *
 * For length operations (`isLengthOp(opCode)`), `resolvedValue` is a hex-encoded count
 * rather than a 32-byte ABI word.
 */
export type ValueMismatchViolation = {
  code: "VALUE_MISMATCH";
  group: number;
  rule: number;
  scope: number;
  path: Hex;
  /** Operator code with the `Op.NOT` bit intact. */
  opCode: number;
  /** Full untruncated operand bytes declared by the rule. */
  operandData: Hex;
  /** Type code of the failing value's leaf. */
  typeCode: number;
  resolvedValue?: Hex;
  elementIndex?: number;
};

/**
 * Single-code shape for a calldata-navigation failure. Internal helper for de-duplication.
 * @internal
 */
type CalldataNavigationVariant<C extends NavigationViolationCode> = {
  code: C;
  group: number;
  rule: number;
  scope: number;
  path: Hex;
  opCode?: number;
  operandData?: Hex;
  typeCode?: number;
  elementIndex?: number;
};

/**
 * Calldata structure prevented the rule from being evaluated.
 *
 * The operator was never applied; `opCode`, `operandData`, `typeCode`, and `elementIndex`
 * are diagnostic context describing the failing site, not a constraint claim. Renderers
 * must not summarise these as "constraint violated".
 *
 * Encoded as a union of per-code variants so consumers can narrow on a single code via
 * `Extract<Violation, { code: "..." }>`.
 */
export type CalldataNavigationViolation =
  | CalldataNavigationVariant<"CALLDATA_OUT_OF_BOUNDS">
  | CalldataNavigationVariant<"ARRAY_INDEX_OUT_OF_BOUNDS">;

/** A quantified array exceeded `Limits.MAX_QUANTIFIED_ARRAY_LENGTH`. */
export type QuantifierLimitExceededViolation = {
  code: "QUANTIFIER_LIMIT_EXCEEDED";
  group: number;
  rule: number;
  scope: number;
  path: Hex;
  /** Hex-encoded element count of the offending array. */
  resolvedValue: Hex;
};

/** A quantifier (`ANY` or `ALL`) was applied to an empty array. */
export type QuantifierEmptyArrayViolation = {
  code: "QUANTIFIER_EMPTY_ARRAY";
  group: number;
  rule: number;
  scope: number;
  path: Hex;
};

/**
 * Structured details of a single rule failure during enforcement.
 *
 * Carries semantic data only — message strings are the consumer's responsibility.
 * Discriminate on `code` to narrow to the matching variant.
 */
export type Violation =
  | MissingSelectorViolation
  | SelectorMismatchViolation
  | MissingContextViolation
  | ValueMismatchViolation
  | CalldataNavigationViolation
  | QuantifierLimitExceededViolation
  | QuantifierEmptyArrayViolation;

/** Machine-readable reason code for an enforcement violation. Derived from `Violation` to prevent drift. */
export type ViolationCode = Violation["code"];

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

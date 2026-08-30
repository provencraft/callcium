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
  baseFee?: bigint;
  gasPrice?: bigint;
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
 * A rule referenced a context property not supplied in the execution context — a context-scoped
 * subject, or an `EQ_CTX` operand on either scope.
 */
export type MissingContextViolation = {
  code: "MISSING_CONTEXT";
  group: number;
  rule: number;
  scope: number;
  path: Hex;
  /** Declared type of the missing context property. */
  typeCode: number;
  /** Operator code with the `Op.NOT` bit intact; absent for a context-scoped subject. */
  opCode?: number;
  /** Operator payload; absent for a context-scoped subject. */
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
  /**
   * Resolved runtime value of a reference operand as a 32-byte word; present when the
   * operator's operand names a reference resolved at enforcement, not a literal.
   */
  resolvedOperand?: Hex;
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
 * are diagnostic context describing the failing site, not a constraint claim.
 *
 * A union of per-code variants, narrowable with `Extract<Violation, { code: "..." }>`.
 */
export type CalldataNavigationViolation =
  | CalldataNavigationVariant<"CALLDATA_OUT_OF_BOUNDS">
  | CalldataNavigationVariant<"ARRAY_INDEX_OUT_OF_BOUNDS">;

/** A quantified array exceeded `PolicyFormat.MAX_QUANTIFIED_ARRAY_LENGTH`. */
export type QuantifierLimitExceededViolation = {
  code: "QUANTIFIER_LIMIT_EXCEEDED";
  group: number;
  rule: number;
  scope: number;
  path: Hex;
  /** Hex-encoded element count of the offending array. */
  resolvedValue: Hex;
};

/**
 * A resolved word is not the canonical encoding of its declared type.
 *
 * `resolvedValue` is the raw 32-byte word as it appeared in calldata, before any masking.
 */
export type NonCanonicalValueViolation = {
  code: "NON_CANONICAL_VALUE";
  group: number;
  rule: number;
  scope: number;
  path: Hex;
  /** Type code of the target whose encoding was violated. */
  typeCode: number;
  /** Raw 32-byte word as it appeared in calldata, before any masking. */
  resolvedValue: Hex;
  opCode?: number;
  operandData?: Hex;
  elementIndex?: number;
};

/** An `ANY` quantifier was applied to an empty array. */
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
 * Carries semantic data only; no message strings.
 * Discriminate on `code` to narrow to the matching variant.
 */
export type Violation =
  | MissingSelectorViolation
  | SelectorMismatchViolation
  | MissingContextViolation
  | ValueMismatchViolation
  | CalldataNavigationViolation
  | NonCanonicalValueViolation
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
  /** Compiled hint block as carried on the wire; absent when the constraint has no encoding. */
  hint?: Hex;
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
  /** Compiled hint block; present for calldata rules only. */
  hint?: Field<Hex>;
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
export type IssueCategory = "typeMismatch" | "contradiction" | "redundancy" | "vacuity" | "compatibility";

/**
 * Machine-readable code for a policy validation issue.
 *
 * Each code names one finding of the semantic validator and matches the constant of the same
 * name in the Solidity `IssueCode` library.
 */
export type IssueCode =
  // Type mismatch.
  | "VALUE_OP_ON_DYNAMIC"
  | "VALUE_OP_ON_COMPOSITE"
  | "NUMERIC_OP_ON_NON_NUMERIC"
  | "BITMASK_ON_INVALID"
  | "IN_ON_BOOL"
  | "LENGTH_ON_STATIC"
  | "CONTEXT_TYPE_MISMATCH"
  | "UNKNOWN_OPERATOR"
  | "NON_CANONICAL_OPERAND"
  | "UNNAVIGABLE_PATH"
  | "NESTED_QUANTIFIER"
  | "HINT_MISMATCH"
  // Contradiction.
  | "EQ_NEQ_CONTRADICTION"
  | "CONFLICTING_EQUALITY"
  | "OUT_OF_PHYSICAL_BOUNDS"
  | "IMPOSSIBLE_GT"
  | "IMPOSSIBLE_LT"
  | "BOUNDS_EXCLUDE_EQUALITY"
  | "IMPOSSIBLE_RANGE"
  | "SET_EXCLUDES_EQUALITY"
  | "EMPTY_SET_INTERSECTION"
  | "SET_FULLY_EXCLUDED"
  | "LENGTH_EQ_NEQ_CONTRADICTION"
  | "CONFLICTING_LENGTH"
  | "BOUNDS_EXCLUDE_LENGTH"
  | "IMPOSSIBLE_LENGTH_RANGE"
  | "OUT_OF_PHYSICAL_LENGTH_BOUNDS"
  | "IMPOSSIBLE_LENGTH_GT"
  | "IMPOSSIBLE_LENGTH_LT"
  | "BITMASK_CONTRADICTION"
  | "BITMASK_ANY_IMPOSSIBLE"
  | "UNSORTED_IN_SET"
  | "EMPTY_GROUP"
  // Redundancy.
  | "DOMINATED_BOUND"
  | "REDUNDANT_BOUND"
  | "SET_REDUCTION"
  | "SET_REDUNDANCY"
  | "SET_PARTIALLY_EXCLUDED"
  | "DOMINATED_LENGTH_BOUND"
  | "REDUNDANT_LENGTH_BOUND"
  | "REDUNDANT_BITMASK"
  | "DUPLICATE_CONSTRAINT"
  | "FUSIBLE_RANGE"
  | "FUSIBLE_LENGTH_RANGE"
  // Vacuity.
  | "VACUOUS_GTE"
  | "VACUOUS_LTE"
  | "VACUOUS_LENGTH_GTE"
  | "VACUOUS_LENGTH_LTE"
  | "VACUOUS_NEGATED_RANGE"
  | "VACUOUS_NEGATED_LENGTH_RANGE"
  // Compatibility.
  | "PATH_DEPTH_EXCEEDED"
  | "QUANTIFIER_OVER_STATIC_LIMIT"
  | "UNKNOWN_CONTEXT_PROPERTY"
  | "NEGATION_UNDER_ANY";

/** A single validation issue found during policy analysis. */
export type Issue = {
  severity: IssueSeverity;
  category: IssueCategory;
  groupIndex: number;
  constraintIndex: number;
  code: IssueCode;
  value1: Hex;
  value2: Hex;
  message: string;
};

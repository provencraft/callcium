import type { ComparisonCode, QuantifierCode, Scope, ScopeCode, Source } from "./constants";

///////////////////////////////////////////////////////////////////////////
// Primitives
///////////////////////////////////////////////////////////////////////////

/** Hex-encoded byte string, 0x-prefixed. */
export type Hex = `0x${string}`;

/** Ethereum address, 0x-prefixed. */
export type Address = `0x${string}`;

/** Byte range in a source blob. */
export type Span = { start: number; end: number };

/** A decoded value with its byte position in the source blob. */
export type Field<T> = { value: T; span: Span };

///////////////////////////////////////////////////////////////////////////
// Enforce
///////////////////////////////////////////////////////////////////////////

/**
 * Execution context for context-scoped rules. Each property maps to a well-known EVM execution environment value. Only
 * the properties referenced by the policy need to be supplied.
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
 * A test read a context property not supplied in the execution context — a context test's subject, or a context
 * operand on either kind of test.
 *
 * `group` and `rule` locate the root rule. A test in a loop body adds `bodyRule` and `elementIndex`.
 */
export type MissingContextViolation = {
  code: "MISSING_CONTEXT";
  group: number;
  rule: number;
  scope: ScopeCode;
  /** The test's path: a context test's property ID, or a calldata test's steps (in a loop body, from the element). */
  path: Hex;
  /** Declared type of the missing context property. */
  typeCode: number;
  /** The test's operator, absent for a context test's subject. */
  operator?: DecodedOperator;
  /** Position of the test in the loop body, absent for a root test. */
  bodyRule?: number;
  /** Position of the element the body test read, absent for a root test. */
  elementIndex?: number;
};

/**
 * A test's operator returned false against the loaded value.
 *
 * `resolvedValue` is the value the operator compared: a word, or for length operators the length as a 32-byte word.
 * `group` and `rule` locate the root rule. A test in a loop body adds `bodyRule` and `elementIndex`.
 */
export type ValueMismatchViolation = {
  code: "VALUE_MISMATCH";
  group: number;
  rule: number;
  scope: ScopeCode;
  /** The test's path: a context test's property ID, or a calldata test's steps (in a loop body, from the element). */
  path: Hex;
  /** The test's operator. */
  operator: DecodedOperator;
  /** Type code of the failing value. */
  typeCode: number;
  resolvedValue: Hex;
  /**
   * Resolved runtime value of a context operand as a 32-byte word, present when the operator's operand names a context
   * property, not a constant.
   */
  resolvedOperand?: Hex;
  /** Position of the test in the loop body, absent for a root test. */
  bodyRule?: number;
  /** Position of the element the body test read, absent for a root test. */
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
  scope: ScopeCode;
  path: Hex;
  operator?: DecodedOperator;
  typeCode?: number;
  bodyRule?: number;
  elementIndex?: number;
};

/**
 * Calldata structure prevented a rule from being evaluated.
 *
 * The operator was never applied. `operator`, `typeCode`, `bodyRule` and `elementIndex` are diagnostic context
 * describing the failing site, not a constraint claim. A failure resolving a loop's array carries the loop
 * rule's scope and array path and no operator. A failure resolving an element adds `elementIndex`. A failure in a body
 * test adds the test's fields and `bodyRule`.
 *
 * A union of per-code variants, narrowable with `Extract<Violation, { code: "..." }>`.
 */
export type CalldataNavigationViolation =
  | CalldataNavigationVariant<"CALLDATA_OUT_OF_BOUNDS">
  | CalldataNavigationVariant<"ARRAY_INDEX_OUT_OF_BOUNDS">;

/** A loop's array exceeded `MAX_QUANTIFIED_ARRAY_LENGTH`. */
export type QuantifierLimitExceededViolation = {
  code: "QUANTIFIER_LIMIT_EXCEEDED";
  group: number;
  rule: number;
  scope: ScopeCode;
  /** The loop's array path. */
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
  scope: ScopeCode;
  path: Hex;
  /** Type code of the target whose encoding was violated. */
  typeCode: number;
  /** Raw 32-byte word as it appeared in calldata, before any masking. */
  resolvedValue: Hex;
  /** The test's operator. */
  operator: DecodedOperator;
  /** Position of the test in the loop body, absent for a root test. */
  bodyRule?: number;
  /** Position of the element the body test read, absent for a root test. */
  elementIndex?: number;
};

/** No element satisfied an `ANY` loop's body, the empty array included. No element and no test is to blame. */
export type QuantifierNoMatchViolation = {
  code: "QUANTIFIER_NO_MATCH";
  group: number;
  rule: number;
  scope: ScopeCode;
  /** The loop's array path. */
  path: Hex;
};

/**
 * Structured details of a single rule failure during enforcement.
 *
 * Carries semantic data only, with no message strings. Discriminate on `code` to narrow to the matching variant.
 */
export type Violation =
  | MissingSelectorViolation
  | SelectorMismatchViolation
  | MissingContextViolation
  | ValueMismatchViolation
  | CalldataNavigationViolation
  | NonCanonicalValueViolation
  | QuantifierLimitExceededViolation
  | QuantifierNoMatchViolation;

/** Machine-readable reason code for an enforcement violation. Derived from `Violation` to prevent drift. */
export type ViolationCode = Violation["code"];

///////////////////////////////////////////////////////////////////////////
// Policy types
///////////////////////////////////////////////////////////////////////////

/** A test or a context test of a loop body, or of a group. */
export type BodyRule = {
  scope: typeof Scope.CONTEXT | typeof Scope.CALLDATA;
  /** BE16-encoded path from the starting point. A context test's path is its property ID. */
  path: Hex;
  /** The hint a blob carries for the path, absent for a context test and in data not read from a blob. */
  hint?: Hex;
  /** Encoded operator: opCode(1) || each operand value as a 32-byte word, a context property as its ID. */
  operator: Hex;
};

/** A loop: its body over each element of the array at `path`. */
export type LoopRule = {
  scope: typeof Scope.LOOP;
  quantifier: QuantifierCode;
  /** BE16-encoded path from the arguments to the array. */
  path: Hex;
  /** The frame hint a blob carries for the path, absent in data not read from a blob. */
  hint?: Hex;
  body: BodyRule[];
};

/** A rule of a group: a test, a context test or a loop. */
export type Rule = BodyRule | LoopRule;

/** A policy: its selector, its descriptor and its groups of rules. */
export type PolicyData = {
  isSelectorless: boolean;
  selector: Hex;
  descriptor: Hex;
  groups: Rule[][];
};

/**
 * An operator as a policy stores it: its comparison, its polarity and its operands. Constants are loaded to 32-byte
 * words of `operandType`. A context operand names its property.
 */
export type DecodedOperator = {
  /** Operator code with the `Op.NOT` bit intact. */
  opCode: number;
  /** Comparison bits of `opCode`. */
  comparison: ComparisonCode;
  /** True when `opCode` carries the `Op.NOT` bit. */
  negated: boolean;
  /**
   * Type code of the operands: the target's type, the type a length compares as for a length comparison,
   * or the context property's type.
   */
  operandType: number;
} & (
  | {
      source: typeof Source.CONSTANT;
      /** Each constant loaded to its 32-byte word. */
      values: Hex[];
    }
  | {
      source: typeof Source.CONTEXT;
      /** The context property the operand names. */
      contextPropertyId: number;
    }
);

/** A collection of operators targeting a specific value. */
export type Constraint = {
  scope: typeof Scope.CONTEXT | typeof Scope.CALLDATA;
  path: Hex;
  operators: Hex[];
};

///////////////////////////////////////////////////////////////////////////
// Inspection
///////////////////////////////////////////////////////////////////////////

/** A descriptor node: its type, its head size and the bytes it spans, with its fields or its element. */
export type DecodedNode = {
  typeCode: number;
  isDynamic: boolean;
  /** Head size in bytes, zero for a dynamic type. */
  staticSize: number;
  span: Span;
} & (
  | { typeClass: "elementary" }
  | { typeClass: "tuple"; fields: DecodedNode[] }
  | { typeClass: "staticArray"; length: number; element: DecodedNode }
  | { typeClass: "dynamicArray"; element: DecodedNode }
);

/** A descriptor: its header fields and one node per parameter. */
export type DecodedDescriptor = {
  version: Field<number>;
  paramCount: Field<number>;
  params: DecodedNode[];
  span: Span;
};

/** An array's meta word. */
export type ArrayMeta = {
  /** The element type is dynamic. An offset word points to each element. */
  isElementDynamic: boolean;
  /** The array is dynamic. A length word is before the elements. */
  isDynamicArray: boolean;
  /** Element head size in words. */
  strideWords: number;
};

/** A hop of a compiled hint: a plain hop enters the node behind an offset word, an element hop selects an element. */
export type DecodedHop = {
  kind: "plain" | "element";
  delta: Field<number>;
  index: Field<number>;
  meta: Field<ArrayMeta>;
  span: Span;
};

/** A test hint: its hops, then the target's position, meta word and type code. */
export type DecodedHint = {
  hopCount: Field<number>;
  hops: DecodedHop[];
  targetDelta: Field<number>;
  /** The target's meta word. Every field is false or zero unless the target is a dynamic array. */
  targetMeta: Field<ArrayMeta>;
  typeCode: Field<number>;
  span: Span;
};

/** A frame hint: its hops, then the array's position, declared length and meta word. */
export type DecodedFrameHint = {
  hopCount: Field<number>;
  hops: DecodedHop[];
  arrayDelta: Field<number>;
  /** Declared length of a static array, or zero for a dynamic array. */
  count: Field<number>;
  meta: Field<ArrayMeta>;
  span: Span;
};

/** A test or a context test, each field with the bytes that contain it. */
export type DecodedTest = {
  ruleSize: Field<number>;
  scope: Field<typeof Scope.CONTEXT | typeof Scope.CALLDATA>;
  pathDepth: Field<number>;
  /** The path steps, or a context test's property ID. */
  path: Field<Hex>;
  /** The test hint, absent for a context test. */
  hint?: DecodedHint;
  /** Type code of the target: the hint's, or the context property's. */
  targetType: number;
  opCode: Field<number>;
  dataLength: Field<number>;
  /** The operands as stored. */
  data: Field<Hex>;
  operator: DecodedOperator;
  span: Span;
};

/** A loop rule, each field with the bytes that contain it. */
export type DecodedLoop = {
  ruleSize: Field<number>;
  scope: Field<typeof Scope.LOOP>;
  quantifier: Field<QuantifierCode>;
  pathDepth: Field<number>;
  /** The array's path. */
  path: Field<Hex>;
  hint: DecodedFrameHint;
  ruleCount: Field<number>;
  body: DecodedTest[];
  span: Span;
};

/** A rule of a group: a test, a context test or a loop. */
export type DecodedRule = DecodedTest | DecodedLoop;

/** A group, each field with the bytes that contain it. */
export type DecodedGroup = {
  ruleCount: Field<number>;
  groupSize: Field<number>;
  rules: DecodedRule[];
  span: Span;
};

/** A policy blob, each field with the bytes that contain it. */
export type DecodedPolicy = {
  header: Field<{ major: number; minor: number; isSelectorless: boolean }>;
  /** The selector slot, zero for a selectorless policy. */
  selector: Field<Hex>;
  descLength: Field<number>;
  descriptor: DecodedDescriptor;
  groupCount: Field<number>;
  groups: DecodedGroup[];
  span: Span;
};

///////////////////////////////////////////////////////////////////////////
// Validation
///////////////////////////////////////////////////////////////////////////

/** Severity of a validation issue. */
export type IssueSeverity = "info" | "warning" | "error";

/** Kind of defect a validation issue reports. */
export type IssueCategory = "typeMismatch" | "contradiction" | "redundancy" | "vacuity" | "compatibility";

/** Machine-readable code of a validation issue. */
export type IssueCode =
  | "INVALID_DESCRIPTOR"
  | "UNNAVIGABLE_PATH"
  | "QUANTIFIER_ON_NON_ARRAY"
  | "HINT_MISMATCH"
  | "NUMERIC_OP_ON_NON_NUMERIC"
  | "BITMASK_ON_INVALID"
  | "IN_ON_BOOL"
  | "CONTEXT_TYPE_MISMATCH"
  | "OUT_OF_PHYSICAL_BOUNDS"
  | "CONTRADICTORY_RULE"
  | "REDUNDANT_RULE"
  | "DOMINATED_BOUND"
  | "DOMINATED_LENGTH_BOUND"
  | "VACUOUS_RULE"
  | "QUANTIFIER_OVER_STATIC_LIMIT"
  | "CONTEXT_ONLY_BODY";

/**
 * The rule an issue names: its group, its position in the group and, for a test in a loop body, its position in the
 * body. The location also carries the rule's scope, path and operator as decoded.
 * A path in a body starts at the element.
 */
export type RuleLocation = {
  groupIndex: number;
  ruleIndex: number;
  bodyRuleIndex?: number;
  scope: ScopeCode;
  path: Hex;
  operator?: Hex;
};

/** A validation issue: the rule it names, absent for one about the descriptor, and the values that show the defect. */
export type Issue = Partial<RuleLocation> & {
  severity: IssueSeverity;
  category: IssueCategory;
  code: IssueCode;
  value1: Hex;
  value2: Hex;
  message: string;
};

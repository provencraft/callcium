/**
 * Machine-readable error code for structural decoding and validation failures.
 *
 * Each code names one invariant and matches the Solidity error raised for the same
 * invariant, transliterated from `PascalCase` to `SCREAMING_SNAKE_CASE`.
 */
export type CallciumErrorCode =
  // Policy and descriptor framing.
  | "UNSUPPORTED_VERSION"
  | "MALFORMED_HEADER"
  | "UNEXPECTED_END"
  | "TRAILING_BYTES"
  // Groups and rules.
  | "EMPTY_POLICY"
  | "EMPTY_GROUP"
  | "GROUP_TOO_SMALL"
  | "GROUP_SIZE_MISMATCH"
  | "GROUP_OVERFLOW"
  | "RULE_TOO_SMALL"
  | "RULE_SIZE_MISMATCH"
  | "RULE_FIELD_OUT_OF_BOUNDS"
  | "RULE_OVERFLOW"
  // Paths.
  | "EMPTY_PATH"
  | "MALFORMED_PATH"
  | "PATH_TOO_DEEP"
  | "PARAM_INDEX_OUT_OF_BOUNDS"
  | "TUPLE_FIELD_OUT_OF_BOUNDS"
  | "STATIC_ARRAY_INDEX_OUT_OF_BOUNDS"
  | "NOT_COMPOSITE"
  | "UNCOMPILABLE_PATH"
  | "QUANTIFIER_ON_NON_ARRAY"
  | "NESTED_QUANTIFIER"
  // Scope and context.
  | "INVALID_SCOPE"
  | "INVALID_CONTEXT_PATH"
  | "UNKNOWN_CONTEXT_PROPERTY"
  // Operators and hints.
  | "UNKNOWN_OPERATOR"
  | "INVALID_OPERATOR_BYTES"
  | "OPERATOR_TARGET_MISMATCH"
  | "UNSORTED_IN_SET"
  | "MALFORMED_HINT"
  // Constraint building.
  | "NO_CONSTRAINT_OPERATORS"
  | "DUPLICATE_PATH_IN_GROUP"
  | "EMPTY_SET"
  | "SET_TOO_LARGE"
  | "INVALID_RANGE"
  // Descriptor nodes.
  | "UNKNOWN_TYPE_CODE"
  | "NODE_LENGTH_TOO_SMALL"
  | "NODE_LENGTH_TOO_LARGE"
  | "NODE_OVERFLOW"
  | "NESTING_TOO_DEEP"
  | "INVALID_ARRAY_LENGTH"
  | "INVALID_TUPLE_FIELD_COUNT"
  | "STATIC_WORDS_TOO_LARGE"
  | "PARAM_COUNT_MISMATCH"
  | "TOO_MANY_PARAMS"
  // Type strings and signatures.
  | "MALFORMED_TYPE_STRING"
  | "UNKNOWN_TYPE"
  | "MALFORMED_SIGNATURE"
  | "SIGNATURE_CONTAINS_WHITESPACE"
  | "INVALID_FUNCTION_NAME"
  // Encoder field widths.
  | "GROUP_COUNT_OVERFLOW"
  | "RULE_COUNT_OVERFLOW"
  | "RULE_SIZE_OVERFLOW"
  | "DESC_LENGTH_OVERFLOW"
  // Inputs and validation.
  | "UNKNOWN_QUANTIFIER"
  | "INVALID_HEX"
  | "VALIDATION_ERROR";

/**
 * Thrown when a policy or descriptor blob is structurally malformed.
 * The optional `offset` indicates the byte position in the source blob where the error was detected.
 */
export class CallciumError extends Error {
  public readonly code: CallciumErrorCode;
  /** Byte position in the source blob where the error was detected, if applicable. */
  public readonly offset?: number;

  constructor(code: CallciumErrorCode, message: string, offset?: number) {
    const prefix = offset !== undefined ? `[offset ${offset}] ` : "";
    super(`${prefix}${message}`);
    this.name = "CallciumError";
    this.code = code;
    Object.setPrototypeOf(this, CallciumError.prototype);
  }
}

/**
 * Thrown by `PolicyBuilder.build` when validation reports any issue.
 *
 * Carries every issue the validator found. The `Error.message` is the first issue's
 * message — a diagnostic summary, not a presentation contract. Consumers rendering
 * issues to users should iterate `issues` directly.
 */
export class ValidationError extends CallciumError {
  public readonly issues: import("./types").Issue[];

  constructor(issues: import("./types").Issue[]) {
    super("VALIDATION_ERROR", issues[0]?.message ?? "Policy validation failed");
    this.name = "ValidationError";
    this.issues = issues;
    Object.setPrototypeOf(this, ValidationError.prototype);
  }
}

/**
 * Thrown by `PolicyEnforcer.enforce` when calldata fails policy enforcement.
 * Distinct from `ValidationError`, which signals static issues in the policy itself.
 *
 * Carries the full list of structured violations (one per failed group). The
 * `Error.message` is a minimal non-lossy diagnostic summary built from the
 * first violation's structured fields — not a presentation contract. Consumers
 * rendering violations to users should iterate `violations` directly.
 */
export class PolicyViolationError extends Error {
  public readonly violations: import("./types").Violation[];

  constructor(violations: import("./types").Violation[]) {
    super(formatDiagnostic(violations[0]));
    this.name = "PolicyViolationError";
    this.violations = violations;
    Object.setPrototypeOf(this, PolicyViolationError.prototype);
  }
}

/** Build a stack-trace-friendly diagnostic line from a violation's code and coordinates. */
function formatDiagnostic(violation: import("./types").Violation | undefined): string {
  if (!violation) return "Policy violation";
  const location = "group" in violation ? ` at group ${violation.group} rule ${violation.rule}` : "";
  return `Policy violation: ${violation.code}${location}`;
}

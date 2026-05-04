/** Machine-readable error code for structural decoding and validation failures. */
export type CallciumErrorCode =
  | "UNSUPPORTED_VERSION"
  | "MALFORMED_HEADER"
  | "UNEXPECTED_END"
  | "NODE_OVERFLOW"
  | "UNKNOWN_TYPE_CODE"
  | "INVALID_OPERATOR"
  | "INVALID_ARRAY_LENGTH"
  | "INVALID_TUPLE_FIELD_COUNT"
  | "PARAM_COUNT_MISMATCH"
  | "EMPTY_POLICY"
  | "EMPTY_GROUP"
  | "EMPTY_PATH"
  | "INVALID_CONTEXT_PATH"
  | "INVALID_CONTEXT_PROPERTY"
  | "INVALID_QUANTIFIER"
  | "INVALID_SCOPE"
  | "RULE_SIZE_MISMATCH"
  | "GROUP_SIZE_MISMATCH"
  | "GROUP_OVERFLOW"
  | "RULE_OVERFLOW"
  | "TRAILING_BYTES"
  | "INTERNAL_ERROR"
  | "INVALID_SIGNATURE"
  | "INVALID_TYPE_STRING"
  | "UNKNOWN_TYPE"
  | "DESCRIPTOR_TOO_LARGE"
  | "INVALID_PATH"
  | "DUPLICATE_PATH"
  | "INVALID_CONSTRAINT"
  | "INVALID_OPERATOR_DATA"
  | "EMPTY_SET"
  | "SET_TOO_LARGE"
  | "INVALID_RANGE"
  | "GROUP_COUNT_OVERFLOW"
  | "RULE_COUNT_OVERFLOW"
  | "RULE_SIZE_OVERFLOW"
  | "DESC_LENGTH_OVERFLOW"
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
 * Thrown by `PolicyEnforcer.enforce` when calldata fails policy enforcement.
 * Distinct from `CallciumError("VALIDATION_ERROR")`, which signals static
 * issues in the policy itself.
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

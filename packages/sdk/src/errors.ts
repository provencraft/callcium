import type { Issue, Violation } from "./types";

/**
 * Machine-readable error code for structural decoding and validation failures.
 *
 * Each code names one invariant. Where Solidity detects the same invariant, the code is its error name transliterated
 * from `PascalCase` to `SCREAMING_SNAKE_CASE`. The codes under "Inputs and validation" have no counterpart: they name
 * input a Solidity signature cannot express.
 */
export type CallciumErrorCode =
  // Policy and descriptor framing.
  | "UNSUPPORTED_VERSION"
  | "UNSUPPORTED_MINOR"
  | "MINOR_MISMATCH"
  | "MALFORMED_HEADER"
  | "UNEXPECTED_END"
  | "TRAILING_BYTES"
  // Groups and rules.
  | "EMPTY_POLICY"
  | "EMPTY_GROUP"
  | "GROUP_SIZE_MISMATCH"
  | "GROUP_OVERFLOW"
  | "RULE_TOO_SMALL"
  | "RULE_SIZE_MISMATCH"
  | "RULE_OVERFLOW"
  // Paths.
  | "EMPTY_PATH"
  | "MALFORMED_PATH"
  | "PATH_TOO_DEEP"
  | "PARAM_INDEX_OUT_OF_BOUNDS"
  | "TUPLE_FIELD_OUT_OF_BOUNDS"
  | "STATIC_ARRAY_INDEX_OUT_OF_BOUNDS"
  | "NOT_COMPOSITE"
  | "QUANTIFIER_ON_NON_ARRAY"
  | "UNKNOWN_PATH_STEP"
  // Loops.
  | "UNKNOWN_QUANTIFIER"
  | "INVALID_NESTED_LOOP"
  // Scope and context.
  | "UNKNOWN_SCOPE"
  | "INVALID_CONTEXT_PATH"
  | "UNKNOWN_CONTEXT_PROPERTY"
  // Operators and hints.
  | "UNKNOWN_OPERATOR"
  | "INVALID_OPERATOR_BYTES"
  | "OPERATOR_TARGET_MISMATCH"
  | "INVALID_CONTEXT_OPERAND"
  | "DATA_LENGTH_MISMATCH"
  | "UNSORTED_IN_SET"
  | "MALFORMED_HINT"
  // Constraint building.
  | "NO_CONSTRAINT_OPERATORS"
  | "EMPTY_SET"
  | "SET_TOO_LARGE"
  | "INVALID_RANGE"
  | "OUT_OF_PHYSICAL_BOUNDS"
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
  | "NODE_LENGTH_MISMATCH"
  | "STATIC_WORDS_MISMATCH"
  // Type codes.
  | "INVALID_UINT_BITS"
  | "INVALID_INT_BITS"
  | "INVALID_BYTES_LENGTH"
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
  // Strict build.
  | "VALIDATION_ERROR"
  // Inputs and validation.
  | "INVALID_HEX"
  | "MALFORMED_SELECTOR"
  | "PATH_STEP_OVERFLOW"
  | "OPERAND_OVERFLOW"
  | "CONTEXT_VALUE_OVERFLOW"
  | "MALFORMED_CONTEXT_VALUE"
  | "MALFORMED_OPERAND";

/**
 * Thrown on malformed or inadmissible SDK input. `offset`, when set, is the error's byte position in the source blob.
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
    // `exactOptionalPropertyTypes` admits no `undefined` in the optional property.
    if (offset !== undefined) this.offset = offset;
  }
}

/**
 * Thrown by `PolicyBuilder.build` when validation reports any issue.
 *
 * Carries every issue the validator found. The `Error.message` is the first issue's message — a diagnostic summary, not
 * a presentation contract. To render issues to users, iterate `issues` directly.
 */
export class ValidationError extends CallciumError {
  public readonly issues: Issue[];

  constructor(issues: Issue[]) {
    super("VALIDATION_ERROR", issues[0]?.message ?? "Policy validation failed");
    this.name = "ValidationError";
    this.issues = issues;
  }
}

/**
 * Thrown by `PolicyEnforcer.enforce` when calldata fails policy enforcement. Distinct from `ValidationError`, which
 * signals static issues in the policy itself.
 *
 * Carries the full list of structured violations (one per failed group). The `Error.message` is a minimal non-lossy
 * diagnostic summary built from the first violation's structured fields — not a presentation contract. To render
 * violations to users, iterate `violations` directly.
 */
export class PolicyViolationError extends Error {
  public readonly violations: Violation[];

  constructor(violations: Violation[]) {
    super(formatDiagnostic(violations[0]));
    this.name = "PolicyViolationError";
    this.violations = violations;
  }
}

/** Build a stack-trace-friendly diagnostic line from a violation's code and coordinates. */
function formatDiagnostic(violation: Violation | undefined): string {
  if (!violation) return "Policy violation";
  const location = "group" in violation ? ` at group ${violation.group} rule ${violation.rule}` : "";
  return `Policy violation: ${violation.code}${location}`;
}

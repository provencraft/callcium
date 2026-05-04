import { expect } from "vitest";

import { CallciumError } from "../src";

import type { EnforceResult, Violation, ViolationCode } from "../src";

/** Assert an enforcement result is a failure and narrow its type. */
export function assertFailed(result: EnforceResult): asserts result is Extract<EnforceResult, { ok: false }> {
  if (result.ok) {
    throw new Error(`Expected enforcement failure, got pass with matched group ${result.matchedGroup}`);
  }
}

/** Assert an enforcement result is a pass and narrow its type. */
export function assertPassed(result: EnforceResult): asserts result is Extract<EnforceResult, { ok: true }> {
  if (!result.ok) {
    const codes = result.violations.map((violation) => violation.code).join(", ") || "no violations";
    throw new Error(`Expected enforcement pass, got failure with ${result.violations.length} violation(s): ${codes}`);
  }
}

/** Assert a violation has the given code and narrow it to the matching variant. */
export function assertViolationCode<C extends ViolationCode>(
  violation: Violation,
  code: C,
): asserts violation is Extract<Violation, { code: C }> {
  if (violation.code !== code) {
    throw new Error(`Expected violation code ${code}, got ${violation.code}`);
  }
}

/**
 * Assert a result failed, has at least one violation, and its first violation matches `code`.
 * Returns the narrowed violation. Combines `assertFailed` + first-violation extraction + code check
 * for the common single-violation test pattern.
 */
export function firstViolation<C extends ViolationCode>(
  result: EnforceResult,
  code: C,
): Extract<Violation, { code: C }> {
  assertFailed(result);
  const violation = result.violations[0];
  if (violation === undefined) {
    throw new Error("Expected at least one violation, got none");
  }
  assertViolationCode(violation, code);
  return violation;
}

/** Assert that calling fn() throws a CallciumError with the given code. */
export function expectErrorCode(fn: () => void, code: string): void {
  try {
    fn();
    expect.unreachable("Expected CallciumError");
  } catch (error) {
    expect(error).toBeInstanceOf(CallciumError);
    if (error instanceof CallciumError) {
      expect(error.code).toBe(code);
    }
  }
}

/** Coerce a plain string to a 0x-prefixed hex value. */
export function hex(s: string) {
  const body = s.startsWith("0x") ? s.slice(2) : s;
  return `0x${body}` as const;
}

///////////////////////////////////////////////////////////////////////////
// Operator hex builders
///////////////////////////////////////////////////////////////////////////

/** Build a single-operand operator hex (opcode + 32-byte value). */
export function op(code: number, value: bigint): `0x${string}` {
  return `0x${code.toString(16).padStart(2, "0")}${value.toString(16).padStart(64, "0")}`;
}

/** Build a BETWEEN/range operator hex (opcode + 64-byte pair). */
export function rangeOp(code: number, low: bigint, high: bigint): `0x${string}` {
  return `0x${code.toString(16).padStart(2, "0")}${low.toString(16).padStart(64, "0")}${high.toString(16).padStart(64, "0")}`;
}

/** Build an IN operator hex (opcode + N * 32-byte values). */
export function inOp(code: number, values: bigint[]): `0x${string}` {
  const body = values.map((v) => v.toString(16).padStart(64, "0")).join("");
  return `0x${code.toString(16).padStart(2, "0")}${body}`;
}

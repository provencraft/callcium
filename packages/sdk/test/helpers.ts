import { expect } from "vitest";

import { bigintToHex } from "../src/bytes";
import { CallciumError } from "../src/errors";
import { PolicyCoder } from "../src/policy-coder";

import type { CallciumErrorCode } from "../src/errors";
import type { EnforceResult, Violation } from "../src/types";

///////////////////////////////////////////////////////////////////////////
// Assertions
///////////////////////////////////////////////////////////////////////////

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
function assertViolationCode<C extends Violation["code"]>(
  violation: Violation,
  code: C,
): asserts violation is Extract<Violation, { code: C }> {
  if (violation.code !== code) {
    throw new Error(`Expected violation code ${code}, got ${violation.code}`);
  }
}

/** Assert a result failed and its first violation carries `code`, and return that violation. */
export function expectFirstViolation<C extends Violation["code"]>(
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

/** Assert that calling call() throws a CallciumError with the given code, or one of the given codes, and return it. */
export function expectErrorCode(
  call: () => unknown,
  code: CallciumErrorCode | readonly CallciumErrorCode[],
): CallciumError {
  try {
    call();
  } catch (error) {
    if (!(error instanceof CallciumError)) {
      throw error;
    }
    if (typeof code === "string") expect(error.code).toBe(code);
    else expect(code).toContain(error.code);
    return error;
  }
  expect.unreachable(`Expected CallciumError ${[code].flat().join(" or ")}`);
}

///////////////////////////////////////////////////////////////////////////
// Vectors
///////////////////////////////////////////////////////////////////////////

/** Coerce a plain string to a 0x-prefixed hex value. */
export function hex(value: string) {
  const body = value.startsWith("0x") ? value.slice(2) : value;
  return `0x${body}` as const;
}

/** The vector `id` of `vectors`. */
export function vectorById<V extends { id: string }>(vectors: readonly V[], id: string): V {
  const found = vectors.find((vector) => vector.id === id);
  if (found === undefined) throw new Error(`No vector ${id}`);
  return found;
}

/**
 * The codes re-encoding refuses a policy with: a descriptor whose composite node disagrees with its children, a path
 * that does not compile, or a comparison or a constant its target's type cannot hold.
 */
const encoderRefusals: ReadonlySet<CallciumErrorCode> = new Set<CallciumErrorCode>([
  "NODE_LENGTH_MISMATCH",
  "STATIC_WORDS_MISMATCH",
  "PARAM_INDEX_OUT_OF_BOUNDS",
  "TUPLE_FIELD_OUT_OF_BOUNDS",
  "STATIC_ARRAY_INDEX_OUT_OF_BOUNDS",
  "NOT_COMPOSITE",
  "QUANTIFIER_ON_NON_ARRAY",
  "OPERATOR_TARGET_MISMATCH",
  "OUT_OF_PHYSICAL_BOUNDS",
]);

/** Encode the policy `blob` states through the encoder; `0x` where re-encoding refuses the policy. */
export function reencode(blob: `0x${string}`): `0x${string}` {
  try {
    return PolicyCoder.encode(PolicyCoder.decode(blob));
  } catch (error) {
    if (error instanceof CallciumError && encoderRefusals.has(error.code)) return "0x";
    throw error;
  }
}

///////////////////////////////////////////////////////////////////////////
// Word encoding
///////////////////////////////////////////////////////////////////////////

/** Pack a value into a 32-byte big-endian word, two's complement for a negative. */
export function word(value: bigint): Uint8Array {
  const buf = new Uint8Array(32);
  let remaining = BigInt.asUintN(256, value);
  for (let i = 31; i >= 0; i--) {
    buf[i] = Number(remaining & 0xffn);
    remaining >>= 8n;
  }
  return buf;
}

/** A non-negative value as a 64-hex-character word with no prefix, for calldata concatenation. */
export function wordHex(value: bigint): string {
  return bigintToHex(value).slice(2);
}

/** Pack values into consecutive 32-byte words. */
export function words(...values: bigint[]): Uint8Array {
  const buf = new Uint8Array(values.length * 32);
  for (let i = 0; i < values.length; i++) {
    buf.set(word(values[i]), i * 32);
  }
  return buf;
}

///////////////////////////////////////////////////////////////////////////
// Operator hex builders
///////////////////////////////////////////////////////////////////////////

/** Build a single-operand operator hex (opcode + 32-byte value). */
export function op(code: number, value: bigint): `0x${string}` {
  return `0x${code.toString(16).padStart(2, "0")}${value.toString(16).padStart(64, "0")}`;
}

/** Build an IN operator hex (opcode + N * 32-byte values). */
export function inOp(code: number, values: bigint[]): `0x${string}` {
  const body = values.map((value) => value.toString(16).padStart(64, "0")).join("");
  return `0x${code.toString(16).padStart(2, "0")}${body}`;
}

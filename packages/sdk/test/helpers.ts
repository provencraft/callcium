import { expect } from "vitest";

import { CallciumError } from "../src";

/** Assert that calling fn() throws a CallciumError with the given code. */
export function expectErrorCode(fn: () => void, code: string): void {
  try {
    fn();
    expect.unreachable("Expected CallciumError");
  } catch (e) {
    expect(e).toBeInstanceOf(CallciumError);
    if (e instanceof CallciumError) {
      expect(e.code).toBe(code);
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

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

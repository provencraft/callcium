import { describe, expect, test } from "vitest";

import { CallciumError, PolicyCoder } from "../src";

///////////////////////////////////////////////////////////////////////////
// Offset
///////////////////////////////////////////////////////////////////////////

describe("CallciumError - offset", () => {
  test("carries the offset it prefixes the message with", () => {
    const error = new CallciumError("MALFORMED_HEADER", "Policy blob is too short", 11);
    expect(error.offset).toBe(11);
    expect(error.message).toBe("[offset 11] Policy blob is too short");
  });

  test("carries a zero offset rather than dropping it", () => {
    const error = new CallciumError("MALFORMED_HEADER", "Policy blob is too short", 0);
    expect(error.offset).toBe(0);
    expect(error.message).toBe("[offset 0] Policy blob is too short");
  });

  test("leaves the offset unset when none is given", () => {
    const error = new CallciumError("MALFORMED_HEADER", "Policy blob is too short");
    expect(error.offset).toBeUndefined();
    expect(error.message).toBe("Policy blob is too short");
  });

  test("reports the byte a decoder rejected", () => {
    // A group declaring no rules, reported at the group header.
    const blob = "0x022fbebd380003020120010000000000090031010100000000000000000020010020";
    expect(() => PolicyCoder.decode(`${blob}${"00".repeat(32)}`)).toThrowError(expect.objectContaining({ offset: 11 }));
  });
});

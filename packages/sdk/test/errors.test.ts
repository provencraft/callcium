import { describe, expect, test } from "vitest";

import { CallciumError, PolicyViolationError } from "../src/errors";

describe("CallciumError", () => {
  test("carries a zero offset rather than dropping it", () => {
    const error = new CallciumError("MALFORMED_HEADER", "Policy blob is too short", 0);
    expect(error.offset).toBe(0);
    expect(error.message).toBe("[offset 0] Policy blob is too short");
  });
});

describe("PolicyViolationError", () => {
  test("an empty violation list reads as a policy violation", () => {
    expect(new PolicyViolationError([]).message).toBe("Policy violation");
  });
});

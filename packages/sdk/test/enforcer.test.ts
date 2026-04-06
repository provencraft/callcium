import { describe, expect, test } from "vitest";

import { check, enforce, CallciumError, PolicyViolationError } from "../src";

import type { Context, Hex } from "../src";

///////////////////////////////////////////////////////////////////////////
//              Test policy blobs from test/vectors/policies.json
///////////////////////////////////////////////////////////////////////////

// EQ rule: arg(0) == 42, selector 0x2fbebd38, descriptor uint256.
const POLICY_EQ_UINT256 =
  "0x012fbebd38000301011f01000100000029002901010000010020000000000000000000000000000000000000000000000000000000000000002a";

// Selectorless: EQ rule arg(0) == 42.
const POLICY_SELECTORLESS =
  "0x1100000000000301011f01000100000029002901010000010020000000000000000000000000000000000000000000000000000000000000002a";

// Two groups (OR): EQ(arg0,2) | EQ(arg0,1).
const POLICY_MULTI_GROUP =
  "0x012fbebd38000301011f0200010000002900290101000001002000000000000000000000000000000000000000000000000000000000000000020001000000290029010100000100200000000000000000000000000000000000000000000000000000000000000001";

// Two calldata rules in one group: GT(0) AND LTE(100).
const POLICY_TWO_CONSTRAINTS =
  "0x012fbebd38000301011f0100020000005200290101000002002000000000000000000000000000000000000000000000000000000000000000000029010100000500200000000000000000000000000000000000000000000000000000000000000064";

// Mixed scope: context msg.sender=addr(1) AND calldata arg(0)=uint256(42).
const POLICY_MIXED_SCOPE =
  "0x012fbebd38000301011f010002000000520029000100000100200000000000000000000000000000000000000000000000000000000000000001002901010000010020000000000000000000000000000000000000000000000000000000000000002a";

///////////////////////////////////////////////////////////////////////////
//                               Helpers
///////////////////////////////////////////////////////////////////////////

const SELECTOR = "0x2fbebd38";

/** Encode a single uint256 arg with selector prefix. */
function encodeUint256(selector: Hex, value: bigint): Hex {
  return `${selector}${value.toString(16).padStart(64, "0")}`;
}

/** Encode a raw uint256 without selector. */
function encodeRawUint256(value: bigint): Hex {
  return `0x${value.toString(16).padStart(64, "0")}`;
}

///////////////////////////////////////////////////////////////////////////
//                                Tests
///////////////////////////////////////////////////////////////////////////

describe("enforce", () => {
  describe("basic EQ uint256", () => {
    test("passes when callData matches", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const result = check(POLICY_EQ_UINT256, callData);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.matchedGroup).toBe(0);
    });

    test("fails when callData does not match", () => {
      const callData = encodeUint256(SELECTOR, 99n);
      const result = check(POLICY_EQ_UINT256, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });

    test("fails on selector mismatch", () => {
      const callData = "0xdeadbeef000000000000000000000000000000000000000000000000000000000000002a";
      const result = check(POLICY_EQ_UINT256, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("SELECTOR_MISMATCH");
        expect(result.violations[0].group).toBeUndefined();
        expect(result.violations[0].rule).toBeUndefined();
        expect(result.violations[0].resolvedValue).toBe("0xdeadbeef");
      }
    });
  });

  describe("selectorless policy", () => {
    test("passes with matching raw callData", () => {
      const callData = encodeRawUint256(42n);
      const result = check(POLICY_SELECTORLESS, callData);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.matchedGroup).toBe(0);
    });

    test("fails with non-matching raw callData", () => {
      const callData = encodeRawUint256(99n);
      const result = check(POLICY_SELECTORLESS, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });

    test("does not require selector in callData", () => {
      // A selectorless policy reads arg(0) at offset 0, not 4.
      // Passing exactly 32 bytes should work.
      const callData = encodeRawUint256(42n);
      const result = check(POLICY_SELECTORLESS, callData);
      expect(result.ok).toBe(true);
    });
  });

  describe("multi-group (OR semantics)", () => {
    test("passes when first group matches", () => {
      const callData = encodeUint256(SELECTOR, 2n);
      const result = check(POLICY_MULTI_GROUP, callData);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.matchedGroup).toBe(0);
    });

    test("passes when second group matches", () => {
      const callData = encodeUint256(SELECTOR, 1n);
      const result = check(POLICY_MULTI_GROUP, callData);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.matchedGroup).toBe(1);
    });

    test("fails when no group matches", () => {
      const callData = encodeUint256(SELECTOR, 99n);
      const result = check(POLICY_MULTI_GROUP, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        // Should have one violation per group.
        expect(result.violations.length).toBe(2);
        expect(result.violations[0].group).toBe(0);
        expect(result.violations[1].group).toBe(1);
      }
    });
  });

  describe("two constraints in one group (AND semantics)", () => {
    test("passes when both constraints are satisfied", () => {
      // GT(0) AND LTE(100): value must be in (0, 100].
      const callData = encodeUint256(SELECTOR, 50n);
      const result = check(POLICY_TWO_CONSTRAINTS, callData);
      expect(result.ok).toBe(true);
    });

    test("fails when first constraint fails (value == 0)", () => {
      const callData = encodeUint256(SELECTOR, 0n);
      const result = check(POLICY_TWO_CONSTRAINTS, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });

    test("fails when second constraint fails (value > 100)", () => {
      const callData = encodeUint256(SELECTOR, 101n);
      const result = check(POLICY_TWO_CONSTRAINTS, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });

    test("passes at boundary (value == 100)", () => {
      const callData = encodeUint256(SELECTOR, 100n);
      const result = check(POLICY_TWO_CONSTRAINTS, callData);
      expect(result.ok).toBe(true);
    });

    test("passes at boundary (value == 1)", () => {
      const callData = encodeUint256(SELECTOR, 1n);
      const result = check(POLICY_TWO_CONSTRAINTS, callData);
      expect(result.ok).toBe(true);
    });
  });

  describe("mixed scope (context + calldata)", () => {
    test("passes when both context and calldata match", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const ctx: Context = {
        msgSender: "0x0000000000000000000000000000000000000001",
      };
      const result = check(POLICY_MIXED_SCOPE, callData, ctx);
      expect(result.ok).toBe(true);
    });

    test("fails when context is missing", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const result = check(POLICY_MIXED_SCOPE, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("MISSING_CONTEXT");
      }
    });

    test("fails when context does not match", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const ctx: Context = {
        msgSender: "0x0000000000000000000000000000000000000002",
      };
      const result = check(POLICY_MIXED_SCOPE, callData, ctx);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });

    test("fails when calldata does not match", () => {
      const callData = encodeUint256(SELECTOR, 99n);
      const ctx: Context = {
        msgSender: "0x0000000000000000000000000000000000000001",
      };
      const result = check(POLICY_MIXED_SCOPE, callData, ctx);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });
  });

  describe("callData too short", () => {
    test("fails when callData is shorter than required", () => {
      // CallData with selector but no argument data.
      const callData = "0x2fbebd38";
      const result = check(POLICY_EQ_UINT256, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("CALLDATA_TOO_SHORT");
      }
    });

    test("fails when selectorless callData is empty", () => {
      const callData = "0x";
      const result = check(POLICY_SELECTORLESS, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("CALLDATA_TOO_SHORT");
      }
    });

    test("fails when callData too short for selector check", () => {
      const callData = "0x2fbe";
      const result = check(POLICY_EQ_UINT256, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("CALLDATA_TOO_SHORT");
      }
    });
  });
});

///////////////////////////////////////////////////////////////////////////
//                         enforce() (throwing)
///////////////////////////////////////////////////////////////////////////

describe("enforce (throwing)", () => {
  test("does not throw when policy passes", () => {
    const callData = encodeUint256(SELECTOR, 42n);
    expect(() => enforce(POLICY_EQ_UINT256, callData)).not.toThrow();
  });

  test("throws PolicyViolationError when policy fails", () => {
    const callData = encodeUint256(SELECTOR, 99n);
    expect(() => enforce(POLICY_EQ_UINT256, callData)).toThrow(PolicyViolationError);
  });

  test("thrown error carries violations", () => {
    const callData = encodeUint256(SELECTOR, 99n);
    try {
      enforce(POLICY_EQ_UINT256, callData);
      expect.unreachable("should have thrown");
    } catch (e) {
      expect(e).toBeInstanceOf(PolicyViolationError);
      if (e instanceof PolicyViolationError) {
        expect(e.violations).toHaveLength(1);
        expect(e.violations[0].code).toBe("VALUE_MISMATCH");
      }
    }
  });

  test("throws CallciumError for malformed policy", () => {
    expect(() => enforce("0x01", "0x")).toThrow(CallciumError);
  });
});

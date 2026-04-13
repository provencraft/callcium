import { describe, expect, test } from "vitest";

import {
  PolicyEnforcer,
  CallciumError,
  PolicyViolationError,
  PolicyBuilder,
  PolicyCoder,
  Quantifier,
  Scope,
  Op,
  TypeCode,
  arg,
  msgSender,
  msgValue,
  blockTimestamp,
  blockNumber,
  chainId,
  txOrigin,
  bytesToHex,
} from "../src";
import { bigintToHex } from "../src/bytes";
import { DescriptorCoder } from "../src/descriptor-coder";
import { applyOperator } from "../src/operators";
import { op } from "./helpers";

import type { Context, Hex, PolicyData } from "../src";

///////////////////////////////////////////////////////////////////////////
// Test policy blobs from test/vectors/policies.json
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
// Helpers
///////////////////////////////////////////////////////////////////////////

const SELECTOR = "0x2fbebd38";

/** Pad a bigint into a 64-char hex word (no 0x prefix), for calldata concatenation. */
function word(v: bigint): string {
  return bigintToHex(v).slice(2);
}

/** Encode a single uint256 arg with selector prefix. */
function encodeUint256(selector: Hex, value: bigint): Hex {
  return `${selector}${word(value)}`;
}

/** Encode a raw uint256 without selector. */
function encodeRawUint256(value: bigint): Hex {
  return bigintToHex(value);
}

/** Encode a selectorless calldata blob containing a single dynamic uint256 array. */
function encodeDynamicUint256Array(elements: bigint[]): Hex {
  let body = word(32n) + word(BigInt(elements.length));
  for (const elem of elements) body += word(elem);
  return `0x${body}`;
}

/** Encode a selectorless calldata blob containing a static uint256[3] array. */
function encodeStaticUint256Array3(a: bigint, b: bigint, c: bigint): Hex {
  return `0x${word(a)}${word(b)}${word(c)}`;
}

/** Encode selectorless calldata for (uint256,address)[] with given tuples. */
function encodeTupleArray(tuples: Array<{ amount: bigint; addr: bigint }>): Hex {
  let body = word(32n) + word(BigInt(tuples.length));
  for (const t of tuples) body += word(t.amount) + word(t.addr);
  return `0x${body}`;
}

/**
 * Build a selectorless policy blob from scratch, bypassing PolicyCoder.encode validation.
 * Used only for the path-depth test where the structural change (33 path steps)
 * cascades into rule and group size fields that can't be patched post-hoc.
 */
function craftPolicy(opts: {
  descriptor: string;
  scope: number;
  pathHex: string;
  opCode: number;
  dataHex: string;
}): Hex {
  const desc = opts.descriptor;
  const descLen = desc.length / 2;
  const pathBytes = opts.pathHex;
  const depth = pathBytes.length / 4;
  const dataBytes = opts.dataHex;
  const dataLen = dataBytes.length / 2;
  const ruleSize = 7 + depth * 2 + dataLen;

  const rule =
    ruleSize.toString(16).padStart(4, "0") +
    opts.scope.toString(16).padStart(2, "0") +
    depth.toString(16).padStart(2, "0") +
    pathBytes +
    opts.opCode.toString(16).padStart(2, "0") +
    dataLen.toString(16).padStart(4, "0") +
    dataBytes;

  const group = "0001" + (rule.length / 2).toString(16).padStart(8, "0") + rule;
  const header = "11" + "00000000" + descLen.toString(16).padStart(4, "0") + desc + "01" + group;
  return `0x${header}`;
}

/** Overwrite bytes in a hex blob at a given byte offset. */
function tamper(blob: Hex, byteOffset: number, replacement: string): Hex {
  const hexOffset = 2 + byteOffset * 2;
  return `0x${blob.slice(2, hexOffset)}${replacement}${blob.slice(hexOffset + replacement.length)}` as Hex;
}

///////////////////////////////////////////////////////////////////////////
// Conformance vectors
///////////////////////////////////////////////////////////////////////////

describe("enforce", () => {
  describe("basic EQ uint256", () => {
    test("passes when callData matches", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const result = PolicyEnforcer.check(POLICY_EQ_UINT256, callData);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.matchedGroup).toBe(0);
    });

    test("fails when callData does not match", () => {
      const callData = encodeUint256(SELECTOR, 99n);
      const result = PolicyEnforcer.check(POLICY_EQ_UINT256, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });

    test("fails on selector mismatch", () => {
      const callData = "0xdeadbeef000000000000000000000000000000000000000000000000000000000000002a";
      const result = PolicyEnforcer.check(POLICY_EQ_UINT256, callData);
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
      const result = PolicyEnforcer.check(POLICY_SELECTORLESS, callData);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.matchedGroup).toBe(0);
    });

    test("fails with non-matching raw callData", () => {
      const callData = encodeRawUint256(99n);
      const result = PolicyEnforcer.check(POLICY_SELECTORLESS, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });

    test("does not require selector in callData", () => {
      const callData = encodeRawUint256(42n);
      const result = PolicyEnforcer.check(POLICY_SELECTORLESS, callData);
      expect(result.ok).toBe(true);
    });
  });

  describe("multi-group (OR semantics)", () => {
    test("passes when first group matches", () => {
      const callData = encodeUint256(SELECTOR, 2n);
      const result = PolicyEnforcer.check(POLICY_MULTI_GROUP, callData);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.matchedGroup).toBe(0);
    });

    test("passes when second group matches", () => {
      const callData = encodeUint256(SELECTOR, 1n);
      const result = PolicyEnforcer.check(POLICY_MULTI_GROUP, callData);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.matchedGroup).toBe(1);
    });

    test("fails when no group matches", () => {
      const callData = encodeUint256(SELECTOR, 99n);
      const result = PolicyEnforcer.check(POLICY_MULTI_GROUP, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations.length).toBe(2);
        expect(result.violations[0].group).toBe(0);
        expect(result.violations[1].group).toBe(1);
      }
    });
  });

  describe("two constraints in one group (AND semantics)", () => {
    test("passes when both constraints are satisfied", () => {
      const callData = encodeUint256(SELECTOR, 50n);
      const result = PolicyEnforcer.check(POLICY_TWO_CONSTRAINTS, callData);
      expect(result.ok).toBe(true);
    });

    test("fails when first constraint fails (value == 0)", () => {
      const callData = encodeUint256(SELECTOR, 0n);
      const result = PolicyEnforcer.check(POLICY_TWO_CONSTRAINTS, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });

    test("fails when second constraint fails (value > 100)", () => {
      const callData = encodeUint256(SELECTOR, 101n);
      const result = PolicyEnforcer.check(POLICY_TWO_CONSTRAINTS, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });

    test("passes at boundary (value == 100)", () => {
      const callData = encodeUint256(SELECTOR, 100n);
      const result = PolicyEnforcer.check(POLICY_TWO_CONSTRAINTS, callData);
      expect(result.ok).toBe(true);
    });

    test("passes at boundary (value == 1)", () => {
      const callData = encodeUint256(SELECTOR, 1n);
      const result = PolicyEnforcer.check(POLICY_TWO_CONSTRAINTS, callData);
      expect(result.ok).toBe(true);
    });
  });

  describe("mixed scope (context + calldata)", () => {
    test("passes when both context and calldata match", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const ctx: Context = { msgSender: "0x0000000000000000000000000000000000000001" };
      const result = PolicyEnforcer.check(POLICY_MIXED_SCOPE, callData, ctx);
      expect(result.ok).toBe(true);
    });

    test("fails when context is missing", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const result = PolicyEnforcer.check(POLICY_MIXED_SCOPE, callData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("MISSING_CONTEXT");
      }
    });

    test("fails when context does not match", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const ctx: Context = { msgSender: "0x0000000000000000000000000000000000000002" };
      const result = PolicyEnforcer.check(POLICY_MIXED_SCOPE, callData, ctx);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });

    test("fails when calldata does not match", () => {
      const callData = encodeUint256(SELECTOR, 99n);
      const ctx: Context = { msgSender: "0x0000000000000000000000000000000000000001" };
      const result = PolicyEnforcer.check(POLICY_MIXED_SCOPE, callData, ctx);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      }
    });
  });

  describe("callData too short", () => {
    test("fails when callData is shorter than required", () => {
      const result = PolicyEnforcer.check(POLICY_EQ_UINT256, "0x2fbebd38");
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("CALLDATA_TOO_SHORT");
      }
    });

    test("fails when selectorless callData is empty", () => {
      const result = PolicyEnforcer.check(POLICY_SELECTORLESS, "0x");
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("CALLDATA_TOO_SHORT");
      }
    });

    test("fails when callData too short for selector check", () => {
      const result = PolicyEnforcer.check(POLICY_EQ_UINT256, "0x2fbe");
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.violations[0].code).toBe("CALLDATA_TOO_SHORT");
      }
    });
  });
});

///////////////////////////////////////////////////////////////////////////
// PolicyEnforcer.enforce() (throwing)
///////////////////////////////////////////////////////////////////////////

describe("enforce (throwing)", () => {
  test("does not throw when policy passes", () => {
    const callData = encodeUint256(SELECTOR, 42n);
    expect(() => PolicyEnforcer.enforce(POLICY_EQ_UINT256, callData)).not.toThrow();
  });

  test("throws PolicyViolationError when policy fails", () => {
    const callData = encodeUint256(SELECTOR, 99n);
    expect(() => PolicyEnforcer.enforce(POLICY_EQ_UINT256, callData)).toThrow(PolicyViolationError);
  });

  test("thrown error carries violations", () => {
    const callData = encodeUint256(SELECTOR, 99n);
    try {
      PolicyEnforcer.enforce(POLICY_EQ_UINT256, callData);
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
    expect(() => PolicyEnforcer.enforce("0x01", "0x")).toThrow(CallciumError);
  });
});

///////////////////////////////////////////////////////////////////////////
// Unknown Operator
///////////////////////////////////////////////////////////////////////////

describe("applyOperator - unknown opcode", () => {
  test("throws CallciumError for unrecognized base opcode", () => {
    const operand = new Uint8Array(32);
    expect(() => applyOperator(0x30, 42n, 32, operand, TypeCode.UINT_MAX)).toThrow(CallciumError);
  });
});

///////////////////////////////////////////////////////////////////////////
// LENGTH_* On Static Type
///////////////////////////////////////////////////////////////////////////

describe("enforce - LENGTH_* on static type", () => {
  // PolicyBuilder rejects LENGTH_EQ on static types as an authoring mistake (LENGTH_ON_STATIC).
  // The enforcer still handles it correctly by using staticSize — these tests verify that
  // defence-in-depth path by encoding directly via PolicyCoder.
  test("LENGTH_EQ(32) on uint256 passes using static byte width", () => {
    const data: PolicyData = {
      isSelectorless: true,
      selector: "0x00000000",
      descriptor: bytesToHex(DescriptorCoder.fromTypes("uint256")),
      groups: [[{ scope: Scope.CALLDATA, path: "0x0000", operators: [op(Op.LENGTH_EQ, 32n)] }]],
    };
    const policyHex = PolicyCoder.encode(data);
    const result = PolicyEnforcer.check(policyHex, encodeRawUint256(42n));
    expect(result.ok).toBe(true);
  });

  test("LENGTH_EQ(31) on uint256 fails (static size is 32, not 31)", () => {
    const data: PolicyData = {
      isSelectorless: true,
      selector: "0x00000000",
      descriptor: bytesToHex(DescriptorCoder.fromTypes("uint256")),
      groups: [[{ scope: Scope.CALLDATA, path: "0x0000", operators: [op(Op.LENGTH_EQ, 31n)] }]],
    };
    const policyHex = PolicyCoder.encode(data);
    const result = PolicyEnforcer.check(policyHex, encodeRawUint256(42n));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
    }
  });
});

///////////////////////////////////////////////////////////////////////////
// Quantifier Edge Cases
///////////////////////////////////////////////////////////////////////////

describe("enforce - quantifier edge cases", () => {
  test("ANY on empty dynamic array fails with QUANTIFIER_EMPTY_ARRAY", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ANY).eq(1n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([]));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("QUANTIFIER_EMPTY_ARRAY");
    }
  });

  test("ALL_OR_EMPTY on empty dynamic array passes (vacuously true)", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL_OR_EMPTY).gt(0n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([]));
    expect(result.ok).toBe(true);
  });

  test("ALL on static array passes when all elements satisfy the rule", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ALL).gt(0n)).build();
    const result = PolicyEnforcer.check(policy, encodeStaticUint256Array3(10n, 20n, 30n));
    expect(result.ok).toBe(true);
  });

  test("ALL on static array fails when one element does not satisfy the rule", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ALL).gt(0n)).build();
    const result = PolicyEnforcer.check(policy, encodeStaticUint256Array3(10n, 20n, 0n));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
    }
  });

  test("ANY on static array passes when one element matches", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ANY).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeStaticUint256Array3(1n, 42n, 99n));
    expect(result.ok).toBe(true);
  });

  test("ANY on static array fails when no element matches", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ANY).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeStaticUint256Array3(1n, 2n, 3n));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
    }
  });

  test("ANY short-circuits on first matching element", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ANY).eq(7n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([7n, 100n, 200n]));
    expect(result.ok).toBe(true);
  });

  test("ALL on empty dynamic array fails with QUANTIFIER_EMPTY_ARRAY", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).gt(0n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([]));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("QUANTIFIER_EMPTY_ARRAY");
    }
  });

  test("ALL_OR_EMPTY on non-empty array behaves like ALL", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL_OR_EMPTY).gt(0n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([5n, 0n]));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
    }
  });

  test("ANY on dynamic array fails when no element matches", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ANY).eq(999n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([1n, 2n, 3n]));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      expect(result.violations[0].message).toContain("ANY");
    }
  });
});

///////////////////////////////////////////////////////////////////////////
// Quantifier With Suffix Path (array of tuples)
///////////////////////////////////////////////////////////////////////////

describe("enforce - quantifier with suffix path", () => {
  test("ALL with suffix path passes when all elements satisfy", () => {
    const policy = PolicyBuilder.createRaw("(uint256,address)[]")
      .add(arg(0, Quantifier.ALL, 0).gt(0n))
      .build();
    const callData = encodeTupleArray([
      { amount: 10n, addr: 1n },
      { amount: 20n, addr: 2n },
    ]);
    expect(PolicyEnforcer.check(policy, callData).ok).toBe(true);
  });

  test("ALL with suffix path fails when one element does not satisfy", () => {
    const policy = PolicyBuilder.createRaw("(uint256,address)[]")
      .add(arg(0, Quantifier.ALL, 0).gt(0n))
      .build();
    const callData = encodeTupleArray([
      { amount: 10n, addr: 1n },
      { amount: 0n, addr: 2n },
    ]);
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
    }
  });

  test("ANY with suffix path passes when one element satisfies", () => {
    const policy = PolicyBuilder.createRaw("(uint256,address)[]")
      .add(arg(0, Quantifier.ANY, 0).eq(42n))
      .build();
    const callData = encodeTupleArray([
      { amount: 1n, addr: 1n },
      { amount: 42n, addr: 2n },
    ]);
    expect(PolicyEnforcer.check(policy, callData).ok).toBe(true);
  });

  test("ANY with suffix path fails when no element satisfies", () => {
    const policy = PolicyBuilder.createRaw("(uint256,address)[]")
      .add(arg(0, Quantifier.ANY, 0).eq(42n))
      .build();
    const callData = encodeTupleArray([
      { amount: 1n, addr: 1n },
      { amount: 2n, addr: 2n },
    ]);
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
    }
  });
});

///////////////////////////////////////////////////////////////////////////
// Quantifier Limit & Truncated Calldata
///////////////////////////////////////////////////////////////////////////

describe("enforce - quantifier limit exceeded", () => {
  test("fails with QUANTIFIER_LIMIT_EXCEEDED for array > 256 elements", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).gt(0n)).build();
    const elems = Array.from({ length: 257 }, (_, i) => BigInt(i + 1));
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array(elems));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("QUANTIFIER_LIMIT_EXCEEDED");
    }
  });
});

///////////////////////////////////////////////////////////////////////////
// Navigation Failure IN Leaf Evaluation
///////////////////////////////////////////////////////////////////////////

describe("enforce - navigation failure", () => {
  test("LENGTH_EQ on dynamic bytes with truncated calldata reports error", () => {
    const policy = PolicyBuilder.createRaw("bytes").add(arg(0).lengthEq(10n)).build();
    // Offset pointing beyond calldata.
    const callData: Hex = `0x${word(999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
// Quantifier Error Paths (element resolution, suffix descent, leaf error)
///////////////////////////////////////////////////////////////////////////

describe("enforce - quantifier element resolution failures", () => {
  test("ALL fails when arrayElementAt returns error (static array, truncated calldata)", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ALL).gt(0n)).build();
    // Only 64 bytes — static array expects 96 bytes (3 * 32). Element 2 will fail.
    const callData: Hex = `0x${word(1n)}${word(2n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("CALLDATA_TOO_SHORT");
      expect(result.violations[0].message).toContain("Quantifier element");
    }
  });

  test("ANY skips elements where arrayElementAt fails and reports failure", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ANY).eq(999n)).build();
    // Only 64 bytes for 3-element static array.
    const callData: Hex = `0x${word(1n)}${word(2n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
    }
  });

  test("ALL with suffix: descendPath failure on element causes violation", () => {
    // (uint256[],uint256)[] — suffix navigates through a dynamic field whose pointer is bogus.
    const policy = PolicyBuilder.createRaw("(uint256[],uint256)[]")
      .add(arg(0, Quantifier.ALL, 0, 0).eq(42n))
      .build();
    // Dynamic array with 1 element: element tuple has field0=uint256[] with a bogus offset pointer.
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(0n)}${word(9999n)}${word(42n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].message).toContain("navigation failed");
    }
  });

  test("ANY with suffix: descendPath failure is skipped, fails when no element passes", () => {
    const policy = PolicyBuilder.createRaw("(uint256[],uint256)[]")
      .add(arg(0, Quantifier.ANY, 0, 0).eq(42n))
      .build();
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(0n)}${word(9999n)}${word(42n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      expect(result.violations[0].message).toContain("ANY");
    }
  });
});

describe("enforce - quantifier deep error paths", () => {
  test("ALL with no suffix: leaf error on element causes failure", () => {
    const policy = PolicyBuilder.createRaw("bytes[]").add(arg(0, Quantifier.ALL).lengthEq(5n)).build();
    // bytes[] with 1 element whose internal offset is invalid.
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(9999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
  });

  test("ANY with no suffix: leaf error on element is skipped, fails if none pass", () => {
    const policy = PolicyBuilder.createRaw("bytes[]").add(arg(0, Quantifier.ANY).lengthEq(5n)).build();
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(9999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
    }
  });

  test("ALL with suffix path: descendPath failure causes violation", () => {
    const policy = PolicyBuilder.createRaw("(uint256,bytes)[]")
      .add(arg(0, Quantifier.ALL, 1).lengthEq(5n))
      .build();
    // Element with bogus bytes offset.
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(0n)}${word(42n)}${word(9999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
  });

  test("ANY with suffix path: descendPath failure is skipped", () => {
    const policy = PolicyBuilder.createRaw("(uint256,bytes)[]")
      .add(arg(0, Quantifier.ANY, 1).lengthEq(5n))
      .build();
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(0n)}${word(42n)}${word(9999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
    }
  });
});

///////////////////////////////////////////////////////////////////////////
// Array Shape Failure (malformed dynamic array)
///////////////////////////////////////////////////////////////////////////

describe("enforce - arrayShape failure", () => {
  test("fails when dynamic array offset points beyond calldata", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).eq(1n)).build();
    const callData: Hex = `0x${word(9999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
// Quantifier Element Resolution Failure (truncated elements)
///////////////////////////////////////////////////////////////////////////

describe("enforce - quantifier element failure paths", () => {
  test("ALL fails when element resolution fails (truncated calldata)", () => {
    const policy = PolicyBuilder.createRaw("(uint256,uint256)[]")
      .add(arg(0, Quantifier.ALL, 1).eq(42n))
      .build();
    // Claims 2 elements but only provides partial data.
    const callData: Hex = `0x${word(32n)}${word(2n)}${word(42n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
  });

  test("ANY skips elements that fail to resolve and continues", () => {
    const policy = PolicyBuilder.createRaw("(uint256,uint256)[]")
      .add(arg(0, Quantifier.ANY, 1).eq(42n))
      .build();
    // 2 elements — both complete, second has field(1) = 42.
    const callData: Hex = `0x${word(32n)}${word(2n)}${word(1n)}${word(1n)}${word(99n)}${word(42n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(true);
  });
});

///////////////////////////////////////////////////////////////////////////
// Tampered Policy Blobs (attack surface testing)
///////////////////////////////////////////////////////////////////////////

describe("enforce - tampered policy blobs (attack surface testing)", () => {
  test("path depth > MAX_PATH_DEPTH (33 steps) throws INVALID_PATH", () => {
    // Requires craftPolicy because adding 33 path steps changes rule size structurally.
    const policy = craftPolicy({
      descriptor: "01011f",
      scope: Scope.CALLDATA,
      pathHex: "0000".repeat(33),
      opCode: Op.EQ,
      dataHex: "00".repeat(32),
    });
    try {
      PolicyEnforcer.check(policy, `0x${"00".repeat(32)}`);
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(CallciumError);
      if (err instanceof CallciumError) {
        expect(err.code).toBe("INVALID_PATH");
        expect(err.message).toContain("exceeds maximum");
      }
    }
  });

  test("unknown context property ID throws INVALID_CONTEXT_PATH", () => {
    // Start from a valid context policy, then tamper the property ID bytes.
    const validPolicy = PolicyBuilder.createRaw("uint256")
      .add(msgSender().eq("0x0000000000000000000000000000000000000001"))
      .build();
    // Tamper: overwrite the 2-byte path from 0x0000 to 0xFFFF.
    const descLen = 3; // "01011f" = 3 bytes.
    const pathOffset = 1 + 4 + 2 + descLen + 1 + 6 + 2 + 1 + 1;
    const tamperedPolicy = tamper(validPolicy, pathOffset, "ffff");
    try {
      PolicyEnforcer.check(tamperedPolicy, `0x${"00".repeat(32)}`);
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(CallciumError);
      if (err instanceof CallciumError) {
        expect(err.code).toBe("INVALID_CONTEXT_PATH");
        expect(err.message).toContain("ffff");
      }
    }
  });

  test("locate() navigation failure from bad calldata pointer", () => {
    // Valid policy for uint256[] targeting index 1.
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, 1).eq(0n)).build();
    // Feed calldata where the dynamic array's base pointer is beyond bounds.
    const callData: Hex = `0x${word(9999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).not.toBe("VALUE_MISMATCH");
      expect(result.violations[0].message).toContain("Navigation failed");
    }
  });
});

///////////////////////////////////////////////////////////////////////////
// Context With Numeric Properties
///////////////////////////////////////////////////////////////////////////

describe("enforce - context numeric properties", () => {
  test("context msgValue check passes with matching value", () => {
    const policy = PolicyBuilder.createRaw("uint256").add(msgValue().lte(1000n)).add(arg(0).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), { msgValue: 500n });
    expect(result.ok).toBe(true);
  });

  test("context msgValue check fails when value exceeds limit", () => {
    const policy = PolicyBuilder.createRaw("uint256").add(msgValue().lte(100n)).add(arg(0).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), { msgValue: 200n });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violations[0].code).toBe("VALUE_MISMATCH");
      expect(result.violations[0].resolvedValue).toBeDefined();
    }
  });

  test("context blockTimestamp check works", () => {
    const policy = PolicyBuilder.createRaw("uint256").add(blockTimestamp().gte(1000n)).add(arg(0).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), { blockTimestamp: 2000n });
    expect(result.ok).toBe(true);
  });

  test("context blockNumber check works", () => {
    const policy = PolicyBuilder.createRaw("uint256").add(blockNumber().eq(12345n)).add(arg(0).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), { blockNumber: 12345n });
    expect(result.ok).toBe(true);
  });

  test("context chainId check works", () => {
    const policy = PolicyBuilder.createRaw("uint256").add(chainId().eq(1n)).add(arg(0).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), { chainId: 1n });
    expect(result.ok).toBe(true);
  });

  test("context txOrigin check works", () => {
    const policy = PolicyBuilder.createRaw("uint256")
      .add(txOrigin().eq("0x0000000000000000000000000000000000000001"))
      .add(arg(0).eq(42n))
      .build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), {
      txOrigin: "0x0000000000000000000000000000000000000001",
    });
    expect(result.ok).toBe(true);
  });
});

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
import { PolicyFormat } from "../src/constants";
import { DescriptorCoder } from "../src/descriptor-coder";
import { applyOperator } from "../src/operators";
import { assertFailed, assertPassed, assertViolationCode, firstViolation, op } from "./helpers";

import type { Context, Hex, PolicyData } from "../src";

///////////////////////////////////////////////////////////////////////////
// Test policy blobs
///////////////////////////////////////////////////////////////////////////

// EQ rule: arg(0) == 42, selector 0x2fbebd38, descriptor uint256.
const POLICY_EQ_UINT256 = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(42n)).build();

// Selectorless: EQ rule arg(0) == 42.
const POLICY_SELECTORLESS = PolicyBuilder.createRaw("uint256").add(arg(0).eq(42n)).build();

// Two groups (OR): EQ(arg0,2) | EQ(arg0,1).
const POLICY_MULTI_GROUP = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(2n)).or().add(arg(0).eq(1n)).build();

// Two calldata rules in one group: GT(0) AND LTE(100).
const POLICY_TWO_CONSTRAINTS = PolicyBuilder.create("foo(uint256)").add(arg(0).gt(0n).lte(100n)).build();

// Mixed scope: context msg.sender=addr(1) AND calldata arg(0)=uint256(42).
const POLICY_MIXED_SCOPE = PolicyBuilder.create("foo(uint256)")
  .add(msgSender().eq("0x0000000000000000000000000000000000000001"))
  .add(arg(0).eq(42n))
  .build();

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

const SELECTOR = "0x2fbebd38";

/** Pad a bigint into a 64-char hex word (no 0x prefix), for calldata concatenation. */
function word(value: bigint): string {
  return bigintToHex(value).slice(2);
}

/** Encode a single uint256 arg with selector prefix. */
function encodeUint256(selector: Hex, value: bigint): Hex {
  return `${selector}${word(value)}`;
}

/** Encode a raw uint256 without selector. */
function encodeRawUint256(value: bigint): Hex {
  return bigintToHex(value);
}

/** Encode a selectorless calldata blob containing a single `bytes` argument. */
function encodeBytesArg(dataHex: string): Hex {
  const padded = dataHex.padEnd(64, "0");
  return `0x${word(32n)}${word(BigInt(dataHex.length / 2))}${padded}`;
}

/** Encode a selectorless calldata blob containing a single dynamic uint256 array. */
function encodeDynamicUint256Array(elements: bigint[]): Hex {
  let body = word(32n) + word(BigInt(elements.length));
  for (const elem of elements) body += word(elem);
  return `0x${body}`;
}

/** Encode a selectorless calldata blob containing a static uint256[3] array. */
function encodeStaticUint256Array3(first: bigint, second: bigint, third: bigint): Hex {
  return `0x${word(first)}${word(second)}${word(third)}`;
}

/** Encode a selectorless calldata blob containing a dynamic int256 array. */
function encodeDynamicInt256Array(elements: bigint[]): Hex {
  return encodeDynamicUint256Array(elements.map((elem) => BigInt.asUintN(256, elem)));
}

/** Encode a selectorless calldata blob containing a dynamic bytes array; elements are hex bodies of at most 32 bytes. */
function encodeDynamicBytesArray(elements: string[]): Hex {
  let heads = "";
  let tails = "";
  const headSize = elements.length * 32;
  for (const elem of elements) {
    heads += word(BigInt(headSize + tails.length / 2));
    tails += word(BigInt(elem.length / 2)) + elem.padEnd(64, "0");
  }
  return `0x${word(32n)}${word(BigInt(elements.length))}${heads}${tails}`;
}

/** Encode selectorless calldata for (uint256,address)[] with given tuples. */
function encodeTupleArray(tuples: Array<{ amount: bigint; addr: bigint }>): Hex {
  let body = word(32n) + word(BigInt(tuples.length));
  for (const tuple of tuples) body += word(tuple.amount) + word(tuple.addr);
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
  /** Hint block; defaults to a hop-free block addressing a uint256 first argument. */
  hintHex?: string;
}): Hex {
  const desc = opts.descriptor;
  const descLen = desc.length / 2;
  const pathBytes = opts.pathHex;
  const depth = pathBytes.length / 4;
  const dataBytes = opts.dataHex;
  const dataLen = dataBytes.length / 2;
  const hintBytes = opts.scope === Scope.CALLDATA ? (opts.hintHex ?? "0000000000000020") : "";
  const ruleSize = 7 + depth * 2 + hintBytes.length / 2 + dataLen;

  const rule =
    ruleSize.toString(16).padStart(4, "0") +
    opts.scope.toString(16).padStart(2, "0") +
    depth.toString(16).padStart(2, "0") +
    pathBytes +
    hintBytes +
    opts.opCode.toString(16).padStart(2, "0") +
    dataLen.toString(16).padStart(4, "0") +
    dataBytes;

  const group = "0001" + (rule.length / 2).toString(16).padStart(8, "0") + rule;
  const headerByte = (PolicyFormat.VERSION | PolicyFormat.FLAG_NO_SELECTOR).toString(16).padStart(2, "0");
  const header = headerByte + "00000000" + descLen.toString(16).padStart(4, "0") + desc + "01" + group;
  return `0x${header}`;
}

/** Return the byte offset of the first rule's hint block within `policy`. */
function hintOffset(policy: Hex): number {
  return PolicyCoder.inspect(policy).groups[0].rules[0].hint!.span.start;
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
      assertPassed(result);
      expect(result.matchedGroup).toBe(0);
    });

    test("fails when callData does not match", () => {
      const callData = encodeUint256(SELECTOR, 99n);
      const result = PolicyEnforcer.check(POLICY_EQ_UINT256, callData);
      firstViolation(result, "VALUE_MISMATCH");
    });

    test("fails on selector mismatch", () => {
      const callData = "0x11111111000000000000000000000000000000000000000000000000000000000000002a";
      const result = PolicyEnforcer.check(POLICY_EQ_UINT256, callData);
      const violation = firstViolation(result, "SELECTOR_MISMATCH");
      expect(violation.resolvedValue).toBe("0x11111111");
    });
  });

  describe("selectorless policy", () => {
    test("passes with matching raw callData", () => {
      const callData = encodeRawUint256(42n);
      const result = PolicyEnforcer.check(POLICY_SELECTORLESS, callData);
      assertPassed(result);
      expect(result.matchedGroup).toBe(0);
    });

    test("fails with non-matching raw callData", () => {
      const callData = encodeRawUint256(99n);
      const result = PolicyEnforcer.check(POLICY_SELECTORLESS, callData);
      firstViolation(result, "VALUE_MISMATCH");
    });

    test("does not require selector in callData", () => {
      const callData = encodeRawUint256(42n);
      const result = PolicyEnforcer.check(POLICY_SELECTORLESS, callData);
      assertPassed(result);
    });
  });

  describe("multi-group (OR semantics)", () => {
    // Groups sort by hash, so the group holding each operand is derived from the built policy.
    function groupIndexOf(operand: bigint): number {
      return PolicyCoder.decode(POLICY_MULTI_GROUP).groups.findIndex((group) =>
        group[0].operators[0].endsWith(word(operand)),
      );
    }

    test("passes when the eq(2) group matches", () => {
      const callData = encodeUint256(SELECTOR, 2n);
      const result = PolicyEnforcer.check(POLICY_MULTI_GROUP, callData);
      assertPassed(result);
      expect(result.matchedGroup).toBe(groupIndexOf(2n));
    });

    test("passes when the eq(1) group matches", () => {
      const callData = encodeUint256(SELECTOR, 1n);
      const result = PolicyEnforcer.check(POLICY_MULTI_GROUP, callData);
      assertPassed(result);
      expect(result.matchedGroup).toBe(groupIndexOf(1n));
    });

    test("fails when no group matches", () => {
      const callData = encodeUint256(SELECTOR, 99n);
      const result = PolicyEnforcer.check(POLICY_MULTI_GROUP, callData);
      assertFailed(result);
      expect(result.violations.length).toBe(2);
      const first = result.violations[0];
      const second = result.violations[1];
      assertViolationCode(first, "VALUE_MISMATCH");
      assertViolationCode(second, "VALUE_MISMATCH");
      expect(first.group).toBe(0);
      expect(second.group).toBe(1);
    });
  });

  describe("two constraints in one group (AND semantics)", () => {
    test("passes when both constraints are satisfied", () => {
      const callData = encodeUint256(SELECTOR, 50n);
      const result = PolicyEnforcer.check(POLICY_TWO_CONSTRAINTS, callData);
      assertPassed(result);
    });

    test("fails when first constraint fails (value == 0)", () => {
      const callData = encodeUint256(SELECTOR, 0n);
      const result = PolicyEnforcer.check(POLICY_TWO_CONSTRAINTS, callData);
      firstViolation(result, "VALUE_MISMATCH");
    });

    test("fails when second constraint fails (value > 100)", () => {
      const callData = encodeUint256(SELECTOR, 101n);
      const result = PolicyEnforcer.check(POLICY_TWO_CONSTRAINTS, callData);
      firstViolation(result, "VALUE_MISMATCH");
    });

    test("passes at boundary (value == 100)", () => {
      const callData = encodeUint256(SELECTOR, 100n);
      const result = PolicyEnforcer.check(POLICY_TWO_CONSTRAINTS, callData);
      assertPassed(result);
    });

    test("passes at boundary (value == 1)", () => {
      const callData = encodeUint256(SELECTOR, 1n);
      const result = PolicyEnforcer.check(POLICY_TWO_CONSTRAINTS, callData);
      assertPassed(result);
    });
  });

  describe("mixed scope (context + calldata)", () => {
    test("passes when both context and calldata match", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const ctx: Context = { msgSender: "0x0000000000000000000000000000000000000001" };
      const result = PolicyEnforcer.check(POLICY_MIXED_SCOPE, callData, ctx);
      assertPassed(result);
    });

    test("fails when context is missing", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const result = PolicyEnforcer.check(POLICY_MIXED_SCOPE, callData);
      const violation = firstViolation(result, "MISSING_CONTEXT");
      expect(violation.typeCode).toBe(TypeCode.ADDRESS);
    });

    test("fails when context does not match", () => {
      const callData = encodeUint256(SELECTOR, 42n);
      const ctx: Context = { msgSender: "0x0000000000000000000000000000000000000002" };
      const result = PolicyEnforcer.check(POLICY_MIXED_SCOPE, callData, ctx);
      firstViolation(result, "VALUE_MISMATCH");
    });

    test("fails when calldata does not match", () => {
      const callData = encodeUint256(SELECTOR, 99n);
      const ctx: Context = { msgSender: "0x0000000000000000000000000000000000000001" };
      const result = PolicyEnforcer.check(POLICY_MIXED_SCOPE, callData, ctx);
      firstViolation(result, "VALUE_MISMATCH");
    });
  });

  describe("callData too short", () => {
    test("fails when callData is shorter than required", () => {
      const result = PolicyEnforcer.check(POLICY_EQ_UINT256, "0x2fbebd38");
      firstViolation(result, "CALLDATA_OUT_OF_BOUNDS");
    });

    test("fails when selectorless callData is empty", () => {
      const result = PolicyEnforcer.check(POLICY_SELECTORLESS, "0x");
      firstViolation(result, "CALLDATA_OUT_OF_BOUNDS");
    });

    test("fails when callData too short for selector check", () => {
      const result = PolicyEnforcer.check(POLICY_EQ_UINT256, "0x2fbe");
      firstViolation(result, "MISSING_SELECTOR");
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

  test("thrown error carries structured violations and a code-bearing message", () => {
    const callData = encodeUint256(SELECTOR, 99n);
    try {
      PolicyEnforcer.enforce(POLICY_EQ_UINT256, callData);
      expect.unreachable("should have thrown");
    } catch (error) {
      expect(error).toBeInstanceOf(PolicyViolationError);
      if (error instanceof PolicyViolationError) {
        expect(error.violations).toHaveLength(1);
        expect(error.violations[0].code).toBe("VALUE_MISMATCH");
        expect(error.message).toContain("VALUE_MISMATCH");
      }
    }
  });

  test("PolicyViolationError with empty violations carries fallback message", () => {
    const err = new PolicyViolationError([]);
    expect(err.message).toBe("Policy violation");
    expect(err.violations).toHaveLength(0);
  });

  test("PolicyViolationError surfaces structured violation fields, not formatted text", () => {
    const err = new PolicyViolationError([
      {
        code: "SELECTOR_MISMATCH",
        resolvedValue: "0x12345678",
        expectedValue: "0xabcdef00",
      },
    ]);
    expect(err.violations[0]).toMatchObject({
      code: "SELECTOR_MISMATCH",
      resolvedValue: "0x12345678",
      expectedValue: "0xabcdef00",
    });
    expect(err.message).toContain("SELECTOR_MISMATCH");
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
    assertPassed(result);
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
    firstViolation(result, "VALUE_MISMATCH");
  });
});

///////////////////////////////////////////////////////////////////////////
// Quantifier Edge Cases
///////////////////////////////////////////////////////////////////////////

describe("enforce - quantifier edge cases", () => {
  test("ANY on empty dynamic array fails with QUANTIFIER_EMPTY_ARRAY", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ANY).eq(1n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([]));
    firstViolation(result, "QUANTIFIER_EMPTY_ARRAY");
  });

  test("ALL on empty dynamic array passes (vacuously true)", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).gt(0n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([]));
    assertPassed(result);
  });

  test("ALL on static array passes when all elements satisfy the rule", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ALL).gt(0n)).build();
    const result = PolicyEnforcer.check(policy, encodeStaticUint256Array3(10n, 20n, 30n));
    assertPassed(result);
  });

  test("ALL on static array fails when one element does not satisfy the rule", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ALL).gt(0n)).build();
    const result = PolicyEnforcer.check(policy, encodeStaticUint256Array3(10n, 20n, 0n));
    firstViolation(result, "VALUE_MISMATCH");
  });

  test("ANY on static array passes when one element matches", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ANY).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeStaticUint256Array3(1n, 42n, 99n));
    assertPassed(result);
  });

  test("ANY on static array fails when no element matches", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ANY).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeStaticUint256Array3(1n, 2n, 3n));
    firstViolation(result, "VALUE_MISMATCH");
  });

  test("ANY short-circuits on first matching element", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ANY).eq(7n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([7n, 100n, 200n]));
    assertPassed(result);
  });

  test("NOT under ALL binds per element, not to the aggregate", () => {
    // ALL neq(1) over [1, 2]: element 1 fails 1 != 1, so ALL rejects.
    // Aggregate binding would compute !(ALL eq 1) and wrongly accept.
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).neq(1n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([1n, 2n]));
    firstViolation(result, "VALUE_MISMATCH");
  });

  test("NOT under ANY binds per element, not to the aggregate", () => {
    // ANY neq(1) over [1, 2]: element 2 satisfies 2 != 1, so ANY accepts.
    // Aggregate binding would compute !(ANY eq 1) and wrongly reject.
    // buildUnsafe: strict build rejects any().neq() as an authoring anti-pattern.
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ANY).neq(1n)).buildUnsafe();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([1n, 2n]));
    assertPassed(result);
  });

  test("composed strict ALL (lengthGt(0) + ALL) fails on an empty array", () => {
    const policy = PolicyBuilder.createRaw("uint256[]")
      .add(arg(0).lengthGt(0n))
      .add(arg(0, Quantifier.ALL).gt(0n))
      .build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([]));
    firstViolation(result, "VALUE_MISMATCH");
  });

  test("ALL on non-empty dynamic array fails when one element does not satisfy the rule", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).gt(0n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([5n, 0n]));
    firstViolation(result, "VALUE_MISMATCH");
  });

  test("ANY on dynamic array fails when no element matches", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ANY).eq(999n)).build();
    const result = PolicyEnforcer.check(policy, encodeDynamicUint256Array([1n, 2n, 3n]));
    const violation = firstViolation(result, "VALUE_MISMATCH");
    expect(violation.elementIndex).toBeUndefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Quantified operator coverage
///////////////////////////////////////////////////////////////////////////

describe("enforce - quantified value operators", () => {
  test("ALL lt passes and rejects an element at the bound", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).lt(4n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicUint256Array([1n, 2n, 3n])));

    const failing = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).lt(3n)).build();
    firstViolation(PolicyEnforcer.check(failing, encodeDynamicUint256Array([1n, 2n, 3n])), "VALUE_MISMATCH");
  });

  test("ALL gte passes and rejects an element below the bound", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).gte(1n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicUint256Array([1n, 2n, 3n])));

    const failing = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).gte(2n)).build();
    firstViolation(PolicyEnforcer.check(failing, encodeDynamicUint256Array([1n, 2n, 3n])), "VALUE_MISMATCH");
  });

  test("ALL lte passes and rejects an element above the bound", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).lte(3n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicUint256Array([1n, 2n, 3n])));

    const failing = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).lte(2n)).build();
    firstViolation(PolicyEnforcer.check(failing, encodeDynamicUint256Array([1n, 2n, 3n])), "VALUE_MISMATCH");
  });

  test("ALL between passes and rejects an element outside the range", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).between(1n, 3n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicUint256Array([1n, 2n, 3n])));

    const failing = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).between(2n, 3n)).build();
    firstViolation(PolicyEnforcer.check(failing, encodeDynamicUint256Array([1n, 2n, 3n])), "VALUE_MISMATCH");
  });

  test("ALL isIn passes and rejects an element outside the set", () => {
    const policy = PolicyBuilder.createRaw("uint256[]")
      .add(arg(0, Quantifier.ALL).isIn([10n, 20n, 30n]))
      .build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicUint256Array([10n, 30n])));

    firstViolation(PolicyEnforcer.check(policy, encodeDynamicUint256Array([10n, 11n])), "VALUE_MISMATCH");
  });

  test("ALL notIn passes and rejects an element inside the set", () => {
    const policy = PolicyBuilder.createRaw("uint256[]")
      .add(arg(0, Quantifier.ALL).notIn([10n, 20n, 30n]))
      .build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicUint256Array([1n, 2n])));

    firstViolation(PolicyEnforcer.check(policy, encodeDynamicUint256Array([1n, 10n])), "VALUE_MISMATCH");
  });

  test("ALL bitmaskAll passes and rejects an element missing a bit", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).bitmaskAll(0x0fn)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicUint256Array([0x0fn, 0xffn])));

    firstViolation(PolicyEnforcer.check(policy, encodeDynamicUint256Array([0x0fn, 0x07n])), "VALUE_MISMATCH");
  });

  test("ALL bitmaskAny passes and rejects an element with no mask bit", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).bitmaskAny(0x0fn)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicUint256Array([0x01n, 0x08n])));

    firstViolation(PolicyEnforcer.check(policy, encodeDynamicUint256Array([0x01n, 0xf0n])), "VALUE_MISMATCH");
  });

  test("ALL bitmaskNone passes and rejects an element with a mask bit", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).bitmaskNone(0x0fn)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicUint256Array([0xf0n, 0x10n])));

    firstViolation(PolicyEnforcer.check(policy, encodeDynamicUint256Array([0xf0n, 0x01n])), "VALUE_MISMATCH");
  });
});

describe("enforce - quantified length operators", () => {
  test("ALL lengthGt passes and rejects an element at the bound", () => {
    const policy = PolicyBuilder.createRaw("bytes[]").add(arg(0, Quantifier.ALL).lengthGt(1n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicBytesArray(["aaaa", "bbbbbb"])));

    firstViolation(PolicyEnforcer.check(policy, encodeDynamicBytesArray(["aaaa", "bb"])), "VALUE_MISMATCH");
  });

  test("ALL lengthLt passes and rejects an element at the bound", () => {
    const policy = PolicyBuilder.createRaw("bytes[]").add(arg(0, Quantifier.ALL).lengthLt(3n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicBytesArray(["aa", "bbbb"])));

    firstViolation(PolicyEnforcer.check(policy, encodeDynamicBytesArray(["aa", "bbbbbb"])), "VALUE_MISMATCH");
  });

  test("ALL lengthGte passes and rejects a shorter element", () => {
    const policy = PolicyBuilder.createRaw("bytes[]").add(arg(0, Quantifier.ALL).lengthGte(2n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicBytesArray(["aaaa", "bbbbbb"])));

    firstViolation(PolicyEnforcer.check(policy, encodeDynamicBytesArray(["aaaa", "bb"])), "VALUE_MISMATCH");
  });

  test("ALL lengthLte passes and rejects a longer element", () => {
    const policy = PolicyBuilder.createRaw("bytes[]").add(arg(0, Quantifier.ALL).lengthLte(2n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicBytesArray(["aa", "bbbb"])));

    firstViolation(PolicyEnforcer.check(policy, encodeDynamicBytesArray(["aa", "bbbbbb"])), "VALUE_MISMATCH");
  });

  test("ALL lengthBetween passes and rejects an element outside the range", () => {
    const policy = PolicyBuilder.createRaw("bytes[]").add(arg(0, Quantifier.ALL).lengthBetween(1n, 2n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicBytesArray(["aa", "bbbb"])));

    firstViolation(PolicyEnforcer.check(policy, encodeDynamicBytesArray(["aa", "bbbbbb"])), "VALUE_MISMATCH");
  });
});

describe("enforce - quantified signed ordering", () => {
  test("ALL lt: negative elements are less than a positive bound", () => {
    const policy = PolicyBuilder.createRaw("int256[]").add(arg(0, Quantifier.ALL).lt(1n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicInt256Array([-2n, -1n])));
  });

  test("ALL gt: elements above a negative bound", () => {
    const policy = PolicyBuilder.createRaw("int256[]").add(arg(0, Quantifier.ALL).gt(-200n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicInt256Array([-100n, 1n])));
  });

  test("ALL gte: negative bound inclusive", () => {
    const policy = PolicyBuilder.createRaw("int256[]").add(arg(0, Quantifier.ALL).gte(-42n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicInt256Array([-42n, 0n])));
  });

  test("ALL lte: negative bound inclusive", () => {
    const policy = PolicyBuilder.createRaw("int256[]").add(arg(0, Quantifier.ALL).lte(-42n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicInt256Array([-100n, -42n])));
  });

  test("ALL between: negative range", () => {
    const policy = PolicyBuilder.createRaw("int256[]").add(arg(0, Quantifier.ALL).between(-100n, -50n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicInt256Array([-75n, -60n])));
  });

  test("ALL between: range crossing zero", () => {
    const policy = PolicyBuilder.createRaw("int256[]").add(arg(0, Quantifier.ALL).between(-50n, 50n)).build();
    assertPassed(PolicyEnforcer.check(policy, encodeDynamicInt256Array([-10n, 0n, 10n])));
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
    const violation = firstViolation(result, "VALUE_MISMATCH");
    expect(violation.scope).toBe(Scope.CALLDATA);
    expect(violation.elementIndex).toBe(1);
    expect(violation.typeCode).toBe(TypeCode.UINT_MAX);
    expect(violation.resolvedValue).toBe(bigintToHex(0n));
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
    firstViolation(result, "VALUE_MISMATCH");
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
    firstViolation(result, "QUANTIFIER_LIMIT_EXCEEDED");
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
    assertFailed(result);
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
    const violation = firstViolation(result, "CALLDATA_OUT_OF_BOUNDS");
    expect(violation.elementIndex).toBe(2);
    expect(violation.typeCode).toBe(TypeCode.UINT_MAX);
  });

  test("an abort under ANY rejects the policy instead of falling through to a later group", () => {
    // Spec §9.3: CALLDATA_OUT_OF_BOUNDS aborts evaluation, so the passing second group is never
    // consulted. The Solidity enforcer reverts on the same input.
    const policy = PolicyBuilder.createRaw("uint256[],uint256")
      .add(arg(0, Quantifier.ANY).eq(7n))
      .or()
      .add(arg(1).eq(5n))
      .build();
    // The array claims two elements but supplies one.
    const callData: Hex = `0x${word(64n)}${word(5n)}${word(2n)}${word(1n)}`;

    firstViolation(PolicyEnforcer.check(policy, callData), "CALLDATA_OUT_OF_BOUNDS");
  });

  test("ANY aborts when arrayElementAt fails", () => {
    const policy = PolicyBuilder.createRaw("uint256[3]").add(arg(0, Quantifier.ANY).eq(999n)).build();
    // Only 64 bytes for 3-element static array.
    const callData: Hex = `0x${word(1n)}${word(2n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    firstViolation(result, "CALLDATA_OUT_OF_BOUNDS");
  });

  test("ALL with suffix: descendPath failure on element causes violation", () => {
    // (uint256[],uint256)[] — suffix navigates through a dynamic field whose pointer is bogus.
    const policy = PolicyBuilder.createRaw("(uint256[],uint256)[]")
      .add(arg(0, Quantifier.ALL, 0, 0).eq(42n))
      .build();
    // Dynamic array with 1 element: element tuple has field0=uint256[] with a bogus offset pointer.
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(0n)}${word(9999n)}${word(42n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    const violation = firstViolation(result, "ARRAY_INDEX_OUT_OF_BOUNDS");
    expect(violation.elementIndex).toBe(0);
    expect(violation.typeCode).toBe(TypeCode.UINT_MAX);
  });

  test("ANY with suffix: descendPath failure aborts", () => {
    const policy = PolicyBuilder.createRaw("(uint256[],uint256)[]")
      .add(arg(0, Quantifier.ANY, 0, 0).eq(42n))
      .build();
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(0n)}${word(9999n)}${word(42n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    const violation = firstViolation(result, "ARRAY_INDEX_OUT_OF_BOUNDS");
    expect(violation.elementIndex).toBe(0);
  });

  test("ALL with suffix: post-descend leaf-load failure surfaces underlying read code", () => {
    const policy = PolicyBuilder.createRaw("(uint256,uint256)[]")
      .add(arg(0, Quantifier.ALL, 1).gt(0n))
      .build();
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(42n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    const violation = firstViolation(result, "CALLDATA_OUT_OF_BOUNDS");
    expect(violation.elementIndex).toBe(0);
    expect(violation.typeCode).toBeDefined();
    expect(violation.opCode).toBeDefined();
    expect(violation.operandData).toBeDefined();
  });
});

describe("enforce - quantifier deep error paths", () => {
  test("ALL with no suffix: leaf error on element causes failure", () => {
    const policy = PolicyBuilder.createRaw("bytes[]").add(arg(0, Quantifier.ALL).lengthEq(5n)).build();
    // bytes[] with 1 element whose internal offset is invalid.
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(9999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    assertFailed(result);
  });

  test("ANY with no suffix: leaf error on an element aborts", () => {
    const policy = PolicyBuilder.createRaw("bytes[]").add(arg(0, Quantifier.ANY).lengthEq(5n)).build();
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(9999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    firstViolation(result, "CALLDATA_OUT_OF_BOUNDS");
  });

  test("ALL with suffix path: descendPath failure causes violation", () => {
    const policy = PolicyBuilder.createRaw("(uint256,bytes)[]")
      .add(arg(0, Quantifier.ALL, 1).lengthEq(5n))
      .build();
    // Element with bogus bytes offset.
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(0n)}${word(42n)}${word(9999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    assertFailed(result);
  });

  test("ANY with suffix path: descendPath failure aborts", () => {
    const policy = PolicyBuilder.createRaw("(uint256,bytes)[]")
      .add(arg(0, Quantifier.ANY, 1).lengthEq(5n))
      .build();
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(0n)}${word(42n)}${word(9999n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    firstViolation(result, "CALLDATA_OUT_OF_BOUNDS");
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
    assertFailed(result);
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
    assertFailed(result);
  });

  test("ANY skips elements that fail to resolve and continues", () => {
    const policy = PolicyBuilder.createRaw("(uint256,uint256)[]")
      .add(arg(0, Quantifier.ANY, 1).eq(42n))
      .build();
    // 2 elements — both complete, second has field(1) = 42.
    const callData: Hex = `0x${word(32n)}${word(2n)}${word(1n)}${word(1n)}${word(99n)}${word(42n)}`;
    const result = PolicyEnforcer.check(policy, callData);
    assertPassed(result);
  });
});

///////////////////////////////////////////////////////////////////////////
// Tampered Policy Blobs (attack surface testing)
///////////////////////////////////////////////////////////////////////////

describe("enforce - tampered policy blobs (attack surface testing)", () => {
  test("path depth > MAX_PATH_DEPTH (33 steps) throws PATH_TOO_DEEP", () => {
    // Requires craftPolicy because adding 33 path steps changes rule size structurally.
    const policy = craftPolicy({
      descriptor: "020120",
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
        expect(err.code).toBe("PATH_TOO_DEEP");
        expect(err.message).toContain("exceeds maximum");
      }
    }
  });

  test("unknown context property ID throws INVALID_CONTEXT_PROPERTY", () => {
    // Start from a valid context policy, then tamper the property ID bytes.
    const validPolicy = PolicyBuilder.createRaw("uint256")
      .add(msgSender().eq("0x0000000000000000000000000000000000000001"))
      .build();
    // Tamper: overwrite the 2-byte path from 0x0000 to 0xFFFF.
    const descLen = 3; // "020120" = 3 bytes.
    const pathOffset = 1 + 4 + 2 + descLen + 1 + 6 + 2 + 1 + 1;
    const tamperedPolicy = tamper(validPolicy, pathOffset, "ffff");
    try {
      PolicyEnforcer.check(tamperedPolicy, `0x${"00".repeat(32)}`);
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(CallciumError);
      if (err instanceof CallciumError) {
        expect(err.code).toBe("INVALID_CONTEXT_PROPERTY");
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
    const violation = firstViolation(result, "CALLDATA_OUT_OF_BOUNDS");
    expect(violation.scope).toBe(Scope.CALLDATA);
  });
});

///////////////////////////////////////////////////////////////////////////
// Context With Numeric Properties
///////////////////////////////////////////////////////////////////////////

describe("enforce - context numeric properties", () => {
  test("context msgValue check passes with matching value", () => {
    const policy = PolicyBuilder.createRaw("uint256").add(msgValue().lte(1000n)).add(arg(0).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), { msgValue: 500n });
    assertPassed(result);
  });

  test("context msgValue check fails when value exceeds limit", () => {
    const policy = PolicyBuilder.createRaw("uint256").add(msgValue().lte(100n)).add(arg(0).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), { msgValue: 200n });
    const violation = firstViolation(result, "VALUE_MISMATCH");
    expect(violation.resolvedValue).toBeDefined();
  });

  test("context blockTimestamp check works", () => {
    const policy = PolicyBuilder.createRaw("uint256").add(blockTimestamp().gte(1000n)).add(arg(0).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), { blockTimestamp: 2000n });
    assertPassed(result);
  });

  test("context blockNumber check works", () => {
    const policy = PolicyBuilder.createRaw("uint256").add(blockNumber().eq(12345n)).add(arg(0).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), { blockNumber: 12345n });
    assertPassed(result);
  });

  test("context chainId check works", () => {
    const policy = PolicyBuilder.createRaw("uint256").add(chainId().eq(1n)).add(arg(0).eq(42n)).build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), { chainId: 1n });
    assertPassed(result);
  });

  test("context txOrigin check works", () => {
    const policy = PolicyBuilder.createRaw("uint256")
      .add(txOrigin().eq("0x0000000000000000000000000000000000000001"))
      .add(arg(0).eq(42n))
      .build();
    const result = PolicyEnforcer.check(policy, encodeRawUint256(42n), {
      txOrigin: "0x0000000000000000000000000000000000000001",
    });
    assertPassed(result);
  });
});

///////////////////////////////////////////////////////////////////////////
// Value operator on non-scalar target
///////////////////////////////////////////////////////////////////////////

describe("PolicyEnforcer - value operator on non-scalar target", () => {
  test("throws NOT_SCALAR for value op on dynamic target", () => {
    // buildUnsafe: strict build rejects value operators on dynamic targets.
    const policy = PolicyBuilder.createRaw("bytes").add(arg(0).eq(0n)).buildUnsafe();
    try {
      PolicyEnforcer.check(policy, encodeBytesArg("1122"));
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(CallciumError);
      if (err instanceof CallciumError) {
        expect(err.code).toBe("NOT_SCALAR");
      }
    }
  });

  test("throws NOT_SCALAR for value op on dynamic array element", () => {
    const policy = PolicyBuilder.createRaw("bytes[]").add(arg(0, Quantifier.ALL).eq(0n)).buildUnsafe();
    // bytes[] with one 2-byte element: outer offset, length 1, element offset, element.
    const callData: Hex = `0x${word(32n)}${word(1n)}${word(32n)}${word(2n)}${"1122".padEnd(64, "0")}`;
    try {
      PolicyEnforcer.check(policy, callData);
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(CallciumError);
      if (err instanceof CallciumError) {
        expect(err.code).toBe("NOT_SCALAR");
      }
    }
  });
});

///////////////////////////////////////////////////////////////////////////
// Hint dispatch
///////////////////////////////////////////////////////////////////////////

// A calldata rule resolves its target through its compiled hint; path bytes are not consulted at
// evaluation time. Rewriting a stored hint therefore changes what the rule reads.

describe("enforce - hint dispatch", () => {
  test("a concrete hint addresses the target", () => {
    const policy = PolicyBuilder.createRaw("uint256,uint256").add(arg(0).eq(1n)).build();
    // Re-point the target delta at the second argument while the path still names the first.
    const tampered = tamper(policy, hintOffset(policy) + PolicyFormat.HINT_HEADER_SIZE, "00000020");

    assertPassed(PolicyEnforcer.check(tampered, `0x${word(9n)}${word(1n)}`));
  });

  test("path bytes do not address the target", () => {
    const policy = PolicyBuilder.createRaw("uint256,uint256").add(arg(0).eq(1n)).build();
    // Re-point the path at the second argument; the hint still addresses the first.
    const pathOffset = PolicyCoder.inspect(policy).groups[0].rules[0].path.span.start;
    const tampered = tamper(policy, pathOffset, "0001");

    assertPassed(PolicyEnforcer.check(tampered, `0x${word(1n)}${word(9n)}`));
    assertFailed(PolicyEnforcer.check(tampered, `0x${word(9n)}${word(1n)}`));
  });

  test("a quantified hint rejects an oversized array pointer", () => {
    const policy = PolicyBuilder.createRaw("uint256[]").add(arg(0, Quantifier.ALL).eq(1n)).build();
    // The array head word is far beyond calldata, so the read fails instead of wrapping.
    const callData: Hex = `0x${word(2n ** 200n)}${word(1n)}`;

    firstViolation(PolicyEnforcer.check(policy, callData), "CALLDATA_OUT_OF_BOUNDS");
  });

  test("a quantified hint addresses the element field", () => {
    const policy = PolicyBuilder.createRaw("(uint256,uint256)[]")
      .add(arg(0, Quantifier.ALL, 0).eq(1n))
      .build();
    // Re-point the target delta at the second field of each element.
    const targetDeltaOffset =
      hintOffset(policy) +
      PolicyFormat.HINT_HEADER_SIZE +
      PolicyFormat.HINT_HOP_SIZE +
      PolicyFormat.HINT_FRAME_PREFIX_SIZE +
      PolicyFormat.HINT_HEADER_SIZE;
    const tampered = tamper(policy, targetDeltaOffset, "00000020");

    const callData: Hex = `0x${word(32n)}${word(2n)}${word(9n)}${word(1n)}${word(9n)}${word(1n)}`;
    assertPassed(PolicyEnforcer.check(tampered, callData));
  });
});

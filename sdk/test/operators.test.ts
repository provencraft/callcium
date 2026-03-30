import { describe, expect, test } from "vitest";

import { Op, TypeCode } from "../src/constants";
import { applyOperator, isSigned, toBigInt } from "../src/operators";

// Packs a bigint into a 32-byte big-endian Uint8Array (two's complement for
// values that fit in 256 bits).
function word(value: bigint): Uint8Array {
  const buf = new Uint8Array(32);
  let v = value & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn;
  for (let i = 31; i >= 0; i--) {
    buf[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return buf;
}

// Concatenates multiple 32-byte words into a single Uint8Array.
function words(...values: bigint[]): Uint8Array {
  const buf = new Uint8Array(values.length * 32);
  for (let i = 0; i < values.length; i++) {
    buf.set(word(values[i]), i * 32);
  }
  return buf;
}

// Shorthand for the unsigned uint256 type code.
const UINT256 = TypeCode.UINT_MAX; // 0x1f
// Shorthand for the signed int256 type code.
const INT256 = TypeCode.INT_MAX; // 0x3f

const MAX_UINT256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn;

///////////////////////////////////////////////////////////////////////////
//                              toBigInt
///////////////////////////////////////////////////////////////////////////

describe("toBigInt", () => {
  test("zero", () => {
    expect(toBigInt(word(0n))).toBe(0n);
  });

  test("42", () => {
    expect(toBigInt(word(42n))).toBe(42n);
  });

  test("max uint256", () => {
    expect(toBigInt(word(MAX_UINT256))).toBe(MAX_UINT256);
  });

  test("with offset into concatenated words", () => {
    const data = words(1n, 42n);
    expect(toBigInt(data, 0)).toBe(1n);
    expect(toBigInt(data, 32)).toBe(42n);
  });
});

///////////////////////////////////////////////////////////////////////////
//                              isSigned
///////////////////////////////////////////////////////////////////////////

describe("isSigned", () => {
  test("uint types are unsigned", () => {
    expect(isSigned(TypeCode.UINT_MIN)).toBe(false);
    expect(isSigned(TypeCode.UINT_MAX)).toBe(false);
  });

  test("int types are signed", () => {
    expect(isSigned(TypeCode.INT_MIN)).toBe(true);
    expect(isSigned(TypeCode.INT_MAX)).toBe(true);
  });

  test("address is unsigned", () => {
    expect(isSigned(TypeCode.ADDRESS)).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                               Op.EQ
///////////////////////////////////////////////////////////////////////////

describe("Op.EQ", () => {
  test("equal values", () => {
    expect(applyOperator(Op.EQ, 7n, 0, word(7n), UINT256)).toBe(true);
  });

  test("unequal values", () => {
    expect(applyOperator(Op.EQ, 7n, 0, word(8n), UINT256)).toBe(false);
  });

  test("NOT flag inverts EQ result (true → false)", () => {
    expect(applyOperator(Op.EQ | Op.NOT, 7n, 0, word(7n), UINT256)).toBe(false);
  });

  test("NOT flag inverts EQ result (false → true)", () => {
    expect(applyOperator(Op.EQ | Op.NOT, 7n, 0, word(8n), UINT256)).toBe(true);
  });
});

///////////////////////////////////////////////////////////////////////////
//                    Op.GT / Op.LT — unsigned
///////////////////////////////////////////////////////////////////////////

describe("Op.GT unsigned", () => {
  test("greater value", () => {
    expect(applyOperator(Op.GT, 10n, 0, word(5n), UINT256)).toBe(true);
  });

  test("equal value", () => {
    expect(applyOperator(Op.GT, 5n, 0, word(5n), UINT256)).toBe(false);
  });

  test("smaller value", () => {
    expect(applyOperator(Op.GT, 3n, 0, word(5n), UINT256)).toBe(false);
  });

  // 0xFF..FF is max uint256 which is > 0 in unsigned interpretation.
  test("0xFF..FF > 0 is true for uint256", () => {
    expect(applyOperator(Op.GT, MAX_UINT256, 0, word(0n), UINT256)).toBe(true);
  });
});

describe("Op.GT signed", () => {
  // 0xFF..FF is -1 in two's complement, so it is NOT > 0.
  test("0xFF..FF > 0 is false for int256 (it is -1)", () => {
    expect(applyOperator(Op.GT, MAX_UINT256, 0, word(0n), INT256)).toBe(false);
  });

  test("1 > -1 is true", () => {
    expect(applyOperator(Op.GT, 1n, 0, word(MAX_UINT256), INT256)).toBe(true);
  });
});

describe("Op.LT unsigned", () => {
  test("smaller value", () => {
    expect(applyOperator(Op.LT, 3n, 0, word(5n), UINT256)).toBe(true);
  });

  test("equal value", () => {
    expect(applyOperator(Op.LT, 5n, 0, word(5n), UINT256)).toBe(false);
  });
});

describe("Op.LT signed", () => {
  // -1 represented as MAX_UINT256 should be < 0.
  test("-1 < 0 is true", () => {
    expect(applyOperator(Op.LT, MAX_UINT256, 0, word(0n), INT256)).toBe(true);
  });

  test("0 < -1 is false", () => {
    expect(applyOperator(Op.LT, 0n, 0, word(MAX_UINT256), INT256)).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                        Op.GTE / Op.LTE
///////////////////////////////////////////////////////////////////////////

describe("Op.GTE", () => {
  test("greater value", () => {
    expect(applyOperator(Op.GTE, 10n, 0, word(5n), UINT256)).toBe(true);
  });

  test("equal value", () => {
    expect(applyOperator(Op.GTE, 5n, 0, word(5n), UINT256)).toBe(true);
  });

  test("smaller value", () => {
    expect(applyOperator(Op.GTE, 4n, 0, word(5n), UINT256)).toBe(false);
  });
});

describe("Op.LTE", () => {
  test("smaller value", () => {
    expect(applyOperator(Op.LTE, 3n, 0, word(5n), UINT256)).toBe(true);
  });

  test("equal value", () => {
    expect(applyOperator(Op.LTE, 5n, 0, word(5n), UINT256)).toBe(true);
  });

  test("greater value", () => {
    expect(applyOperator(Op.LTE, 6n, 0, word(5n), UINT256)).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                           Op.BETWEEN
///////////////////////////////////////////////////////////////////////////

describe("Op.BETWEEN", () => {
  test("value at lower boundary (inclusive)", () => {
    expect(applyOperator(Op.BETWEEN, 5n, 0, words(5n, 10n), UINT256)).toBe(true);
  });

  test("value at upper boundary (inclusive)", () => {
    expect(applyOperator(Op.BETWEEN, 10n, 0, words(5n, 10n), UINT256)).toBe(true);
  });

  test("value in middle of range", () => {
    expect(applyOperator(Op.BETWEEN, 7n, 0, words(5n, 10n), UINT256)).toBe(true);
  });

  test("value below range", () => {
    expect(applyOperator(Op.BETWEEN, 4n, 0, words(5n, 10n), UINT256)).toBe(false);
  });

  test("value above range", () => {
    expect(applyOperator(Op.BETWEEN, 11n, 0, words(5n, 10n), UINT256)).toBe(false);
  });

  test("signed: -2 between -5 and 0 is true", () => {
    // -2, -5, 0 in two's complement 256-bit
    const neg2 = MAX_UINT256 - 1n;
    const neg5 = MAX_UINT256 - 4n;
    expect(applyOperator(Op.BETWEEN, neg2, 0, words(neg5, 0n), INT256)).toBe(true);
  });

  test("signed: 1 between -5 and 0 is false", () => {
    const neg5 = MAX_UINT256 - 4n;
    expect(applyOperator(Op.BETWEEN, 1n, 0, words(neg5, 0n), INT256)).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                               Op.IN
///////////////////////////////////////////////////////////////////////////

describe("Op.IN", () => {
  test("value found in single-element set", () => {
    expect(applyOperator(Op.IN, 42n, 0, words(42n), UINT256)).toBe(true);
  });

  test("value not found in single-element set", () => {
    expect(applyOperator(Op.IN, 7n, 0, words(42n), UINT256)).toBe(false);
  });

  test("value found in multi-element sorted set", () => {
    expect(applyOperator(Op.IN, 30n, 0, words(10n, 20n, 30n, 40n, 50n), UINT256)).toBe(true);
  });

  test("value not found in multi-element sorted set", () => {
    expect(applyOperator(Op.IN, 25n, 0, words(10n, 20n, 30n, 40n, 50n), UINT256)).toBe(false);
  });

  test("finds first element", () => {
    expect(applyOperator(Op.IN, 10n, 0, words(10n, 20n, 30n), UINT256)).toBe(true);
  });

  test("finds last element", () => {
    expect(applyOperator(Op.IN, 30n, 0, words(10n, 20n, 30n), UINT256)).toBe(true);
  });

  // IN is always unsigned: MAX_UINT256 is a large positive number, not -1.
  test("IN comparison is always unsigned regardless of typeCode", () => {
    // MAX_UINT256 is greater than 0 in unsigned comparison, so sorted set
    // [0, MAX_UINT256] should find MAX_UINT256.
    expect(applyOperator(Op.IN, MAX_UINT256, 0, words(0n, MAX_UINT256), INT256)).toBe(true);
  });
});

///////////////////////////////////////////////////////////////////////////
//                    Op.BITMASK_ALL / ANY / NONE
///////////////////////////////////////////////////////////////////////////

describe("Op.BITMASK_ALL", () => {
  // value=0b1111, mask=0b1010 → (0b1111 & 0b1010) = 0b1010 === 0b1010 → true.
  test("value has all mask bits set", () => {
    expect(applyOperator(Op.BITMASK_ALL, 0b1111n, 0, word(0b1010n), UINT256)).toBe(true);
  });

  // value=0b1010, mask=0b1010 → exact match.
  test("value matches mask exactly", () => {
    expect(applyOperator(Op.BITMASK_ALL, 0b1010n, 0, word(0b1010n), UINT256)).toBe(true);
  });

  // value=0b0110, mask=0b1001 → (0b0110 & 0b1001) = 0 ≠ 0b1001 → false.
  test("value is missing required mask bits", () => {
    expect(applyOperator(Op.BITMASK_ALL, 0b0110n, 0, word(0b1001n), UINT256)).toBe(false);
  });
});

describe("Op.BITMASK_ANY", () => {
  test("at least one bit matches", () => {
    expect(applyOperator(Op.BITMASK_ANY, 0b1010n, 0, word(0b1000n), UINT256)).toBe(true);
  });

  test("no bits match", () => {
    expect(applyOperator(Op.BITMASK_ANY, 0b0101n, 0, word(0b1010n), UINT256)).toBe(false);
  });

  test("zero value never matches any mask", () => {
    expect(applyOperator(Op.BITMASK_ANY, 0n, 0, word(0b1111n), UINT256)).toBe(false);
  });
});

describe("Op.BITMASK_NONE", () => {
  test("no bits match", () => {
    expect(applyOperator(Op.BITMASK_NONE, 0b0101n, 0, word(0b1010n), UINT256)).toBe(true);
  });

  test("some bits match", () => {
    expect(applyOperator(Op.BITMASK_NONE, 0b1010n, 0, word(0b1000n), UINT256)).toBe(false);
  });

  test("all bits match", () => {
    expect(applyOperator(Op.BITMASK_NONE, 0b1111n, 0, word(0b1111n), UINT256)).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                        LENGTH_* operators
///////////////////////////////////////////////////////////////////////////

describe("LENGTH_EQ", () => {
  test("length matches operand", () => {
    expect(applyOperator(Op.LENGTH_EQ, 0n, 32, word(32n), TypeCode.BYTES)).toBe(true);
  });

  test("length does not match operand", () => {
    expect(applyOperator(Op.LENGTH_EQ, 0n, 16, word(32n), TypeCode.BYTES)).toBe(false);
  });

  test("valid for TypeCode.STRING", () => {
    expect(applyOperator(Op.LENGTH_EQ, 0n, 5, word(5n), TypeCode.STRING)).toBe(true);
  });

  test("valid for TypeCode.DYNAMIC_ARRAY", () => {
    expect(applyOperator(Op.LENGTH_EQ, 0n, 3, word(3n), TypeCode.DYNAMIC_ARRAY)).toBe(true);
  });

  test("rejected for static type (address)", () => {
    expect(applyOperator(Op.LENGTH_EQ, 0n, 20, word(20n), TypeCode.ADDRESS)).toBe(false);
  });

  test("rejected for uint256", () => {
    expect(applyOperator(Op.LENGTH_EQ, 0n, 32, word(32n), UINT256)).toBe(false);
  });
});

describe("LENGTH_GT", () => {
  test("length greater than operand", () => {
    expect(applyOperator(Op.LENGTH_GT, 0n, 10, word(5n), TypeCode.BYTES)).toBe(true);
  });

  test("length equal to operand", () => {
    expect(applyOperator(Op.LENGTH_GT, 0n, 5, word(5n), TypeCode.BYTES)).toBe(false);
  });

  test("rejected for static type", () => {
    expect(applyOperator(Op.LENGTH_GT, 0n, 10, word(5n), TypeCode.ADDRESS)).toBe(false);
  });
});

describe("LENGTH_LT", () => {
  test("length less than operand", () => {
    expect(applyOperator(Op.LENGTH_LT, 0n, 3, word(5n), TypeCode.BYTES)).toBe(true);
  });

  test("length equal to operand", () => {
    expect(applyOperator(Op.LENGTH_LT, 0n, 5, word(5n), TypeCode.BYTES)).toBe(false);
  });
});

describe("LENGTH_GTE", () => {
  test("length greater than operand", () => {
    expect(applyOperator(Op.LENGTH_GTE, 0n, 6, word(5n), TypeCode.BYTES)).toBe(true);
  });

  test("length equal to operand", () => {
    expect(applyOperator(Op.LENGTH_GTE, 0n, 5, word(5n), TypeCode.BYTES)).toBe(true);
  });

  test("length less than operand", () => {
    expect(applyOperator(Op.LENGTH_GTE, 0n, 4, word(5n), TypeCode.BYTES)).toBe(false);
  });
});

describe("LENGTH_LTE", () => {
  test("length less than operand", () => {
    expect(applyOperator(Op.LENGTH_LTE, 0n, 4, word(5n), TypeCode.BYTES)).toBe(true);
  });

  test("length equal to operand", () => {
    expect(applyOperator(Op.LENGTH_LTE, 0n, 5, word(5n), TypeCode.BYTES)).toBe(true);
  });

  test("length greater than operand", () => {
    expect(applyOperator(Op.LENGTH_LTE, 0n, 6, word(5n), TypeCode.BYTES)).toBe(false);
  });
});

describe("LENGTH_BETWEEN", () => {
  test("length at lower boundary (inclusive)", () => {
    expect(applyOperator(Op.LENGTH_BETWEEN, 0n, 5, words(5n, 10n), TypeCode.BYTES)).toBe(true);
  });

  test("length at upper boundary (inclusive)", () => {
    expect(applyOperator(Op.LENGTH_BETWEEN, 0n, 10, words(5n, 10n), TypeCode.BYTES)).toBe(true);
  });

  test("length in middle of range", () => {
    expect(applyOperator(Op.LENGTH_BETWEEN, 0n, 7, words(5n, 10n), TypeCode.BYTES)).toBe(true);
  });

  test("length below range", () => {
    expect(applyOperator(Op.LENGTH_BETWEEN, 0n, 4, words(5n, 10n), TypeCode.BYTES)).toBe(false);
  });

  test("length above range", () => {
    expect(applyOperator(Op.LENGTH_BETWEEN, 0n, 11, words(5n, 10n), TypeCode.BYTES)).toBe(false);
  });

  test("rejected for static type", () => {
    expect(applyOperator(Op.LENGTH_BETWEEN, 0n, 7, words(5n, 10n), TypeCode.ADDRESS)).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                    NOT flag with non-EQ operators
///////////////////////////////////////////////////////////////////////////

describe("Op.NOT flag", () => {
  test("NOT GT inverts result", () => {
    // 10 > 5 is true, so NOT GT should be false.
    expect(applyOperator(Op.GT | Op.NOT, 10n, 0, word(5n), UINT256)).toBe(false);
  });

  test("NOT IN inverts result", () => {
    expect(applyOperator(Op.IN | Op.NOT, 99n, 0, words(10n, 20n, 30n), UINT256)).toBe(true);
  });
});

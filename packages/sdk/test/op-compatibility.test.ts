import { describe, expect, test } from "vitest";

import { isOpAllowed, Op, TypeCode } from "../src";

import type { TypeInfo } from "../src";

///////////////////////////////////////////////////////////////////////////
// Test type info fixtures
///////////////////////////////////////////////////////////////////////////

const uint256: TypeInfo = { typeCode: TypeCode.UINT_MAX, isDynamic: false, staticSize: 32 };
const int256: TypeInfo = { typeCode: TypeCode.INT_MAX, isDynamic: false, staticSize: 32 };
const uint8: TypeInfo = { typeCode: TypeCode.UINT_MIN, isDynamic: false, staticSize: 32 };
const address: TypeInfo = { typeCode: TypeCode.ADDRESS, isDynamic: false, staticSize: 32 };
const bool: TypeInfo = { typeCode: TypeCode.BOOL, isDynamic: false, staticSize: 32 };
const bytes32: TypeInfo = { typeCode: TypeCode.FIXED_BYTES_MAX, isDynamic: false, staticSize: 32 };
const bytes1: TypeInfo = { typeCode: TypeCode.FIXED_BYTES_MIN, isDynamic: false, staticSize: 32 };
const dynamicBytes: TypeInfo = { typeCode: TypeCode.BYTES, isDynamic: true, staticSize: 0 };
const string_: TypeInfo = { typeCode: TypeCode.STRING, isDynamic: true, staticSize: 0 };
const dynamicArray: TypeInfo = { typeCode: TypeCode.DYNAMIC_ARRAY, isDynamic: true, staticSize: 0 };
const tuple: TypeInfo = { typeCode: TypeCode.TUPLE, isDynamic: false, staticSize: 64 };

///////////////////////////////////////////////////////////////////////////
// Value operators (EQ, GT, LT, GTE, LTE, BETWEEN, IN)
///////////////////////////////////////////////////////////////////////////

describe("isOpAllowed - value operators", () => {
  const valueOps = [Op.EQ, Op.GT, Op.LT, Op.GTE, Op.LTE, Op.BETWEEN, Op.IN];
  const comparisonOps = [Op.GT, Op.LT, Op.GTE, Op.LTE, Op.BETWEEN];

  test("allowed on uint256", () => {
    for (const op of valueOps) expect(isOpAllowed(op, uint256)).toBe(true);
  });

  test("allowed on int256", () => {
    for (const op of valueOps) expect(isOpAllowed(op, int256)).toBe(true);
  });

  test("allowed on uint8", () => {
    for (const op of valueOps) expect(isOpAllowed(op, uint8)).toBe(true);
  });

  test("EQ and IN allowed on address, comparison ops forbidden", () => {
    expect(isOpAllowed(Op.EQ, address)).toBe(true);
    expect(isOpAllowed(Op.IN, address)).toBe(true);
    for (const op of comparisonOps) expect(isOpAllowed(op, address)).toBe(false);
  });

  test("EQ and IN allowed on bool, comparison ops forbidden", () => {
    expect(isOpAllowed(Op.EQ, bool)).toBe(true);
    expect(isOpAllowed(Op.IN, bool)).toBe(true);
    for (const op of comparisonOps) expect(isOpAllowed(op, bool)).toBe(false);
  });

  test("allowed on bytes32", () => {
    expect(isOpAllowed(Op.EQ, bytes32)).toBe(true);
    expect(isOpAllowed(Op.IN, bytes32)).toBe(true);
    for (const op of comparisonOps) expect(isOpAllowed(op, bytes32)).toBe(false);
  });

  test("allowed on bytes1 (fixed-size, not numeric)", () => {
    expect(isOpAllowed(Op.EQ, bytes1)).toBe(true);
    expect(isOpAllowed(Op.IN, bytes1)).toBe(true);
    for (const op of comparisonOps) expect(isOpAllowed(op, bytes1)).toBe(false);
  });

  test("forbidden on dynamic bytes", () => {
    for (const op of valueOps) expect(isOpAllowed(op, dynamicBytes)).toBe(false);
  });

  test("forbidden on string", () => {
    for (const op of valueOps) expect(isOpAllowed(op, string_)).toBe(false);
  });

  test("forbidden on dynamic array", () => {
    for (const op of valueOps) expect(isOpAllowed(op, dynamicArray)).toBe(false);
  });

  test("forbidden on tuple (non-32 staticSize)", () => {
    for (const op of valueOps) expect(isOpAllowed(op, tuple)).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
// Bitmask operators (BITMASK_ALL, BITMASK_ANY, BITMASK_NONE)
///////////////////////////////////////////////////////////////////////////

describe("isOpAllowed - bitmask operators", () => {
  const bitmaskOps = [Op.BITMASK_ALL, Op.BITMASK_ANY, Op.BITMASK_NONE];

  test("allowed on uint256", () => {
    for (const op of bitmaskOps) expect(isOpAllowed(op, uint256)).toBe(true);
  });

  test("allowed on uint8", () => {
    for (const op of bitmaskOps) expect(isOpAllowed(op, uint8)).toBe(true);
  });

  test("allowed on bytes32", () => {
    for (const op of bitmaskOps) expect(isOpAllowed(op, bytes32)).toBe(true);
  });

  test("forbidden on int256 (signed)", () => {
    for (const op of bitmaskOps) expect(isOpAllowed(op, int256)).toBe(false);
  });

  test("forbidden on address", () => {
    for (const op of bitmaskOps) expect(isOpAllowed(op, address)).toBe(false);
  });

  test("forbidden on bool", () => {
    for (const op of bitmaskOps) expect(isOpAllowed(op, bool)).toBe(false);
  });

  test("forbidden on bytes1 (not bytes32)", () => {
    for (const op of bitmaskOps) expect(isOpAllowed(op, bytes1)).toBe(false);
  });

  test("forbidden on dynamic bytes", () => {
    for (const op of bitmaskOps) expect(isOpAllowed(op, dynamicBytes)).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
// Length operators
///////////////////////////////////////////////////////////////////////////

describe("isOpAllowed - length operators", () => {
  const lengthOps = [Op.LENGTH_EQ, Op.LENGTH_GT, Op.LENGTH_LT, Op.LENGTH_GTE, Op.LENGTH_LTE, Op.LENGTH_BETWEEN];

  test("allowed on dynamic bytes", () => {
    for (const op of lengthOps) expect(isOpAllowed(op, dynamicBytes)).toBe(true);
  });

  test("allowed on string", () => {
    for (const op of lengthOps) expect(isOpAllowed(op, string_)).toBe(true);
  });

  test("allowed on dynamic array", () => {
    for (const op of lengthOps) expect(isOpAllowed(op, dynamicArray)).toBe(true);
  });

  test("forbidden on uint256", () => {
    for (const op of lengthOps) expect(isOpAllowed(op, uint256)).toBe(false);
  });

  test("forbidden on address", () => {
    for (const op of lengthOps) expect(isOpAllowed(op, address)).toBe(false);
  });

  test("forbidden on bytes32 (fixed-size bytes)", () => {
    for (const op of lengthOps) expect(isOpAllowed(op, bytes32)).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
// NOT flag tolerance
///////////////////////////////////////////////////////////////////////////

describe("isOpAllowed - NOT flag", () => {
  test("EQ | NOT behaves like EQ", () => {
    expect(isOpAllowed(Op.EQ | Op.NOT, uint256)).toBe(true);
    expect(isOpAllowed(Op.EQ | Op.NOT, address)).toBe(true);
    expect(isOpAllowed(Op.EQ | Op.NOT, dynamicBytes)).toBe(false);
  });

  test("IN | NOT behaves like IN", () => {
    expect(isOpAllowed(Op.IN | Op.NOT, uint256)).toBe(true);
    expect(isOpAllowed(Op.IN | Op.NOT, address)).toBe(true);
    expect(isOpAllowed(Op.IN | Op.NOT, dynamicBytes)).toBe(false);
  });

  test("GT | NOT behaves like GT", () => {
    expect(isOpAllowed(Op.GT | Op.NOT, uint256)).toBe(true);
    expect(isOpAllowed(Op.GT | Op.NOT, address)).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
// Unknown opcodes
///////////////////////////////////////////////////////////////////////////

describe("isOpAllowed - unknown opcodes", () => {
  test("returns false for unknown op code", () => {
    expect(isOpAllowed(0xff, uint256)).toBe(false);
    expect(isOpAllowed(0x30, address)).toBe(false);
  });
});

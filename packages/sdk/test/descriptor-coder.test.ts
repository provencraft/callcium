import { describe, expect, test } from "vitest";

import { DescriptorFormat as DF, TypeCode } from "../src/constants";
import { DescriptorCoder } from "../src/descriptor-coder";
import { decodeDescriptor } from "../src/descriptor-coder";
import { expectErrorCode } from "./helpers";

///////////////////////////////////////////////////////////////////////////
// Round-trip helper
///////////////////////////////////////////////////////////////////////////

/** Verify that encoded bytes decode without error and return the decoded param count. */
function decodeParamCount(bytes: Uint8Array): number {
  const { descriptor } = decodeDescriptor(bytes);
  return descriptor.params.length;
}

///////////////////////////////////////////////////////////////////////////
// Empty / header
///////////////////////////////////////////////////////////////////////////

describe("DescriptorCoder.fromTypes", () => {
  test("empty string → [VERSION, 0x00]", () => {
    expect(DescriptorCoder.fromTypes("")).toEqual(new Uint8Array([DF.VERSION, 0x00]));
  });

  ///////////////////////////////////////////////////////////////////////////
  // Elementary types
  ///////////////////////////////////////////////////////////////////////////

  test("uint256 → 1 param", () => {
    const bytes = DescriptorCoder.fromTypes("uint256");
    expect(bytes[0]).toBe(DF.VERSION);
    expect(bytes[1]).toBe(1);
    expect(bytes[2]).toBe(TypeCode.UINT_MAX);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("address → 1 param", () => {
    const bytes = DescriptorCoder.fromTypes("address");
    expect(bytes[2]).toBe(TypeCode.ADDRESS);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("bool → 1 param", () => {
    const bytes = DescriptorCoder.fromTypes("bool");
    expect(bytes[2]).toBe(TypeCode.BOOL);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("bytes32 → 1 param", () => {
    const bytes = DescriptorCoder.fromTypes("bytes32");
    expect(bytes[2]).toBe(TypeCode.FIXED_BYTES_MIN + 31);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("bytes1 → 1 param", () => {
    const bytes = DescriptorCoder.fromTypes("bytes1");
    expect(bytes[2]).toBe(TypeCode.FIXED_BYTES_MIN);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("bytes (dynamic) → 1 param", () => {
    const bytes = DescriptorCoder.fromTypes("bytes");
    expect(bytes[2]).toBe(TypeCode.BYTES);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("string → 1 param", () => {
    const bytes = DescriptorCoder.fromTypes("string");
    expect(bytes[2]).toBe(TypeCode.STRING);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("int8 → 1 param", () => {
    const bytes = DescriptorCoder.fromTypes("int8");
    expect(bytes[2]).toBe(TypeCode.INT_MIN);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("uint8 → 1 param", () => {
    const bytes = DescriptorCoder.fromTypes("uint8");
    expect(bytes[2]).toBe(TypeCode.UINT_MIN);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("function → 1 param", () => {
    const bytes = DescriptorCoder.fromTypes("function");
    expect(bytes[2]).toBe(TypeCode.FUNCTION);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  ///////////////////////////////////////////////////////////////////////////
  // Multiple params
  ///////////////////////////////////////////////////////////////////////////

  test("address,uint256 → 2 params", () => {
    const bytes = DescriptorCoder.fromTypes("address,uint256");
    expect(bytes[1]).toBe(2);
    expect(bytes[2]).toBe(TypeCode.ADDRESS);
    expect(bytes[3]).toBe(TypeCode.UINT_MAX);
    expect(decodeParamCount(bytes)).toBe(2);
  });

  ///////////////////////////////////////////////////////////////////////////
  // Arrays
  ///////////////////////////////////////////////////////////////////////////

  test("uint256[] → dynamic array", () => {
    const bytes = DescriptorCoder.fromTypes("uint256[]");
    expect(bytes[1]).toBe(1);
    expect(bytes[2]).toBe(TypeCode.DYNAMIC_ARRAY);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("address[5] → static array of length 5", () => {
    const bytes = DescriptorCoder.fromTypes("address[5]");
    expect(bytes[1]).toBe(1);
    expect(bytes[2]).toBe(TypeCode.STATIC_ARRAY);
    // length suffix is at the end: 2-byte BE16 value 5
    const lengthHi = bytes[bytes.length - 2];
    const lengthLo = bytes[bytes.length - 1];
    expect((lengthHi << 8) | lengthLo).toBe(5);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("uint256[][] → nested dynamic array", () => {
    const bytes = DescriptorCoder.fromTypes("uint256[][]");
    expect(bytes[1]).toBe(1);
    expect(bytes[2]).toBe(TypeCode.DYNAMIC_ARRAY);
    expect(bytes[DF.HEADER_SIZE + DF.ARRAY_HEADER_SIZE]).toBe(TypeCode.DYNAMIC_ARRAY);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  ///////////////////////////////////////////////////////////////////////////
  // Tuples
  ///////////////////////////////////////////////////////////////////////////

  test("(address,uint256) → tuple with 2 fields", () => {
    const bytes = DescriptorCoder.fromTypes("(address,uint256)");
    expect(bytes[1]).toBe(1);
    expect(bytes[2]).toBe(TypeCode.TUPLE);
    // header(2) + typecode(1) + meta24(3) = offset 6 for fieldCount BE16
    const fieldCount = (bytes[6] << 8) | bytes[7];
    expect(fieldCount).toBe(2);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("(bool,(uint8,bytes32)) → nested tuple", () => {
    const bytes = DescriptorCoder.fromTypes("(bool,(uint8,bytes32))");
    expect(bytes[1]).toBe(1);
    expect(bytes[2]).toBe(TypeCode.TUPLE);
    // header(2) + typecode(1) + meta24(3) = offset 6 for fieldCount BE16
    const outerFieldCount = (bytes[6] << 8) | bytes[7];
    expect(outerFieldCount).toBe(2);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  test("(address,uint256)[] → dynamic array of tuples", () => {
    const bytes = DescriptorCoder.fromTypes("(address,uint256)[]");
    expect(bytes[1]).toBe(1);
    expect(bytes[2]).toBe(TypeCode.DYNAMIC_ARRAY);
    expect(bytes[2 + DF.ARRAY_HEADER_SIZE]).toBe(TypeCode.TUPLE);
    expect(decodeParamCount(bytes)).toBe(1);
  });

  ///////////////////////////////////////////////////////////////////////////
  // Error cases
  ///////////////////////////////////////////////////////////////////////////

  test("unknown type 'foo' throws UNKNOWN_TYPE", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("foo"), "UNKNOWN_TYPE");
  });

  test("malformed tuple '(' throws INVALID_TYPE_STRING", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("("), "INVALID_TYPE_STRING");
  });

  test("trailing comma 'uint256,' throws INVALID_TYPE_STRING", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("uint256,"), "INVALID_TYPE_STRING");
  });

  test("empty tuple '()' throws INVALID_TYPE_STRING", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("()"), "INVALID_TYPE_STRING");
  });

  test("unclosed array bracket 'uint256[' throws UNKNOWN_TYPE", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("uint256["), "UNKNOWN_TYPE");
  });

  test("unmatched closing bracket ']' throws INVALID_TYPE_STRING", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("uint256]"), "INVALID_TYPE_STRING");
  });

  test("non-numeric array length 'uint256[abc]' throws INVALID_TYPE_STRING", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("uint256[abc]"), "INVALID_TYPE_STRING");
  });

  test("non-numeric bytesN 'bytesXX' throws UNKNOWN_TYPE", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("bytesXX"), "UNKNOWN_TYPE");
  });

  test("non-numeric intN 'intXX' throws UNKNOWN_TYPE", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("intXX"), "UNKNOWN_TYPE");
  });
});

///////////////////////////////////////////////////////////////////////////
// toTypes
///////////////////////////////////////////////////////////////////////////

describe("DescriptorCoder.toTypes", () => {
  test.each([
    "",
    "address",
    "uint256",
    "bool",
    "bytes32",
    "bytes1",
    "bytes",
    "string",
    "int8",
    "uint8",
    "function",
    "address,uint256",
    "uint256[]",
    "address[5]",
    "uint256[][]",
    "(address,uint256)",
    "(bool,(uint8,bytes32))",
    "(address,uint256)[]",
    "address,uint256,(bool,bytes32)[],string",
  ])("roundtrip: %s", (typesCsv) => {
    const desc = DescriptorCoder.fromTypes(typesCsv);
    expect(DescriptorCoder.toTypes(desc)).toBe(typesCsv);
  });
});

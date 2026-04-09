import { describe, expect, test } from "vitest";

import { TypeCode, DescriptorFormat as DF } from "../src/constants";
import {
  address,
  bool,
  function_,
  uint256,
  int256,
  uintN,
  intN,
  bytes,
  string_,
  bytesN,
  bytes32,
  enum_,
  array,
  tuple,
  struct,
} from "../src/type-desc";
import { expectErrorCode } from "./helpers";

///////////////////////////////////////////////////////////////////////////
// Elementary types
///////////////////////////////////////////////////////////////////////////

describe("address", () => {
  test("returns single byte 0x40", () => {
    expect(address()).toEqual(new Uint8Array([TypeCode.ADDRESS]));
  });
});

describe("bool", () => {
  test("returns single byte 0x41", () => {
    expect(bool()).toEqual(new Uint8Array([TypeCode.BOOL]));
  });
});

describe("function_", () => {
  test("returns single byte 0x42", () => {
    expect(function_()).toEqual(new Uint8Array([TypeCode.FUNCTION]));
  });
});

describe("uint256", () => {
  test("returns single byte 0x1f", () => {
    expect(uint256()).toEqual(new Uint8Array([TypeCode.UINT_MAX]));
  });
});

describe("int256", () => {
  test("returns single byte 0x3f", () => {
    expect(int256()).toEqual(new Uint8Array([TypeCode.INT_MAX]));
  });
});

describe("bytes", () => {
  test("returns single byte 0x70", () => {
    expect(bytes()).toEqual(new Uint8Array([TypeCode.BYTES]));
  });
});

describe("string_", () => {
  test("returns single byte 0x71", () => {
    expect(string_()).toEqual(new Uint8Array([TypeCode.STRING]));
  });
});

///////////////////////////////////////////////////////////////////////////
// uintN ranges
///////////////////////////////////////////////////////////////////////////

describe("uintN", () => {
  test("uint8 → 0x00", () => {
    expect(uintN(8)).toEqual(new Uint8Array([TypeCode.UINT_MIN]));
  });

  test("uint16 → 0x01", () => {
    expect(uintN(16)).toEqual(new Uint8Array([0x01]));
  });

  test("uint128 → 0x0f", () => {
    expect(uintN(128)).toEqual(new Uint8Array([0x0f]));
  });

  test("uint256 → 0x1f", () => {
    expect(uintN(256)).toEqual(new Uint8Array([TypeCode.UINT_MAX]));
  });

  test("rejects bits not multiple of 8", () => {
    expectErrorCode(() => uintN(7), "INVALID_TYPE_STRING");
  });

  test("rejects bits below 8", () => {
    expectErrorCode(() => uintN(0), "INVALID_TYPE_STRING");
  });

  test("rejects bits above 256", () => {
    expectErrorCode(() => uintN(264), "INVALID_TYPE_STRING");
  });
});

///////////////////////////////////////////////////////////////////////////
// intN ranges
///////////////////////////////////////////////////////////////////////////

describe("intN", () => {
  test("int8 → 0x20", () => {
    expect(intN(8)).toEqual(new Uint8Array([TypeCode.INT_MIN]));
  });

  test("int16 → 0x21", () => {
    expect(intN(16)).toEqual(new Uint8Array([0x21]));
  });

  test("int128 → 0x2f", () => {
    expect(intN(128)).toEqual(new Uint8Array([0x2f]));
  });

  test("int256 → 0x3f", () => {
    expect(intN(256)).toEqual(new Uint8Array([TypeCode.INT_MAX]));
  });

  test("rejects bits not multiple of 8", () => {
    expectErrorCode(() => intN(9), "INVALID_TYPE_STRING");
  });

  test("rejects bits above 256", () => {
    expectErrorCode(() => intN(512), "INVALID_TYPE_STRING");
  });
});

///////////////////////////////////////////////////////////////////////////
// bytesN ranges
///////////////////////////////////////////////////////////////////////////

describe("bytesN", () => {
  test("bytes1 → 0x50", () => {
    expect(bytesN(1)).toEqual(new Uint8Array([TypeCode.FIXED_BYTES_MIN]));
  });

  test("bytes16 → 0x5f", () => {
    expect(bytesN(16)).toEqual(new Uint8Array([0x5f]));
  });

  test("bytes32 → 0x6f", () => {
    expect(bytesN(32)).toEqual(new Uint8Array([TypeCode.FIXED_BYTES_MAX]));
  });

  test("rejects n=0", () => {
    expectErrorCode(() => bytesN(0), "INVALID_TYPE_STRING");
  });

  test("rejects n=33", () => {
    expectErrorCode(() => bytesN(33), "INVALID_TYPE_STRING");
  });
});

describe("bytes32", () => {
  test("shorthand for bytesN(32)", () => {
    expect(bytes32()).toEqual(bytesN(32));
  });
});

///////////////////////////////////////////////////////////////////////////
// enum_ alias
///////////////////////////////////////////////////////////////////////////

describe("enum_", () => {
  test("defaults to uint8", () => {
    expect(enum_()).toEqual(uintN(8));
  });

  test("accepts explicit bits", () => {
    expect(enum_(16)).toEqual(uintN(16));
  });
});

///////////////////////////////////////////////////////////////////////////
// Dynamic array
///////////////////////////////////////////////////////////////////////////

describe("array (dynamic)", () => {
  test("wraps uint256 in dynamic array", () => {
    const elem = uint256();
    const result = array(elem);
    // [0x81][meta:3][elemDesc]
    expect(result[0]).toBe(TypeCode.DYNAMIC_ARRAY);
    // nodeLength = ARRAY_HEADER_SIZE + elemDesc.length = 4 + 1 = 5
    // staticWords = 0 (always dynamic)
    // meta = (0 << 12) | 5 = 0x000005 encoded as 3 bytes big-endian
    expect(result[1]).toBe(0x00);
    expect(result[2]).toBe(0x00);
    expect(result[3]).toBe(0x05);
    expect(result[4]).toBe(0x1f);
    expect(result.length).toBe(5);
  });

  test("dynamic array of bytes has correct meta", () => {
    const elem = bytes();
    const result = array(elem);
    expect(result[0]).toBe(TypeCode.DYNAMIC_ARRAY);
    // nodeLength = 4 + 1 = 5, staticWords = 0
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const nodeLength = meta24 & DF.META_NODE_LENGTH_MASK;
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    expect(nodeLength).toBe(5);
    expect(staticWords).toBe(0);
  });

  test("dynamic array staticWords is always 0", () => {
    const result = array(uint256());
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    expect(staticWords).toBe(0);
  });
});

///////////////////////////////////////////////////////////////////////////
// Static array
///////////////////////////////////////////////////////////////////////////

describe("array (static)", () => {
  test("uint256[4] has correct staticWords and length suffix", () => {
    const elem = uint256();
    const result = array(elem, 4);
    // [0x80][meta:3][elemDesc][length:be16]
    expect(result[0]).toBe(TypeCode.STATIC_ARRAY);
    // nodeLength = ARRAY_HEADER_SIZE + elemDesc.length + ARRAY_LENGTH_SIZE = 4 + 1 + 2 = 7
    // elemStaticWords = 1 (uint256 is elementary static)
    // staticWords = 4 * 1 = 4
    // meta = (4 << 12) | 7 = 0x004007
    expect(result[1]).toBe(0x00);
    expect(result[2]).toBe(0x40);
    expect(result[3]).toBe(0x07);
    // elem byte
    expect(result[4]).toBe(0x1f);
    // length suffix as be16
    expect(result[5]).toBe(0x00);
    expect(result[6]).toBe(0x04);
    expect(result.length).toBe(7);
  });

  test("static array of dynamic type has staticWords=0", () => {
    const elem = bytes();
    const result = array(elem, 5);
    expect(result[0]).toBe(TypeCode.STATIC_ARRAY);
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    expect(staticWords).toBe(0);
  });

  test("rejects length 0", () => {
    expectErrorCode(() => array(uint256(), 0), "INVALID_ARRAY_LENGTH");
  });

  test("rejects length > MAX_STATIC_ARRAY_LENGTH", () => {
    expectErrorCode(() => array(uint256(), DF.MAX_STATIC_ARRAY_LENGTH + 1), "INVALID_ARRAY_LENGTH");
  });
});

///////////////////////////////////////////////////////////////////////////
// Tuple
///////////////////////////////////////////////////////////////////////////

describe("tuple", () => {
  test("single-field tuple has correct fieldCount and staticWords", () => {
    const fields = [uint256()];
    const result = tuple(fields);
    // [0x90][meta:3][fieldCount:be16][field0]
    expect(result[0]).toBe(TypeCode.TUPLE);
    // nodeLength = TUPLE_HEADER_SIZE + 1 = 6 + 1 = 7
    // staticWords = 1
    // meta = (1 << 12) | 7 = 0x001007
    expect(result[1]).toBe(0x00);
    expect(result[2]).toBe(0x10);
    expect(result[3]).toBe(0x07);
    // fieldCount be16
    expect(result[4]).toBe(0x00);
    expect(result[5]).toBe(0x01);
    // field byte
    expect(result[6]).toBe(0x1f);
    expect(result.length).toBe(7);
  });

  test("two-field tuple sums staticWords", () => {
    const fields = [uint256(), address()];
    const result = tuple(fields);
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    expect(staticWords).toBe(2);
    const fieldCount = (result[4] << 8) | result[5];
    expect(fieldCount).toBe(2);
  });

  test("tuple with dynamic field has staticWords=0", () => {
    const fields = [uint256(), bytes()];
    const result = tuple(fields);
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    expect(staticWords).toBe(0);
  });

  test("rejects empty fields array", () => {
    expectErrorCode(() => tuple([]), "INVALID_TUPLE_FIELD_COUNT");
  });

  test("rejects fields.length > MAX_TUPLE_FIELDS", () => {
    const fields = Array.from({ length: DF.MAX_TUPLE_FIELDS + 1 }, () => uint256());
    expectErrorCode(() => tuple(fields), "INVALID_TUPLE_FIELD_COUNT");
  });
});

///////////////////////////////////////////////////////////////////////////
// Static words overflow
///////////////////////////////////////////////////////////////////////////

describe("static words overflow", () => {
  test("static array rejects staticWords > 4095", () => {
    // tuple(uint256, uint256) has staticWords=2. Array of 2048 → 4096 words, overflow.
    const pairDesc = tuple([uint256(), uint256()]);
    expectErrorCode(() => array(pairDesc, 2048), "DESCRIPTOR_TOO_LARGE");
  });

  test("static array at boundary 4095 succeeds", () => {
    // uint256[4095] → staticWords = 4095, exactly at 12-bit max.
    const result = array(uint256(), 4095);
    expect(result[0]).toBe(TypeCode.STATIC_ARRAY);
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    expect(staticWords).toBe(4095);
  });

  test("tuple rejects staticWords > 4095 via nested static arrays", () => {
    // Two uint256[2048] arrays → 2 * 2048 = 4096 words, overflow.
    const bigArray = array(uint256(), 2048);
    expectErrorCode(() => tuple([bigArray, bigArray]), "DESCRIPTOR_TOO_LARGE");
  });

  test("tuple with dynamic field skips staticWords check", () => {
    // Even with large static fields, a dynamic field makes staticWords = 0.
    const bigArray = array(uint256(), 2048);
    const result = tuple([bigArray, bigArray, bytes()]);
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    expect(staticWords).toBe(0);
  });
});

///////////////////////////////////////////////////////////////////////////
// Node length overflow
///////////////////////////////////////////////////////////////////////////

describe("node length overflow", () => {
  test("dynamic array rejects nodeLength > MAX_NODE_LENGTH", () => {
    // A tuple with MAX_TUPLE_FIELDS elementary fields produces a descriptor of
    // TUPLE_HEADER_SIZE + MAX_TUPLE_FIELDS = 6 + 4089 = 4095 bytes.
    // Wrapping it in a dynamic array gives nodeLength = ARRAY_HEADER_SIZE + 4095 = 4099.
    const bigTuple = tuple(Array.from({ length: DF.MAX_TUPLE_FIELDS }, () => uint256()));
    expect(bigTuple.length).toBe(DF.MAX_NODE_LENGTH);
    expectErrorCode(() => array(bigTuple), "DESCRIPTOR_TOO_LARGE");
  });

  test("static array rejects nodeLength > MAX_NODE_LENGTH", () => {
    // Same big tuple as element, but in a static array: nodeLength =
    // ARRAY_HEADER_SIZE + 4095 + ARRAY_LENGTH_SIZE = 4 + 4095 + 2 = 4101.
    // The length=1 passes the MAX_STATIC_ARRAY_LENGTH check but nodeLength overflows.
    const bigTuple = tuple(Array.from({ length: DF.MAX_TUPLE_FIELDS }, () => uint256()));
    expectErrorCode(() => array(bigTuple, 1), "DESCRIPTOR_TOO_LARGE");
  });

  test("tuple rejects nodeLength > MAX_NODE_LENGTH via large fields", () => {
    // Two tuples of ~2045 elementary fields each produce ~2051-byte descriptors.
    // Outer tuple totalFieldBytes = 2 * 2051 = 4102, nodeLength = 6 + 4102 = 4108.
    const halfTuple = tuple(Array.from({ length: 2045 }, () => uint256()));
    expect(halfTuple.length).toBe(DF.TUPLE_HEADER_SIZE + 2045);
    expectErrorCode(() => tuple([halfTuple, halfTuple]), "INVALID_TUPLE_FIELD_COUNT");
  });
});

///////////////////////////////////////////////////////////////////////////
// struct alias
///////////////////////////////////////////////////////////////////////////

describe("struct", () => {
  test("delegates to tuple", () => {
    const fields = [uint256(), address()];
    expect(struct(fields)).toEqual(tuple(fields));
  });
});

///////////////////////////////////////////////////////////////////////////
// Nested composites
///////////////////////////////////////////////////////////////////////////

describe("nested composites", () => {
  test("dynamic array of tuples", () => {
    const fields = [uint256(), address()];
    const tupleDesc = tuple(fields);
    const result = array(tupleDesc);
    expect(result[0]).toBe(TypeCode.DYNAMIC_ARRAY);
    // nodeLength = ARRAY_HEADER_SIZE + tupleDesc.length
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const nodeLength = meta24 & DF.META_NODE_LENGTH_MASK;
    expect(nodeLength).toBe(DF.ARRAY_HEADER_SIZE + tupleDesc.length);
    // dynamicArray staticWords always 0
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    expect(staticWords).toBe(0);
    // elem bytes follow
    expect(result.slice(4)).toEqual(tupleDesc);
  });

  test("static array of tuples propagates elemStaticWords", () => {
    // tuple of (uint256, address) → staticWords=2
    const fields = [uint256(), address()];
    const tupleDesc = tuple(fields);
    const result = array(tupleDesc, 3);
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    // 3 * 2 = 6
    expect(staticWords).toBe(6);
  });

  test("tuple containing a static array", () => {
    // uint256[3] → staticWords=3
    const arrDesc = array(uint256(), 3);
    const result = tuple([arrDesc, bool()]);
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    // 3 + 1 = 4
    expect(staticWords).toBe(4);
  });
});

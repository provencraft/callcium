import { describe, expect, test } from "vitest";

import { TypeCode, DescriptorFormat as DF } from "../src/constants";
import { uintN, intN, string_, bytesN, array, tuple } from "../src/type-desc";
import { expectErrorCode } from "./helpers";

///////////////////////////////////////////////////////////////////////////
// Sized types
///////////////////////////////////////////////////////////////////////////

describe("uintN", () => {
  test("uint16 → 0x02", () => {
    expect(uintN(16)).toEqual(new Uint8Array([0x02]));
  });

  test("rejects bits not multiple of 8", () => {
    expectErrorCode(() => uintN(9), "INVALID_UINT_BITS");
  });

  test("rejects bits below 8", () => {
    expectErrorCode(() => uintN(0), "INVALID_UINT_BITS");
  });

  test("rejects bits above 256", () => {
    expectErrorCode(() => uintN(264), "INVALID_UINT_BITS");
  });
});

describe("intN", () => {
  test("int16 → 0x22", () => {
    expect(intN(16)).toEqual(new Uint8Array([0x22]));
  });

  test("rejects bits not multiple of 8", () => {
    expectErrorCode(() => intN(9), "INVALID_INT_BITS");
  });

  test("rejects bits above 256", () => {
    expectErrorCode(() => intN(512), "INVALID_INT_BITS");
  });
});

describe("bytesN", () => {
  test("bytes16 → 0x5f", () => {
    expect(bytesN(16)).toEqual(new Uint8Array([0x5f]));
  });

  test("rejects n=0", () => {
    expectErrorCode(() => bytesN(0), "INVALID_BYTES_LENGTH");
  });

  test("rejects n=33", () => {
    expectErrorCode(() => bytesN(33), "INVALID_BYTES_LENGTH");
  });
});

///////////////////////////////////////////////////////////////////////////
// Composites
///////////////////////////////////////////////////////////////////////////

describe("array", () => {
  test("wraps an element in a dynamic array with zero static words", () => {
    expect(array(uintN(256))).toEqual(
      Uint8Array.of(TypeCode.DYNAMIC_ARRAY, 0x00, 0x00, DF.ARRAY_HEADER_SIZE + 1, TypeCode.UINT_MAX),
    );
  });

  test("rejects length 0", () => {
    expectErrorCode(() => array(uintN(256), 0), "INVALID_ARRAY_LENGTH");
  });

  test("rejects length > MAX_STATIC_ARRAY_LENGTH", () => {
    expectErrorCode(() => array(uintN(256), DF.MAX_STATIC_ARRAY_LENGTH + 1), "INVALID_ARRAY_LENGTH");
  });
});

describe("tuple", () => {
  test("rejects empty fields array", () => {
    expectErrorCode(() => tuple([]), "INVALID_TUPLE_FIELD_COUNT");
  });

  test("rejects fields.length > MAX_TUPLE_FIELDS", () => {
    const fields = Array.from({ length: DF.MAX_TUPLE_FIELDS + 1 }, () => uintN(256));
    expectErrorCode(() => tuple(fields), "INVALID_TUPLE_FIELD_COUNT");
  });
});

///////////////////////////////////////////////////////////////////////////
// Static words overflow
///////////////////////////////////////////////////////////////////////////

describe("static words overflow", () => {
  /** Half of one past MAX_STATIC_WORDS: twice this many words pass the limit. */
  const halfPastLimit = (DF.MAX_STATIC_WORDS + 1) / 2;

  test("static array rejects staticWords > MAX_STATIC_WORDS", () => {
    const pairDesc = tuple([uintN(256), uintN(256)]);
    expectErrorCode(() => array(pairDesc, halfPastLimit), "STATIC_WORDS_TOO_LARGE");
  });

  test("static array at MAX_STATIC_WORDS succeeds", () => {
    const result = array(uintN(256), DF.MAX_STATIC_WORDS);
    expect(result[0]).toBe(TypeCode.STATIC_ARRAY);
    const meta24 = (result[1] << 16) | (result[2] << 8) | result[3];
    const staticWords = meta24 >> DF.META_STATIC_WORDS_SHIFT;
    expect(staticWords).toBe(DF.MAX_STATIC_WORDS);
  });

  test("tuple rejects staticWords > MAX_STATIC_WORDS via nested static arrays", () => {
    const bigArray = array(uintN(256), halfPastLimit);
    expectErrorCode(() => tuple([bigArray, bigArray]), "STATIC_WORDS_TOO_LARGE");
  });

  test("tuple with dynamic field skips staticWords check", () => {
    const bigArray = array(uintN(256), halfPastLimit);
    const result = tuple([bigArray, bigArray, string_()]);
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
    // A tuple of MAX_TUPLE_FIELDS elementary fields fills MAX_NODE_LENGTH; an array header around it exceeds it.
    const bigTuple = tuple(Array.from({ length: DF.MAX_TUPLE_FIELDS }, () => uintN(256)));
    expect(bigTuple.length).toBe(DF.MAX_NODE_LENGTH);
    expectErrorCode(() => array(bigTuple), "NODE_LENGTH_TOO_LARGE");
  });

  test("static array rejects nodeLength > MAX_NODE_LENGTH", () => {
    // The same tuple in a static array of length 1: the length passes MAX_STATIC_ARRAY_LENGTH, the node does not fit.
    const bigTuple = tuple(Array.from({ length: DF.MAX_TUPLE_FIELDS }, () => uintN(256)));
    expectErrorCode(() => array(bigTuple, 1), "NODE_LENGTH_TOO_LARGE");
  });

  test("tuple rejects nodeLength > MAX_NODE_LENGTH via large fields", () => {
    // Two tuples of 2045 fields fill more than MAX_NODE_LENGTH once a tuple header wraps them.
    const halfTuple = tuple(Array.from({ length: 2045 }, () => uintN(256)));
    expect(halfTuple.length).toBe(DF.TUPLE_HEADER_SIZE + 2045);
    expectErrorCode(() => tuple([halfTuple, halfTuple]), "NODE_LENGTH_TOO_LARGE");
  });
});

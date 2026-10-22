import { describe, expect, test } from "vitest";

import rawVectors from "../../../spec/vectors/descriptors.json";
import { bytesToHex, hexToBytes } from "../src/bytes";
import { DescriptorFormat as DF, TypeCode } from "../src/constants";
import { DescriptorCoder } from "../src/descriptor-coder";
import { expectErrorCode, hex } from "./helpers";

describe("DescriptorCoder.fromTypes", () => {
  test("encodes each type to its node bytes", () => {
    expect(DescriptorCoder.fromTypes("uint8,uint16,int8,bytes1,uint256[3],string,function")).toEqual(
      hexToBytes("0x020701022150800030072000037143"),
    );
  });

  test("uint width off the 8-bit grid throws UNKNOWN_TYPE", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("uint7"), "UNKNOWN_TYPE");
  });

  test("int width off the 8-bit grid throws UNKNOWN_TYPE", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("int7"), "UNKNOWN_TYPE");
  });

  test("bytes size past 32 throws UNKNOWN_TYPE", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("bytes33"), "UNKNOWN_TYPE");
  });

  test("bare width prefix throws UNKNOWN_TYPE", () => {
    // A prefix carrying no width names no type; it is not a width spelled wrongly.
    expectErrorCode(() => DescriptorCoder.fromTypes("uint"), "UNKNOWN_TYPE");
  });

  test("unknown base under an array suffix throws UNKNOWN_TYPE", () => {
    // The base is read before the suffix length, so the unknown base is what gets reported.
    expectErrorCode(() => DescriptorCoder.fromTypes("foo[x]"), "UNKNOWN_TYPE");
  });

  test("a closer with nothing open throws MALFORMED_TYPE_STRING, not an unknown type", () => {
    // A stray closer is malformed, not read into the next segment.
    expectErrorCode(() => DescriptorCoder.fromTypes("uint256[],]uint8"), "MALFORMED_TYPE_STRING");
  });

  test("trailing comma 'uint256,' throws MALFORMED_TYPE_STRING", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("uint256,"), "MALFORMED_TYPE_STRING");
  });

  test("empty tuple '()' throws INVALID_TUPLE_FIELD_COUNT", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("()"), "INVALID_TUPLE_FIELD_COUNT");
  });

  test("unclosed array bracket 'uint256[' throws MALFORMED_TYPE_STRING", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("uint256["), "MALFORMED_TYPE_STRING");
  });

  test("non-numeric array length 'uint256[abc]' throws MALFORMED_TYPE_STRING", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("uint256[abc]"), "MALFORMED_TYPE_STRING");
  });

  test("array length of 2**256 + 1 is rejected, never a valid small length", () => {
    expectErrorCode(
      () =>
        DescriptorCoder.fromTypes(
          "uint256[115792089237316195423570985008687907853269984665640564039457584007913129639937]",
        ),
      "MALFORMED_TYPE_STRING",
    );
  });

  test("zero-padded array length 'uint256[03]' throws MALFORMED_TYPE_STRING", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("uint256[03]"), "MALFORMED_TYPE_STRING");
  });

  test("characters after a tuple's closing paren throw MALFORMED_TYPE_STRING", () => {
    expectErrorCode(() => DescriptorCoder.fromTypes("(bool)garbage"), "MALFORMED_TYPE_STRING");
  });

  test("rejects array nesting beyond the maximum depth", () => {
    const types = `uint256${"[]".repeat(DF.MAX_NESTING_DEPTH + 1)}`;
    expectErrorCode(() => DescriptorCoder.fromTypes(types), "NESTING_TOO_DEEP");
  });
});

describe("DescriptorCoder.inspect", () => {
  test("returns each parameter as a node tree with the bytes every node spans", () => {
    const desc = DescriptorCoder.fromTypes("(uint8,bytes)[2],uint256[]");
    expect(DescriptorCoder.inspect(desc)).toEqual({
      version: { value: DF.VERSION, span: { start: 0, end: 1 } },
      paramCount: { value: 2, span: { start: 1, end: 2 } },
      params: [
        {
          typeClass: "staticArray",
          typeCode: TypeCode.STATIC_ARRAY,
          isDynamic: true,
          staticSize: 0,
          span: { start: 2, end: 16 },
          length: 2,
          element: {
            typeClass: "tuple",
            typeCode: TypeCode.TUPLE,
            isDynamic: true,
            staticSize: 0,
            span: { start: 6, end: 14 },
            fields: [
              {
                typeClass: "elementary",
                typeCode: TypeCode.UINT_MIN,
                isDynamic: false,
                staticSize: 32,
                span: { start: 12, end: 13 },
              },
              {
                typeClass: "elementary",
                typeCode: TypeCode.BYTES,
                isDynamic: true,
                staticSize: 0,
                span: { start: 13, end: 14 },
              },
            ],
          },
        },
        {
          typeClass: "dynamicArray",
          typeCode: TypeCode.DYNAMIC_ARRAY,
          isDynamic: true,
          staticSize: 0,
          span: { start: 16, end: 21 },
          element: {
            typeClass: "elementary",
            typeCode: TypeCode.UINT_MAX,
            isDynamic: false,
            staticSize: 32,
            span: { start: 20, end: 21 },
          },
        },
      ],
      span: { start: 0, end: 21 },
    });
  });
});

describe("DescriptorCoder.toTypes", () => {
  test("reads back every descriptor vector it accepts", () => {
    const accepted = rawVectors.filter((vector) => vector.error === "");
    expect(accepted.length).toBeGreaterThan(0);
    for (const vector of accepted) {
      const desc = hexToBytes(hex(vector.blob));
      expect(bytesToHex(DescriptorCoder.fromTypes(DescriptorCoder.toTypes(desc)))).toBe(vector.blob);
    }
  });

  test("refuses a composite whose declared static words disagree with its children", () => {
    // Tuple of (uint256,bytes) declaring staticWords 2.
    const desc = hexToBytes("0x02019000200800022070");
    expectErrorCode(() => DescriptorCoder.toTypes(desc), "STATIC_WORDS_MISMATCH");
  });
});

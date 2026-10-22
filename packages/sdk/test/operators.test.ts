import { describe, expect, test } from "vitest";

import { DescriptorFormat as DF, fieldMax, TypeCode } from "../src/constants";
import {
  canonicalize,
  hasCalldataLength,
  isLeftAligned,
  isSigned,
  lookupTypeCode,
  operandWidth,
} from "../src/operators";
import { expectErrorCode } from "./helpers";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** The type codes from `first` to `last`. */
function codeRange(first: number, last: number): number[] {
  return Array.from({ length: last - first + 1 }, (_, index) => first + index);
}

const elementaryCodes = [
  ...codeRange(TypeCode.UINT_MIN, TypeCode.UINT_MAX),
  ...codeRange(TypeCode.INT_MIN, TypeCode.INT_MAX),
  TypeCode.ADDRESS,
  TypeCode.BOOL,
  TypeCode.FUNCTION,
  ...codeRange(TypeCode.FIXED_BYTES_MIN, TypeCode.FIXED_BYTES_MAX),
];

const definedCodes = [
  ...elementaryCodes,
  TypeCode.BYTES,
  TypeCode.STRING,
  TypeCode.STATIC_ARRAY,
  TypeCode.DYNAMIC_ARRAY,
  TypeCode.TUPLE,
];

/** Byte widths of the static elementary types whose label carries no size. */
const unsizedWidths: Record<string, number> = { address: 20, bool: 1, function: 24 };

/** The byte width a static elementary type's label states. */
function labelWidth(label: string): number | undefined {
  const integer = /^u?int(\d+)$/.exec(label);
  if (integer) return Number(integer[1]) / 8;
  const fixedBytes = /^bytes(\d+)$/.exec(label);
  if (fixedBytes) return Number(fixedBytes[1]);
  return unsizedWidths[label];
}

/** Whether `word` encodes a value of the type, stated as a value range. */
function isEncoding(word: bigint, typeCode: number): boolean {
  if (typeCode <= TypeCode.UINT_MAX) return word < 1n << BigInt(8 * (typeCode - TypeCode.UINT_MIN + 1));
  if (typeCode <= TypeCode.INT_MAX) {
    const bits = BigInt(8 * (typeCode - TypeCode.INT_MIN + 1));
    const signed = BigInt.asIntN(256, word);
    return signed >= -(1n << (bits - 1n)) && signed < 1n << (bits - 1n);
  }
  if (typeCode === TypeCode.ADDRESS) return word < 1n << 160n;
  if (typeCode === TypeCode.BOOL) return word <= 1n;
  const width = typeCode === TypeCode.FUNCTION ? 24 : typeCode - TypeCode.FIXED_BYTES_MIN + 1;
  return word % (1n << BigInt(256 - 8 * width)) === 0n;
}

// The lowest and highest bit of every byte, so each width's top and sign bits, plus 2 and every bit set.
const edgeWords = [
  0n,
  2n,
  (1n << 256n) - 1n,
  ...codeRange(0, 31).flatMap((byte) => [1n << BigInt(8 * byte), 1n << BigInt(8 * byte + 7)]),
];

///////////////////////////////////////////////////////////////////////////
// canonicalize
///////////////////////////////////////////////////////////////////////////

describe("canonicalize", () => {
  test("leaves exactly the encodings of every elementary type unchanged", () => {
    for (const typeCode of elementaryCodes) {
      for (const word of edgeWords) {
        expect(canonicalize(word, typeCode) === word, `type ${typeCode}, word ${word}`).toBe(
          isEncoding(word, typeCode),
        );
      }
    }
  });
});

///////////////////////////////////////////////////////////////////////////
// lookupTypeCode
///////////////////////////////////////////////////////////////////////////

describe("lookupTypeCode", () => {
  test.each([
    [TypeCode.UINT_MIN, "uint8", "elementary", false],
    [TypeCode.UINT_MAX, "uint256", "elementary", false],
    [TypeCode.INT_MIN, "int8", "elementary", false],
    [TypeCode.INT_MAX, "int256", "elementary", false],
    [TypeCode.ADDRESS, "address", "elementary", false],
    [TypeCode.BOOL, "bool", "elementary", false],
    [TypeCode.FUNCTION, "function", "elementary", false],
    [TypeCode.FIXED_BYTES_MIN, "bytes1", "elementary", false],
    [TypeCode.FIXED_BYTES_MAX, "bytes32", "elementary", false],
    [TypeCode.BYTES, "bytes", "elementary", true],
    [TypeCode.STRING, "string", "elementary", true],
    [TypeCode.STATIC_ARRAY, "T[k]", "staticArray", false],
    [TypeCode.DYNAMIC_ARRAY, "T[]", "dynamicArray", true],
    [TypeCode.TUPLE, "tuple", "tuple", false],
  ])("labels type code %d as %s", (code, label, typeClass, isDynamic) => {
    expect(lookupTypeCode(code)).toEqual({ label, typeClass, isDynamic });
  });

  test("every type code function agrees with the defined codes on every byte", () => {
    for (const code of codeRange(0, fieldMax(DF.TYPECODE_SIZE))) {
      const isDefined = definedCodes.includes(code);
      if (!isDefined) expectErrorCode(() => lookupTypeCode(code), "UNKNOWN_TYPE_CODE");
      const info = isDefined ? lookupTypeCode(code) : undefined;
      const label = info?.label ?? "";
      const isStaticElementary = info?.typeClass === "elementary" && !info.isDynamic;
      expect(operandWidth(code), `type ${code}`).toBe(isStaticElementary ? labelWidth(label) : undefined);
      expect(isSigned(code), `type ${code}`).toBe(/^int\d+$/.test(label));
      expect(isLeftAligned(code), `type ${code}`).toBe(label === "function" || /^bytes\d+$/.test(label));
      expect(hasCalldataLength(code), `type ${code}`).toBe(info?.isDynamic === true);
    }
  });
});

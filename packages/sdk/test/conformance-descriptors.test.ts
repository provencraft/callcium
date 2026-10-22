import { describe, expect, test } from "vitest";

import rawVectors from "../../../spec/vectors/descriptors.json";
import { hexToBytes } from "../src/bytes";
import { decodeDescriptor } from "../src/descriptor-coder";
import { expectErrorCode, hex } from "./helpers";

import type { CallciumErrorCode } from "../src/errors";

///////////////////////////////////////////////////////////////////////////
// Vector types
///////////////////////////////////////////////////////////////////////////

type VectorParam = {
  typeCode: number;
  isDynamic: boolean;
  staticSize: number;
};

type Vector = {
  id: string;
  blob: string;
  description: string;
  version: number;
  params: VectorParam[];
  error: string;
  errorArgs: string[];
};

const vectors: Vector[] = rawVectors;

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** Vector error names are the canonical invariant names; SDK codes are their SCREAMING_SNAKE form. */
const errorMap: Record<string, CallciumErrorCode> = {
  MalformedHeader: "MALFORMED_HEADER",
  UnsupportedVersion: "UNSUPPORTED_VERSION",
  UnexpectedEnd: "UNEXPECTED_END",
  ParamCountMismatch: "PARAM_COUNT_MISMATCH",
  NestingTooDeep: "NESTING_TOO_DEEP",
  NodeLengthTooSmall: "NODE_LENGTH_TOO_SMALL",
  NodeOverflow: "NODE_OVERFLOW",
  UnknownTypeCode: "UNKNOWN_TYPE_CODE",
  InvalidTupleFieldCount: "INVALID_TUPLE_FIELD_COUNT",
  InvalidArrayLength: "INVALID_ARRAY_LENGTH",
  TooManyParams: "TOO_MANY_PARAMS",
};

///////////////////////////////////////////////////////////////////////////
// Descriptor verdicts
///////////////////////////////////////////////////////////////////////////

describe("Descriptor conformance vectors - decodeDescriptor", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      const blob = hexToBytes(hex(vector.blob));
      if (vector.error === "") {
        const result = decodeDescriptor(blob);
        expect(result.version.value).toBe(vector.version);
        expect(result.params).toHaveLength(vector.params.length);

        for (let i = 0; i < vector.params.length; i++) {
          const expected = vector.params[i];
          const actual = result.params[i];
          expect(actual.typeCode).toBe(expected.typeCode);
          expect(actual.isDynamic).toBe(expected.isDynamic);
          expect(actual.staticSize).toBe(expected.staticSize);
        }
      } else {
        const expectedCode = errorMap[vector.error];
        expect(expectedCode).toBeDefined();

        expectErrorCode(() => decodeDescriptor(blob), expectedCode);
      }
    });
  }
});

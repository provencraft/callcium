import { describe, expect, test } from "vitest";

import rawVectors from "../../contracts/test/vectors/descriptors.json";
import { decodeDescriptor } from "../src";
import { expectErrorCode, hex } from "./helpers";

import type { CallciumErrorCode } from "../src";

// Map conformance vector error names to SDK error codes.
const ERROR_MAP: Record<string, CallciumErrorCode> = {
  MalformedHeader: "MALFORMED_HEADER",
  UnsupportedVersion: "UNSUPPORTED_VERSION",
  UnexpectedEnd: "UNEXPECTED_END",
  ParamCountMismatch: "PARAM_COUNT_MISMATCH",
  NodeLengthTooSmall: "MALFORMED_HEADER",
  NodeOverflow: "NODE_OVERFLOW",
  UnknownTypeCode: "UNKNOWN_TYPE_CODE",
  InvalidTupleFieldCount: "INVALID_TUPLE_FIELD_COUNT",
  InvalidArrayLength: "INVALID_ARRAY_LENGTH",
  TooManyParams: "PARAM_COUNT_MISMATCH",
  ArrayLengthTooLarge: "INVALID_ARRAY_LENGTH",
  TupleFieldCountTooLarge: "INVALID_TUPLE_FIELD_COUNT",
};

type VectorParam = {
  index: number;
  typeCode: number;
  isDynamic: boolean;
  staticSize: number;
  path: string;
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

const vectors = rawVectors as Vector[];

describe("descriptor conformance vectors", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      if (vector.error === "") {
        // Valid vector — decode and verify all param fields.
        const result = decodeDescriptor(hex(vector.blob));
        expect(result.version).toBe(vector.version);
        expect(result.params).toHaveLength(vector.params.length);

        for (let i = 0; i < vector.params.length; i++) {
          const expected = vector.params[i];
          const actual = result.params[i];
          expect(actual.index).toBe(expected.index);
          expect(actual.typeCode).toBe(expected.typeCode);
          expect(actual.isDynamic).toBe(expected.isDynamic);
          expect(actual.staticSize).toBe(expected.staticSize);
          expect(actual.path).toBe(expected.path);
        }
      } else {
        // Error vector — expect CallciumError with mapped code.
        const expectedCode = ERROR_MAP[vector.error];
        expect(expectedCode).toBeDefined();

        expectErrorCode(() => decodeDescriptor(hex(vector.blob)), expectedCode);
      }
    });
  }
});

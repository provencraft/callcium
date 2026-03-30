import { describe, expect, test } from "vitest";

import rawVectors from "../../test/vectors/policies.json";
import { decodePolicy } from "../src";
import { expectErrorCode, hex } from "./helpers";

import type { CallciumErrorCode } from "../src";

// Map conformance vector error names to SDK error codes.
const ERROR_MAP: Record<string, CallciumErrorCode> = {
  MalformedHeader: "MALFORMED_HEADER",
  UnsupportedVersion: "UNSUPPORTED_VERSION",
  UnexpectedEnd: "UNEXPECTED_END",
  EmptyPolicy: "EMPTY_POLICY",
  EmptyGroup: "EMPTY_GROUP",
  EmptyPath: "EMPTY_PATH",
  InvalidContextPath: "INVALID_CONTEXT_PATH",
  InvalidScope: "INVALID_SCOPE",
  RuleSizeMismatch: "RULE_SIZE_MISMATCH",
  GroupSizeMismatch: "GROUP_SIZE_MISMATCH",
  GroupTooSmall: "GROUP_SIZE_MISMATCH",
  GroupOverflow: "GROUP_OVERFLOW",
  RuleTooSmall: "RULE_SIZE_MISMATCH",
  RuleOverflow: "RULE_OVERFLOW",
  UnknownOperator: "INVALID_OPERATOR",
};

type VectorConstraint = {
  path: string;
  scope: number;
  operators: string[];
};

type VectorGroup = {
  constraints: VectorConstraint[];
};

type VectorDecoded = {
  isSelectorless: boolean;
  selector: string;
  descriptor: string;
  groups: VectorGroup[];
};

type Vector = {
  id: string;
  blob: string;
  description: string;
  error: string;
  errorArgs: string[];
  spec?: {
    decoded?: VectorDecoded;
  };
};

const vectors = rawVectors as Vector[];

describe("policy conformance vectors", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      if (vector.error === "") {
        const result = decodePolicy(hex(vector.blob));
        const decoded = vector.spec?.decoded;
        if (decoded !== undefined) {
          expect(result.isSelectorless).toBe(decoded.isSelectorless);
          expect(result.selector.value).toBe(decoded.selector);
          expect(result.descriptor.raw).toBe(decoded.descriptor);
          expect(result.groups).toHaveLength(decoded.groups.length);
        }
      } else {
        const expectedCode = ERROR_MAP[vector.error];
        expect(expectedCode, `No error code mapping for "${vector.error}"`).toBeDefined();

        expectErrorCode(() => decodePolicy(hex(vector.blob)), expectedCode);
      }
    });
  }
});

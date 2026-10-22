import { describe, expect, test } from "vitest";

import rawVectors from "../../../spec/vectors/policies.json";
import { validatePolicy } from "../src/policy-coder";
import { expectErrorCode, hex, reencode } from "./helpers";

import type { CallciumErrorCode } from "../src/errors";

///////////////////////////////////////////////////////////////////////////
// Vector types
///////////////////////////////////////////////////////////////////////////

type Vector = {
  id: string;
  blob: string;
  description: string;
  error: string;
  canonical?: boolean;
};

const vectors: Vector[] = rawVectors;

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** Vector error names and the SDK codes that transliterate them. */
const errorMap: Record<string, CallciumErrorCode> = {
  DataLengthMismatch: "DATA_LENGTH_MISMATCH",
  EmptyGroup: "EMPTY_GROUP",
  EmptyPath: "EMPTY_PATH",
  EmptyPolicy: "EMPTY_POLICY",
  GroupOverflow: "GROUP_OVERFLOW",
  GroupSizeMismatch: "GROUP_SIZE_MISMATCH",
  InvalidContextOperand: "INVALID_CONTEXT_OPERAND",
  InvalidContextPath: "INVALID_CONTEXT_PATH",
  InvalidNestedLoop: "INVALID_NESTED_LOOP",
  MalformedHeader: "MALFORMED_HEADER",
  MalformedHint: "MALFORMED_HINT",
  MinorMismatch: "MINOR_MISMATCH",
  OperatorTargetMismatch: "OPERATOR_TARGET_MISMATCH",
  ParamCountMismatch: "PARAM_COUNT_MISMATCH",
  PathTooDeep: "PATH_TOO_DEEP",
  RuleOverflow: "RULE_OVERFLOW",
  RuleSizeMismatch: "RULE_SIZE_MISMATCH",
  RuleTooSmall: "RULE_TOO_SMALL",
  TrailingBytes: "TRAILING_BYTES",
  UnexpectedEnd: "UNEXPECTED_END",
  UnknownContextProperty: "UNKNOWN_CONTEXT_PROPERTY",
  UnknownOperator: "UNKNOWN_OPERATOR",
  UnknownPathStep: "UNKNOWN_PATH_STEP",
  UnknownQuantifier: "UNKNOWN_QUANTIFIER",
  UnknownScope: "UNKNOWN_SCOPE",
  UnsortedInSet: "UNSORTED_IN_SET",
  UnsupportedVersion: "UNSUPPORTED_VERSION",
};

///////////////////////////////////////////////////////////////////////////
// Storage verdicts
///////////////////////////////////////////////////////////////////////////

describe("Storage conformance vectors - validatePolicy", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      const blob = hex(vector.blob);
      if (vector.error === "") {
        validatePolicy(blob);
        expect(reencode(blob) === blob).toBe(vector.canonical);
        return;
      }
      const code = errorMap[vector.error];
      expect(code, `No error code mapping for "${vector.error}"`).toBeDefined();
      expectErrorCode(() => validatePolicy(blob), code);
    });
  }
});

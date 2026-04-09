import { describe, expect, test } from "vitest";

import rawVectors from "../../contracts/test/vectors/policies.json";
import { PolicyCoder, decodePolicy } from "../src/policy-coder";
import { expectErrorCode, hex } from "./helpers";

import type { CallciumErrorCode, Constraint, PolicyData } from "../src";

///////////////////////////////////////////////////////////////////////////
// Test helpers
///////////////////////////////////////////////////////////////////////////

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

const vectors: Vector[] = rawVectors;
const validVectors = vectors.filter((v) => v.error === "" && v.spec?.decoded !== undefined);

/** Build a PolicyData from a vector's decoded spec. */
function policyDataFromVector(decoded: VectorDecoded): PolicyData {
  const groups: Constraint[][] = decoded.groups.map((g) =>
    g.constraints.map((c) => ({
      scope: c.scope,
      path: hex(c.path),
      operators: c.operators.map((o) => hex(o)),
    })),
  );
  return {
    isSelectorless: decoded.isSelectorless,
    selector: hex(decoded.selector),
    descriptor: hex(decoded.descriptor),
    groups,
  };
}

///////////////////////////////////////////////////////////////////////////
// Decoding
///////////////////////////////////////////////////////////////////////////

describe("policy conformance - decoding", () => {
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

///////////////////////////////////////////////////////////////////////////
// Public API decode (PolicyCoder)
///////////////////////////////////////////////////////////////////////////

describe("policy conformance - PolicyCoder.decode", () => {
  for (const vector of validVectors) {
    test(`${vector.id}: decodes blob to expected structure`, () => {
      const decoded = vector.spec!.decoded!;
      const result = PolicyCoder.decode(hex(vector.blob));

      expect(result.isSelectorless).toBe(decoded.isSelectorless);
      expect(result.selector).toBe(decoded.selector);
      expect(result.descriptor).toBe(decoded.descriptor);
      expect(result.groups).toHaveLength(decoded.groups.length);

      for (let gi = 0; gi < decoded.groups.length; gi++) {
        const expectedConstraints = decoded.groups[gi].constraints;
        const actualConstraints = result.groups[gi];
        expect(actualConstraints).toHaveLength(expectedConstraints.length);

        for (let ci = 0; ci < expectedConstraints.length; ci++) {
          const expected = expectedConstraints[ci];
          const actual = actualConstraints[ci];
          expect(actual.scope).toBe(expected.scope);
          expect(actual.path).toBe(expected.path);
          expect(actual.operators).toEqual(expected.operators);
        }
      }
    });
  }
});

///////////////////////////////////////////////////////////////////////////
// Encoding
///////////////////////////////////////////////////////////////////////////

describe("policy conformance - PolicyCoder.encode", () => {
  for (const vector of validVectors) {
    test(`${vector.id}: encodes to expected blob`, () => {
      const decoded = vector.spec!.decoded!;
      const data = policyDataFromVector(decoded);
      const encoded = PolicyCoder.encode(data);
      expect(encoded).toBe(vector.blob);
    });
  }
});

///////////////////////////////////////////////////////////////////////////
// Round-trip
///////////////////////////////////////////////////////////////////////////

describe("policy conformance - round-trip", () => {
  for (const vector of validVectors) {
    test(`${vector.id}: encode(decode(blob)) === blob`, () => {
      const decoded = PolicyCoder.decode(hex(vector.blob));
      const reEncoded = PolicyCoder.encode(decoded);
      expect(reEncoded).toBe(vector.blob);
    });
  }
});

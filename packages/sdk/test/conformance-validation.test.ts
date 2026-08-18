import { describe, expect, test } from "vitest";

import rawVectors from "../../../spec/vectors/validation.json";
import { PolicyValidator } from "../src/policy-validator";
import { policyDataFromVector } from "./helpers";

import type { VectorPolicy } from "./helpers";

///////////////////////////////////////////////////////////////////////////
// Vector types
///////////////////////////////////////////////////////////////////////////

type VectorIssue = {
  code: string;
  severity: string;
  groupIndex: number;
  constraintIndex: number;
};

type Vector = {
  id: string;
  description: string;
  policy: VectorPolicy;
  issues: VectorIssue[];
  builds: boolean;
};

const vectors: Vector[] = rawVectors;

///////////////////////////////////////////////////////////////////////////
// Test helpers
///////////////////////////////////////////////////////////////////////////

/** Sortable identity of an issue for order-insensitive comparison. */
function issueKey(issue: { code: string; severity: string; groupIndex: number; constraintIndex: number }): string {
  return `${issue.groupIndex}:${issue.constraintIndex}:${issue.code}:${issue.severity}`;
}

///////////////////////////////////////////////////////////////////////////
// Conformance
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator conformance vectors", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      const issues = PolicyValidator.validate(policyDataFromVector(vector.policy));

      const actual = issues.map(issueKey).toSorted();
      const expected = vector.issues.map(issueKey).toSorted();
      expect(actual).toEqual(expected);

      // Strict-gate invariant: a policy builds if and only if validation is clean.
      expect(vector.builds).toBe(issues.length === 0);
    });
  }
});

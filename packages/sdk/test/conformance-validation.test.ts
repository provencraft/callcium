import { describe, expect, test } from "vitest";

import rawVectors from "../../contracts/test/vectors/validation.json";
import { PolicyValidator } from "../src/policy-validator";
import { hex } from "./helpers";

import type { Constraint, PolicyData } from "../src";

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
  policy: {
    isSelectorless: boolean;
    selector: string;
    descriptor: string;
    groups: { constraints: { scope: number; path: string; operators: string[] }[] }[];
  };
  issues: VectorIssue[];
  builds: boolean;
};

const vectors: Vector[] = rawVectors;

///////////////////////////////////////////////////////////////////////////
// Test helpers
///////////////////////////////////////////////////////////////////////////

/** Build a PolicyData from a vector's policy spec. */
function policyDataFromVector(policy: Vector["policy"]): PolicyData {
  const groups: Constraint[][] = policy.groups.map((g) =>
    g.constraints.map((c) => ({
      scope: c.scope,
      path: hex(c.path),
      operators: c.operators.map((o) => hex(o)),
    })),
  );
  return {
    isSelectorless: policy.isSelectorless,
    selector: hex(policy.selector),
    descriptor: hex(policy.descriptor),
    groups,
  };
}

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

import { describe, expect, test } from "vitest";

import rawVectors from "../../../spec/vectors/validation.json";
import { PolicyValidator } from "../src/policy-validator";
import { hex } from "./helpers";

import type { Issue } from "../src/types";

///////////////////////////////////////////////////////////////////////////
// Vector types
///////////////////////////////////////////////////////////////////////////

type Vector = {
  id: string;
  blob: string;
  description: string;
  issues: { code: string; location: string }[];
};

const vectors: Vector[] = rawVectors;

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** An issue as the vectors spell it: its code, then the indices of the rule it names. */
function issueKey(issue: Issue): string {
  const location = [issue.groupIndex, issue.ruleIndex, issue.bodyRuleIndex].filter((index) => index !== undefined);
  return location.length === 0 ? issue.code : `${issue.code}@${location.join(".")}`;
}

///////////////////////////////////////////////////////////////////////////
// Validation issues
///////////////////////////////////////////////////////////////////////////

describe("Validation conformance vectors - PolicyValidator.validate", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      const actual = PolicyValidator.validate(hex(vector.blob)).map(issueKey).toSorted();
      const expected = vector.issues
        .map((issue) => (issue.location === "" ? issue.code : `${issue.code}@${issue.location}`))
        .toSorted();
      expect(actual).toEqual(expected);
    });
  }
});

import { describe, expect, test } from "vitest";

import rawVectors from "../../../spec/vectors/enforcement.json";
import { PolicyCoder, PolicyEnforcer, toAddress } from "../src";
import { hex, policyDataFromVector } from "./helpers";

import type { Context } from "../src";
import type { VectorPolicy } from "./helpers";

///////////////////////////////////////////////////////////////////////////
// Vector types
///////////////////////////////////////////////////////////////////////////

type VectorContext = {
  msgSender: string;
  msgValue: string;
  baseFee: string;
  gasPrice: string;
  txOrigin?: string;
};

type Vector = {
  id: string;
  description: string;
  policy: VectorPolicy;
  callData: string;
  context?: VectorContext;
  expected?: boolean;
  /** Violation code for malformed-calldata vectors (the onchain enforcer reverts). */
  expectedError?: string;
  /**
   * Expected violation codes, one per failed group. Reporting detail is non-normative (spec 9.3):
   * only implementations that expose a violation list consume this field.
   */
  violations?: string[];
};

///////////////////////////////////////////////////////////////////////////
// Test helpers
///////////////////////////////////////////////////////////////////////////

/** Parse a hex-encoded uint256 context word, returning undefined when zero (unset). */
function parseUint(word: string | undefined): bigint | undefined {
  if (!word) return undefined;
  const value = BigInt(word);
  return value === 0n ? undefined : value;
}

/** Parse a hex-encoded context into the SDK Context type. */
function parseContext(ctx: VectorContext): Context {
  const result: Context = {};

  if (ctx.msgSender && ctx.msgSender !== "0x0000000000000000000000000000000000000000") {
    result.msgSender = toAddress(ctx.msgSender);
  }

  if (ctx.txOrigin) {
    result.txOrigin = toAddress(ctx.txOrigin);
  }

  result.msgValue = parseUint(ctx.msgValue);
  result.baseFee = parseUint(ctx.baseFee);
  result.gasPrice = parseUint(ctx.gasPrice);

  return result;
}

const vectors: Vector[] = rawVectors;

///////////////////////////////////////////////////////////////////////////
// Conformance
///////////////////////////////////////////////////////////////////////////

describe("PolicyEnforcer conformance vectors", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      const policy = PolicyCoder.encode(policyDataFromVector(vector.policy));
      const context = vector.context ? parseContext(vector.context) : undefined;

      const result = PolicyEnforcer.check(policy, hex(vector.callData), context);

      if (vector.expectedError !== undefined) {
        expect(result.ok, "Expected error but got pass").toBe(false);
        if (!result.ok) {
          expect(result.violations.map((violation) => violation.code)).toContain(vector.expectedError);
        }
      } else if (vector.expected) {
        expect(result.ok, `Expected pass but got fail: ${!result.ok ? JSON.stringify(result.violations) : ""}`).toBe(
          true,
        );
      } else {
        expect(result.ok, "Expected fail but got pass").toBe(false);
      }

      if (vector.violations !== undefined && !result.ok) {
        expect(result.violations.map((violation) => violation.code).toSorted()).toEqual(vector.violations.toSorted());
      }
    });
  }
});

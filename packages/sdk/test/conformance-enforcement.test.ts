import { describe, expect, test } from "vitest";

import vectorMap from "../../contracts/test/vectors/enforcement.json";
import { PolicyEnforcer, toAddress } from "../src";
import { hex } from "./helpers";

import type { Context } from "../src";

///////////////////////////////////////////////////////////////////////////
// Vector types
///////////////////////////////////////////////////////////////////////////

type VectorContext = {
  msgSender: string;
  msgValue: string;
  baseFee: string;
  gasPrice: string;
};

type Vector = {
  id: string;
  description: string;
  policy: string;
  callData: string;
  context?: VectorContext;
  expected?: boolean;
  /** Violation code for malformed-calldata vectors (the onchain enforcer reverts). */
  expectedError?: string;
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

  result.msgValue = parseUint(ctx.msgValue);
  result.baseFee = parseUint(ctx.baseFee);
  result.gasPrice = parseUint(ctx.gasPrice);

  return result;
}

const vectors: Vector[] = Object.values(vectorMap);

///////////////////////////////////////////////////////////////////////////
// Conformance
///////////////////////////////////////////////////////////////////////////

describe("PolicyEnforcer conformance vectors", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      const context = vector.context ? parseContext(vector.context) : undefined;

      const result = PolicyEnforcer.check(hex(vector.policy), hex(vector.callData), context);

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
    });
  }
});

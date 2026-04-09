import { describe, expect, test } from "vitest";

import vectorMap from "../../contracts/test/vectors/enforcement.json";
import { check, toAddress } from "../src";
import { hex } from "./helpers";

import type { Context } from "../src";

type VectorContext = {
  msgSender: string;
  msgValue: string;
};

type Vector = {
  id: string;
  description: string;
  policy: string;
  callData: string;
  context?: VectorContext;
  expected: boolean;
};

/** Parse a hex-encoded context into the SDK Context type. */
function parseContext(ctx: VectorContext): Context {
  const result: Context = {};

  if (ctx.msgSender && ctx.msgSender !== "0x0000000000000000000000000000000000000000") {
    result.msgSender = toAddress(ctx.msgSender);
  }

  if (ctx.msgValue && ctx.msgValue !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
    const cleanHex = ctx.msgValue.replace(/^0x/, "");
    result.msgValue = BigInt(`0x${cleanHex}`);
  }

  return result;
}

const vectors: Vector[] = Object.values(vectorMap);

describe("enforcement conformance vectors", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      const context = vector.context ? parseContext(vector.context) : undefined;

      const result = check(hex(vector.policy), hex(vector.callData), context);

      if (vector.expected) {
        expect(result.ok, `Expected pass but got fail: ${!result.ok ? JSON.stringify(result.violations) : ""}`).toBe(
          true,
        );
      } else {
        expect(result.ok, "Expected fail but got pass").toBe(false);
      }
    });
  }
});

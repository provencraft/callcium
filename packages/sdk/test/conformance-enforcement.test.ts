import { describe, expect, test } from "vitest";

import rawVectors from "../../../spec/vectors/enforcement.json";
import { toAddress } from "../src/bytes";
import { PolicyEnforcer, VIOLATION_EFFECT } from "../src/policy-enforcer";
import { assertFailed, expectErrorCode, hex } from "./helpers";

import type { CallciumErrorCode } from "../src/errors";
import type { Context, ViolationCode } from "../src/types";

///////////////////////////////////////////////////////////////////////////
// Vector types
///////////////////////////////////////////////////////////////////////////

type VectorContext = Partial<Record<keyof Context, string>>;

type Vector = {
  id: string;
  description: string;
  blob: string;
  callData: string;
  context?: VectorContext;
  expected?: boolean;
  /** Abort code. */
  expectedError?: string;
  /** Group-local codes, one per failed group. */
  violations?: string[];
  integrityError?: boolean;
};

const vectors: Vector[] = rawVectors;

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** The codes an integrity error throws, each the transliteration of the Solidity error. */
const INTEGRITY_ERRORS = [
  "MALFORMED_HEADER",
  "UNSUPPORTED_VERSION",
  "UNSUPPORTED_MINOR",
] as const satisfies readonly CallciumErrorCode[];

/** Narrow a vector's code to a violation code. */
function violationCode(code: string): ViolationCode {
  if (!isViolationCode(code)) throw new Error(`Unknown violation code ${code}`);
  return code;
}

function isViolationCode(code: string): code is ViolationCode {
  return Object.hasOwn(VIOLATION_EFFECT, code);
}

/** Read a vector context; every key it carries is present, a zero word included. */
function parseContext(vectorContext: VectorContext): Context {
  const context: Context = {};
  for (const [key, word] of Object.entries(vectorContext)) {
    if (key === "msgSender" || key === "txOrigin") context[key] = toAddress(word);
    else if (
      key === "msgValue" ||
      key === "blockTimestamp" ||
      key === "blockNumber" ||
      key === "chainId" ||
      key === "baseFee" ||
      key === "gasPrice"
    ) {
      context[key] = BigInt(word);
    } else throw new Error(`Unknown context key ${key}`);
  }
  return context;
}

///////////////////////////////////////////////////////////////////////////
// Enforcement outcomes
///////////////////////////////////////////////////////////////////////////

describe("Enforcement conformance vectors - PolicyEnforcer.check", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      const blob = hex(vector.blob);
      const callData = hex(vector.callData);
      const context = vector.context === undefined ? undefined : parseContext(vector.context);

      if (vector.integrityError) {
        expectErrorCode(() => PolicyEnforcer.check(blob, callData, context), INTEGRITY_ERRORS);
        return;
      }

      const result = PolicyEnforcer.check(blob, callData, context);
      if (vector.expectedError !== undefined) {
        const code = violationCode(vector.expectedError);
        expect(VIOLATION_EFFECT[code]).toBe("abort");
        assertFailed(result);
        expect(result.violations.at(-1)?.code).toBe(code);
        return;
      }

      expect(result.ok, JSON.stringify(result)).toBe(vector.expected);
      if (!result.ok) {
        const codes = (vector.violations ?? []).map(violationCode);
        expect(result.violations.map((violation) => violation.code)).toEqual(codes);
      }
    });
  }
});

import { describe, expect, test } from "vitest";

import { bytesToHex } from "../src/bytes";
import { MAX_CONTEXT_PROPERTY_ID, Scope } from "../src/constants";
import { DescriptorCoder } from "../src/descriptor-coder";
import { PolicyCoder, parsePathSteps } from "../src/policy-coder";
import { expectErrorCode } from "./helpers";

import type { Constraint, Hex, PolicyData } from "../src/types";

///////////////////////////////////////////////////////////////////////////
// parsePathSteps
///////////////////////////////////////////////////////////////////////////

describe("parsePathSteps", () => {
  test("empty path yields no steps", () => {
    expect(parsePathSteps("0x")).toEqual([]);
  });

  test("single step", () => {
    expect(parsePathSteps("0x0001")).toEqual([1]);
  });

  test("several steps", () => {
    expect(parsePathSteps("0x0000ffff0002")).toEqual([0, 65535, 2]);
  });

  test("odd-length body throws INVALID_HEX", () => {
    expectErrorCode(() => parsePathSteps("0x000"), "INVALID_HEX");
  });

  test("non-hex characters throw INVALID_HEX", () => {
    expectErrorCode(() => parsePathSteps("0xzzzz"), "INVALID_HEX");
  });

  test("non-hex characters in a trailing step throw INVALID_HEX", () => {
    expectErrorCode(() => parsePathSteps("0x0000zz"), "INVALID_HEX");
  });

  test("byte length that is not a whole number of steps throws MALFORMED_PATH", () => {
    expectErrorCode(() => parsePathSteps("0x000000"), "MALFORMED_PATH");
  });
});

///////////////////////////////////////////////////////////////////////////
// Encode check order
///////////////////////////////////////////////////////////////////////////

/** Build PolicyData around `groups`, defaulting the descriptor to a single uint256 param. */
function policyData(groups: Constraint[][], descriptor?: Hex): PolicyData {
  return {
    isSelectorless: true,
    selector: "0x00000000",
    descriptor: descriptor ?? bytesToHex(DescriptorCoder.fromTypes("uint256")),
    groups,
  };
}

describe("PolicyCoder.encode check order", () => {
  const brokenRule: Constraint = { scope: Scope.CALLDATA, path: "0x000000", operators: ["0x"] };

  test("group count outranks a malformed rule", () => {
    const groups = Array.from({ length: 256 }, () => [brokenRule]);
    expectErrorCode(() => PolicyCoder.encode(policyData(groups)), "GROUP_COUNT_OVERFLOW");
  });

  test("operator framing outranks path shape", () => {
    expectErrorCode(() => PolicyCoder.encode(policyData([[brokenRule]])), "INVALID_OPERATOR_BYTES");
  });

  test("descriptor length outranks an empty group", () => {
    const oversized: Hex = `0x${"00".repeat(0x10000)}`;
    const contextRule: Constraint = { scope: Scope.CONTEXT, path: "0x0000", operators: [`0x01${"0".repeat(64)}`] };
    expectErrorCode(() => PolicyCoder.encode(policyData([[contextRule], []], oversized)), "DESC_LENGTH_OVERFLOW");
  });
});

///////////////////////////////////////////////////////////////////////////
// EQ_CTX operand validation (PWF-25)
///////////////////////////////////////////////////////////////////////////

describe("PolicyCoder.decode EQ_CTX operand", () => {
  // Single EQ_CTX rule on address arg(0), calldata scope, operand = msg.sender.
  const EQ_CTX_BLOB: Hex = `0x02fdf80bda0003020141010001000000310031010100000000000000000041080020${"00".repeat(32)}`;

  test("accepts a defined property operand", () => {
    expect(PolicyCoder.decode(EQ_CTX_BLOB)).toBeDefined();
  });

  test("rejects an operand above the defined property range", () => {
    const blob: Hex = `0x${EQ_CTX_BLOB.slice(2, -4)}${(MAX_CONTEXT_PROPERTY_ID + 1).toString(16).padStart(4, "0")}`;
    expectErrorCode(() => PolicyCoder.decode(blob), "UNKNOWN_CONTEXT_PROPERTY");
  });

  test("rejects an operand with garbage above the ID bytes", () => {
    const blob: Hex = `0x${EQ_CTX_BLOB.slice(2, -64)}01${"00".repeat(31)}`;
    expectErrorCode(() => PolicyCoder.decode(blob), "UNKNOWN_CONTEXT_PROPERTY");
  });
});

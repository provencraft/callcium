import { ContextProperty, Op, Scope, TypeCode, type Violation } from "@callcium/sdk";
import { describe, expect, it } from "vitest";
import { formatViolation } from "../format-violation";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** Pad a hex value to a 32-byte ABI word, right-aligned. */
function word(value: bigint): `0x${string}` {
  return `0x${value.toString(16).padStart(64, "0")}`;
}

const ARG0_PATH: `0x${string}` = "0x0000";
const CONTEXT_MSG_SENDER_PATH: `0x${string}` = `0x${ContextProperty.MSG_SENDER.toString(16).padStart(4, "0")}`;

///////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////

describe("formatViolation", () => {
  it("formats a scalar leaf VALUE_MISMATCH with decimal integer rendering", () => {
    const v: Violation = {
      group: 0,
      rule: 0,
      code: "VALUE_MISMATCH",
      scope: Scope.CALLDATA,
      path: ARG0_PATH,
      opCode: Op.LT,
      operandData: word(1_000_000_000_000_000_000n),
      typeCode: TypeCode.UINT_MAX,
      resolvedValue: word(105_200_000_000_000_000_000_000n),
    };
    expect(formatViolation(v)).toBe("arg(0): < 1000000000000000000 violated by 105200000000000000000000");
  });

  it("formats a context VALUE_MISMATCH with checksummed address rendering", () => {
    const expected = "0x0000000000000000000000000000000000000001";
    const actual = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045";
    const v: Violation = {
      group: 0,
      rule: 0,
      code: "VALUE_MISMATCH",
      scope: Scope.CONTEXT,
      path: CONTEXT_MSG_SENDER_PATH,
      opCode: Op.EQ,
      operandData: `0x${"00".repeat(12)}${expected.slice(2)}`,
      typeCode: TypeCode.ADDRESS,
      resolvedValue: `0x${"00".repeat(12)}${actual.slice(2)}`,
    };
    expect(formatViolation(v)).toBe(
      "msg.sender: == 0x0000000000000000000000000000000000000001 violated by 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
    );
  });

  it("collapses NOT-eq into != and renders bool literals", () => {
    const v: Violation = {
      group: 0,
      rule: 0,
      code: "VALUE_MISMATCH",
      scope: Scope.CALLDATA,
      path: ARG0_PATH,
      opCode: Op.EQ | Op.NOT,
      operandData: word(0n),
      typeCode: TypeCode.BOOL,
      resolvedValue: word(0n),
    };
    expect(formatViolation(v)).toBe("arg(0): != false violated by false");
  });

  it("formats a quantifier per-element VALUE_MISMATCH with the failing element's actual value", () => {
    const v: Violation = {
      group: 0,
      rule: 0,
      code: "VALUE_MISMATCH",
      scope: Scope.CALLDATA,
      path: "0x000000ff",
      opCode: Op.GT,
      operandData: word(0n),
      typeCode: TypeCode.UINT_MAX,
      resolvedValue: word(0n),
      elementIndex: 1,
    };
    expect(formatViolation(v)).toContain("violated at element 1 by 0");
  });

  it("falls back to actual-less wording when a per-element VALUE_MISMATCH lacks resolvedValue", () => {
    const v: Violation = {
      group: 0,
      rule: 0,
      code: "VALUE_MISMATCH",
      scope: Scope.CALLDATA,
      path: "0x000000ff",
      opCode: Op.GT,
      operandData: word(0n),
      typeCode: TypeCode.UINT_MAX,
      elementIndex: 1,
    };
    const summary = formatViolation(v);
    expect(summary).toContain("violated at element 1");
    expect(summary).not.toContain(" by ");
  });

  it("formats an existential quantifier failure as violated by all elements", () => {
    const v: Violation = {
      group: 0,
      rule: 0,
      code: "VALUE_MISMATCH",
      scope: Scope.CALLDATA,
      path: "0x000001ff",
      opCode: Op.EQ,
      operandData: word(42n),
      typeCode: TypeCode.UINT_MAX,
    };
    expect(formatViolation(v)).toContain("violated by all elements");
  });

  it("formats SELECTOR_MISMATCH with expected and actual selectors", () => {
    const v: Violation = {
      code: "SELECTOR_MISMATCH",
      resolvedValue: "0x12345678",
      expectedValue: "0xabcdef00",
    };
    expect(formatViolation(v)).toBe("selector mismatch: expected 0xabcdef00, got 0x12345678");
  });

  it("formats QUANTIFIER_LIMIT_EXCEEDED with a decimal count", () => {
    const v: Violation = {
      group: 0,
      rule: 0,
      code: "QUANTIFIER_LIMIT_EXCEEDED",
      scope: Scope.CALLDATA,
      path: ARG0_PATH,
      resolvedValue: word(300n),
    };
    expect(formatViolation(v)).toBe("arg(0): array length 300 exceeds maximum");
  });

  it("formats length-op violations with decimal counts on both sides", () => {
    const v: Violation = {
      group: 0,
      rule: 0,
      code: "VALUE_MISMATCH",
      scope: Scope.CALLDATA,
      path: ARG0_PATH,
      opCode: Op.LENGTH_EQ,
      operandData: word(5n),
      typeCode: TypeCode.BYTES,
      resolvedValue: word(7n),
    };
    expect(formatViolation(v)).toBe("arg(0): length == 5 violated by 7");
  });
});

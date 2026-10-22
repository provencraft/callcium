import { describe, expect, test } from "vitest";

import rawVectors from "../../../spec/vectors/enforcement.json";
import { bigintToHex, hexToBytes, toHex } from "../src/bytes";
import { ContextProperty, Op, PolicyFormat as PF, Scope, Source, TypeCode } from "../src/constants";
import { arg, msgSender } from "../src/constraint";
import { PolicyViolationError } from "../src/errors";
import { PolicyBuilder } from "../src/policy-builder";
import { PolicyEnforcer } from "../src/policy-enforcer";
import { assertFailed, assertPassed, expectErrorCode, expectFirstViolation, hex, vectorById, wordHex } from "./helpers";

import type { Context, Hex } from "../src/types";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** The blob and calldata of the enforcement vector `id`. */
function vector(id: string): { blob: Hex; callData: Hex } {
  const found = vectorById(rawVectors, id);
  return { blob: hex(found.blob), callData: hex(found.callData) };
}

/** The selector slot of `blob`. */
function selectorOf(blob: Hex): Hex {
  return toHex(hexToBytes(blob), PF.SELECTOR_OFFSET, PF.SELECTOR_OFFSET + PF.SELECTOR_SIZE);
}

const senderContext: Context = { msgSender: "0x0000000000000000000000000000000000000001" };

///////////////////////////////////////////////////////////////////////////
// Entry
///////////////////////////////////////////////////////////////////////////

describe("PolicyEnforcer.check entry", () => {
  test("rejects an unsupported major version before its minor", () => {
    const { blob, callData } = vector("multi-rule-and-fail");
    const data = hexToBytes(blob);
    data[0] = ((PF.MAJOR + 1) << PF.MAJOR_SHIFT) | ((PF.SUPPORTED_MINOR + 1) << PF.MINOR_SHIFT);
    const raised = toHex(data, 0, data.length);
    expectErrorCode(() => PolicyEnforcer.check(raised, callData), "UNSUPPORTED_VERSION");
  });

  test("rejects a minor version above the highest supported", () => {
    const { blob, callData } = vector("multi-rule-and-fail");
    const data = hexToBytes(blob);
    data[0] = (PF.MAJOR << PF.MAJOR_SHIFT) | ((PF.SUPPORTED_MINOR + 1) << PF.MINOR_SHIFT);
    const raised = toHex(data, 0, data.length);
    expectErrorCode(() => PolicyEnforcer.check(raised, callData), "UNSUPPORTED_MINOR");
  });
});

///////////////////////////////////////////////////////////////////////////
// Violation fields
///////////////////////////////////////////////////////////////////////////

describe("PolicyEnforcer.check violation fields", () => {
  test("a pass names the group that matched", () => {
    const { blob, callData } = vector("group-local-value-mismatch-multi-group");
    const result = PolicyEnforcer.check(blob, callData);
    assertPassed(result);
    expect(result.matchedGroup).toBe(1);
  });

  test("a failed test names its group, rule, value and operator", () => {
    const { blob, callData } = vector("multi-group-or-fail-all");
    const result = PolicyEnforcer.check(blob, callData);
    assertFailed(result);
    const violation = result.violations[1];
    expect(violation).toEqual({
      code: "VALUE_MISMATCH",
      group: 1,
      rule: 0,
      scope: Scope.CALLDATA,
      path: "0x0000",
      operator: {
        opCode: Op.EQ,
        comparison: Op.EQ,
        negated: false,
        operandType: TypeCode.UINT_MAX,
        source: Source.CONSTANT,
        values: [bigintToHex(2n)],
      },
      typeCode: TypeCode.UINT_MAX,
      resolvedValue: bigintToHex(99n),
    });
  });

  test("a failed body test names its position in the body and the element", () => {
    const { blob } = vector("quantifier-body-context-pass");
    // [1, 0]: the second element fails the body's second test, `> 0`.
    const callData = hex(`${selectorOf(blob)}${wordHex(0x20n)}${wordHex(2n)}${wordHex(1n)}${wordHex(0n)}`);
    const violation = expectFirstViolation(PolicyEnforcer.check(blob, callData, senderContext), "VALUE_MISMATCH");
    expect(violation).toMatchObject({ group: 0, rule: 0, bodyRule: 1, elementIndex: 1, path: "0x" });
  });

  test("a failed test against a context operand carries the operand's value", () => {
    const { blob, callData } = vector("gt-ctx-value-fail");
    const violation = expectFirstViolation(PolicyEnforcer.check(blob, callData, { msgValue: 42n }), "VALUE_MISMATCH");
    expect(violation.resolvedOperand).toBe(bigintToHex(42n));
  });

  test("a mismatched selector carries both selectors", () => {
    const { blob, callData } = vector("selector-mismatch");
    const violation = expectFirstViolation(PolicyEnforcer.check(blob, callData), "SELECTOR_MISMATCH");
    expect(violation).toEqual({
      code: "SELECTOR_MISMATCH",
      expectedValue: selectorOf(blob),
      resolvedValue: toHex(hexToBytes(callData), 0, PF.SELECTOR_SIZE),
    });
  });

  test("an ANY loop without a match names the loop rule and no element or test", () => {
    const { blob, callData } = vector("eq-ctx-any-fail");
    const violation = expectFirstViolation(PolicyEnforcer.check(blob, callData, senderContext), "QUANTIFIER_NO_MATCH");
    expect(violation).toEqual({ code: "QUANTIFIER_NO_MATCH", group: 0, rule: 0, scope: Scope.LOOP, path: "0x0000" });
  });
});

///////////////////////////////////////////////////////////////////////////
// Missing context
///////////////////////////////////////////////////////////////////////////

describe("PolicyEnforcer.check missing context", () => {
  test("an absent subject names the property's type and no operator", () => {
    const { blob, callData } = vector("context-sender-pass");
    const violation = expectFirstViolation(PolicyEnforcer.check(blob, callData), "MISSING_CONTEXT");
    expect(violation).toEqual({
      code: "MISSING_CONTEXT",
      group: 0,
      rule: 0,
      scope: Scope.CONTEXT,
      path: "0x0000",
      typeCode: TypeCode.ADDRESS,
    });
  });

  test("an absent operand names the operator and the operand property's type", () => {
    const { blob, callData } = vector("eq-ctx-value-pass");
    const violation = expectFirstViolation(PolicyEnforcer.check(blob, callData), "MISSING_CONTEXT");
    expect(violation).toMatchObject({
      scope: Scope.CALLDATA,
      operator: {
        opCode: Op.EQ | (Source.CONTEXT << Op.SOURCE_SHIFT),
        comparison: Op.EQ,
        negated: false,
        operandType: TypeCode.UINT_MAX,
        source: Source.CONTEXT,
        contextPropertyId: ContextProperty.MSG_VALUE,
      },
      typeCode: TypeCode.UINT_MAX,
    });
  });

  test("an absent operand of a context test names the operator and the operand property's type", () => {
    const { blob, callData } = vector("eq-ctx-context-subject-pass");
    const violation = expectFirstViolation(PolicyEnforcer.check(blob, callData, senderContext), "MISSING_CONTEXT");
    expect(violation).toMatchObject({
      scope: Scope.CONTEXT,
      operator: { comparison: Op.EQ, source: Source.CONTEXT, contextPropertyId: ContextProperty.TX_ORIGIN },
      typeCode: TypeCode.ADDRESS,
    });
  });

  test("an absent property fails its group and the next group still passes", () => {
    const blob = PolicyBuilder.create("foo(uint256)")
      .add(msgSender().eq("0x0000000000000000000000000000000000000001"))
      .or()
      .add(arg(0).eq(1n))
      .build();
    const callData = hex(`${selectorOf(blob)}${wordHex(1n)}`);
    const result = PolicyEnforcer.check(blob, callData);
    assertPassed(result);
    expect(result.matchedGroup).toBe(1);
  });
});

///////////////////////////////////////////////////////////////////////////
// Context values
///////////////////////////////////////////////////////////////////////////

describe("PolicyEnforcer.check context values", () => {
  test("rejects an integer outside a 32-byte word", () => {
    const { blob, callData } = vector("eq-ctx-value-pass");
    expectErrorCode(() => PolicyEnforcer.check(blob, callData, { msgValue: -1n }), "CONTEXT_VALUE_OVERFLOW");
    expectErrorCode(() => PolicyEnforcer.check(blob, callData, { msgValue: 2n ** 256n }), "CONTEXT_VALUE_OVERFLOW");
  });

  test("rejects a value not of its property's type", () => {
    const { blob, callData } = vector("eq-ctx-value-pass");
    const numberValue: Context = JSON.parse('{ "msgValue": 42 }');
    const numberSender: Context = JSON.parse('{ "msgSender": 1 }');
    expectErrorCode(() => PolicyEnforcer.check(blob, callData, numberValue), "MALFORMED_CONTEXT_VALUE");
    expectErrorCode(() => PolicyEnforcer.check(blob, callData, numberSender), "MALFORMED_CONTEXT_VALUE");
  });
});

///////////////////////////////////////////////////////////////////////////
// enforce
///////////////////////////////////////////////////////////////////////////

describe("PolicyEnforcer.enforce", () => {
  test("throws the violations check reports", () => {
    const { blob, callData } = vector("multi-group-or-fail-all");
    const result = PolicyEnforcer.check(blob, callData);
    assertFailed(result);
    let thrown: unknown;
    try {
      PolicyEnforcer.enforce(blob, callData);
    } catch (error) {
      thrown = error;
    }
    expect(thrown).toBeInstanceOf(PolicyViolationError);
    if (!(thrown instanceof PolicyViolationError)) return;
    expect(thrown.violations).toEqual(result.violations);
    expect(thrown.message).toBe("Policy violation: VALUE_MISMATCH at group 0 rule 0");
  });
});

import { describe, expect, test } from "vitest";

import validationVectors from "../../../spec/vectors/validation.json";
import { bigintToHex, bytesToHex, hexToBytes } from "../src/bytes";
import {
  ContextProperty,
  DescriptorFormat as DF,
  Op,
  PolicyFormat as PF,
  Scope,
  Source,
  TypeCode,
} from "../src/constants";
import { arg } from "../src/constraint";
import { encodePath, Quantifier } from "../src/path";
import { PolicyBuilder } from "../src/policy-builder";
import { isOpAllowed, PolicyValidator } from "../src/policy-validator";
import { expectErrorCode, hex, op, vectorById } from "./helpers";

import type { Issue } from "../src/types";

///////////////////////////////////////////////////////////////////////////
// validate
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator.validate", () => {
  test("throws the storage error of a blob that fails storage validation, before analysis", () => {
    const bytes = hexToBytes(PolicyBuilder.create("foo((uint256))").add(arg(0, 0).eq(1n)).build());
    // The low byte of the tuple's field count, set to zero.
    bytes[PF.DESC_OFFSET + DF.HEADER_SIZE + DF.TYPECODE_SIZE + DF.COMPOSITE_META_SIZE + 1] = 0;
    expectErrorCode(() => PolicyValidator.validate(bytesToHex(bytes)), "INVALID_TUPLE_FIELD_COUNT");
  });

  test("names a root test by its position, its path and its operator", () => {
    const blob = PolicyBuilder.create("foo(address)").add(arg(0).gt(1n)).buildUnsafe();
    const [issue] = PolicyValidator.validate(blob);
    expect(issue).toMatchObject({
      groupIndex: 0,
      ruleIndex: 0,
      scope: Scope.CALLDATA,
      path: encodePath([0]),
      operator: op(Op.GT, 1n),
    });
    expect(issue).not.toHaveProperty("bodyRuleIndex");
  });

  test("names a body test by its loop, its position in the body, its path from the element and its operator", () => {
    const blob = PolicyBuilder.create("foo((uint256,address)[])")
      .add(arg(0, Quantifier.ALL, 1).gt(1n))
      .buildUnsafe();
    expect(PolicyValidator.validate(blob)).toEqual([
      {
        groupIndex: 0,
        ruleIndex: 0,
        bodyRuleIndex: 0,
        scope: Scope.CALLDATA,
        path: encodePath([1]),
        operator: op(Op.GT, 1n),
        severity: "error",
        category: "typeMismatch",
        code: "NUMERIC_OP_ON_NON_NUMERIC",
        value1: bigintToHex(BigInt(Op.GT)),
        value2: bigintToHex(0n),
        message: "Comparison operator used on non-numeric type",
      },
    ]);
  });

  describe("issue values", () => {
    const cases: {
      id: string;
      severity: Issue["severity"];
      category: Issue["category"];
      value1: bigint;
      value2: bigint;
      message: string;
    }[] = [
      {
        id: "invalid-descriptor",
        severity: "error",
        category: "typeMismatch",
        value1: 3n,
        value2: 0n,
        message: "Descriptor node metadata disagrees with its children",
      },
      {
        id: "unnavigable-path",
        severity: "error",
        category: "typeMismatch",
        value1: 1n,
        value2: 2n,
        message: "Path does not navigate the descriptor",
      },
      {
        id: "quantifier-on-non-array",
        severity: "error",
        category: "typeMismatch",
        value1: BigInt(TypeCode.UINT_MAX),
        value2: 0n,
        message: "Loop path does not end at an array",
      },
      {
        id: "hint-mismatch",
        severity: "error",
        category: "typeMismatch",
        value1: 0n,
        value2: 0n,
        message: "Hint does not match the path compiled against the descriptor",
      },
      {
        id: "context-operand-on-signed",
        severity: "error",
        category: "typeMismatch",
        value1: BigInt(ContextProperty.MSG_VALUE),
        value2: BigInt(TypeCode.INT_MAX),
        message: "Context property type does not match the target type",
      },
      {
        id: "bool-operand-two",
        severity: "error",
        category: "contradiction",
        value1: 2n,
        value2: 0n,
        message: "Value is outside the physical range of the type",
      },
      {
        id: "mask-contradiction",
        severity: "error",
        category: "contradiction",
        value1: 0n,
        value2: 0n,
        message: "Rules on the subject are not satisfiable together",
      },
      {
        id: "bound-implied-by-mask",
        severity: "warning",
        category: "redundancy",
        value1: 0n,
        value2: 0n,
        message: "Rule is implied by the other rules on its subject",
      },
      {
        id: "signed-dominated-bound",
        severity: "warning",
        category: "redundancy",
        value1: BigInt.asUintN(256, -10n),
        value2: BigInt.asUintN(256, -2n),
        message: "Numeric bound is dominated by a stricter bound",
      },
      {
        id: "int256-dominated-bound",
        severity: "warning",
        category: "redundancy",
        value1: BigInt.asUintN(256, -(2n ** 255n)),
        value2: BigInt.asUintN(256, -(2n ** 255n) + 1n),
        message: "Numeric bound is dominated by a stricter bound",
      },
      {
        id: "dominated-length-bound",
        severity: "warning",
        category: "redundancy",
        value1: 10n,
        value2: 4n,
        message: "Length bound is dominated by a stricter bound",
      },
      {
        id: "vacuous-length",
        severity: "info",
        category: "vacuity",
        value1: 0n,
        value2: 0n,
        message: "Rule holds for every value",
      },
      {
        id: "quantifier-over-static-limit",
        severity: "error",
        category: "compatibility",
        value1: BigInt(PF.MAX_QUANTIFIED_ARRAY_LENGTH + 1),
        value2: BigInt(PF.MAX_QUANTIFIED_ARRAY_LENGTH),
        message: "Quantifier over static array exceeds the maximum quantified length",
      },
      {
        id: "context-only-all-body",
        severity: "error",
        category: "compatibility",
        value1: 0n,
        value2: 0n,
        message: "Loop body holds no test of the element",
      },
    ];

    for (const { id, severity, category, value1, value2, message } of cases) {
      test(`${id} carries its category, severity, values and message`, () => {
        const vector = vectorById(validationVectors, id);
        const [issue] = PolicyValidator.validate(hex(vector.blob));
        expect(issue).toMatchObject({
          severity,
          category,
          value1: bigintToHex(value1),
          value2: bigintToHex(value2),
          message,
        });
      });
    }
  });
});

///////////////////////////////////////////////////////////////////////////
// isOpAllowed
///////////////////////////////////////////////////////////////////////////

describe("isOpAllowed", () => {
  test("admits an ordering on an integer and refuses it on an address", () => {
    expect(isOpAllowed(Op.GT, TypeCode.INT_MIN)).toBe(true);
    expect(isOpAllowed(Op.GT, TypeCode.ADDRESS)).toBe(false);
  });

  test("tolerates the NOT flag", () => {
    expect(isOpAllowed(Op.EQ | Op.NOT, TypeCode.BOOL)).toBe(true);
  });

  test("refuses an unassigned comparison", () => {
    expect(isOpAllowed(0x0f, TypeCode.UINT_MAX)).toBe(false);
  });

  test("admits a bitmask on an integer, an address and fixed bytes, and refuses it on a bool and a function", () => {
    expect(isOpAllowed(Op.BITMASK_ALL, TypeCode.INT_MAX)).toBe(true);
    expect(isOpAllowed(Op.BITMASK_ANY, TypeCode.ADDRESS)).toBe(true);
    expect(isOpAllowed(Op.BITMASK_NONE, TypeCode.FIXED_BYTES_MIN)).toBe(true);
    expect(isOpAllowed(Op.BITMASK_ALL, TypeCode.BOOL)).toBe(false);
    expect(isOpAllowed(Op.BITMASK_ALL, TypeCode.FUNCTION)).toBe(false);
  });

  test("refuses a comparison of the wrong class for its target", () => {
    expect(isOpAllowed(Op.LENGTH_EQ, TypeCode.UINT_MAX)).toBe(false);
    expect(isOpAllowed(Op.EQ, TypeCode.BYTES)).toBe(false);
  });

  test("admits a context operand on an unsigned target, and on an address under EQ alone", () => {
    const context = Source.CONTEXT << Op.SOURCE_SHIFT;
    expect(isOpAllowed(Op.GT | context, TypeCode.UINT_MIN)).toBe(true);
    expect(isOpAllowed(Op.EQ | context, TypeCode.ADDRESS)).toBe(true);
    expect(isOpAllowed(Op.GT | context, TypeCode.ADDRESS)).toBe(false);
    expect(isOpAllowed(Op.BETWEEN | context, TypeCode.UINT_MIN)).toBe(false);
  });
});

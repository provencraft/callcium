import { describe, expect, test } from "vitest";

import {
  CallciumError,
  ContextProperty,
  PolicyBuilder,
  Quantifier,
  arg,
  msgSender,
  msgValue,
  Op,
  Scope,
  TypeCode,
} from "../src";
import { bytesToHex } from "../src/bytes";
import { MAX_CONTEXT_PROPERTY_ID } from "../src/constants";
import { DescriptorCoder } from "../src/descriptor-coder";
import { PolicyValidator } from "../src/policy-validator";
import { expectErrorCode, expectIssueCode, refuteIssueCode, op, rangeOp, inOp } from "./helpers";

import type { Constraint, Hex, Issue, PolicyData } from "../src/types";

///////////////////////////////////////////////////////////////////////////
// Test helpers
///////////////////////////////////////////////////////////////////////////

/**
 * Build a raw PolicyData with a single constraint. Used only for tests
 * that the builder would reject (empty groups, unsorted sets, unknown
 * opcodes, LENGTH on static types, context-scope with raw paths).
 */
function rawPolicy(typesCsv: string, scope: number, path: Hex, operators: Hex[]): PolicyData {
  return {
    isSelectorless: true,
    selector: "0x00000000",
    descriptor: bytesToHex(DescriptorCoder.fromTypes(typesCsv)),
    groups: [[{ scope, path, operators }]],
  };
}

/** Build a raw PolicyData with multiple constraints in one group (same-path cross-constraint tests). */
function multiConstraintPolicy(
  typesCsv: string,
  constraints: Array<{ scope: number; path: Hex; operators: Hex[] }>,
): PolicyData {
  return {
    isSelectorless: true,
    selector: "0x00000000",
    descriptor: bytesToHex(DescriptorCoder.fromTypes(typesCsv)),
    groups: [constraints],
  };
}

/** Validate via PolicyBuilder and return issues. */
function validate(typesCsv: string, build: (b: ReturnType<typeof PolicyBuilder.createRaw>) => void): Issue[] {
  const builder = PolicyBuilder.createRaw(typesCsv);
  build(builder);
  return builder.validate();
}

///////////////////////////////////////////////////////////////////////////
// Type Compatibility
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - type compatibility", () => {
  test("reports VALUE_OP_ON_DYNAMIC for eq on bytes", () => {
    // Builder rejects this at add() time, so use raw.
    const issues = PolicyValidator.validate(rawPolicy("bytes", Scope.CALLDATA, "0x0000", [op(Op.EQ, 42n)]));
    expectIssueCode(issues, "VALUE_OP_ON_DYNAMIC");
  });

  test("reports VALUE_OP_ON_COMPOSITE for eq on a one-element static array", () => {
    // uint256[1] has a 32-byte static head but is composite; the enforcer cannot load it.
    const issues = PolicyValidator.validate(rawPolicy("uint256[1]", Scope.CALLDATA, "0x0000", [op(Op.EQ, 42n)]));
    expectIssueCode(issues, "VALUE_OP_ON_COMPOSITE");
  });

  test("reports VALUE_OP_ON_COMPOSITE for eq on a single-static-field tuple", () => {
    const issues = PolicyValidator.validate(rawPolicy("(uint256)", Scope.CALLDATA, "0x0000", [op(Op.EQ, 42n)]));
    expectIssueCode(issues, "VALUE_OP_ON_COMPOSITE");
  });

  test("reports NUMERIC_OP_ON_NON_NUMERIC for gt on address", () => {
    const issues = validate("address", (b) => b.add(arg(0).gt(42n)));
    expectIssueCode(issues, "NUMERIC_OP_ON_NON_NUMERIC");
  });

  test("reports BITMASK_ON_INVALID for bitmask on int256", () => {
    const issues = validate("int256", (b) => b.add(arg(0).bitmaskAll(0xffn)));
    expectIssueCode(issues, "BITMASK_ON_INVALID");
  });

  test("reports LENGTH_ON_STATIC for lengthEq on uint256", () => {
    // Builder rejects LENGTH on static types, so use raw.
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(Op.LENGTH_EQ, 5n)]));
    expectIssueCode(issues, "LENGTH_ON_STATIC");
  });

  test("allows eq on uint256 with no issues", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(42n)));
    expect(issues).toHaveLength(0);
  });

  test("allows bitmask on uint256", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskAll(0xffn)));
    expect(issues).toHaveLength(0);
  });

  test("allows bitmask on bytes32", () => {
    const issues = validate("bytes32", (b) => b.add(arg(0).bitmaskAll(0xffn)));
    expect(issues).toHaveLength(0);
  });

  test("allows lengthEq on bytes", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthEq(32n)));
    expect(issues).toHaveLength(0);
  });

  test("allows lengthEq on string", () => {
    const issues = validate("string", (b) => b.add(arg(0).lengthEq(32n)));
    expect(issues).toHaveLength(0);
  });

  test("allows comparison on uint8", () => {
    const issues = validate("uint8", (b) => b.add(arg(0).gt(5n)));
    expect(issues).toHaveLength(0);
  });

  test("allows comparison on int256", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(0n)));
    expect(issues).toHaveLength(0);
  });
});

///////////////////////////////////////////////////////////////////////////
// Canonical Operands
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - canonical operands", () => {
  test("reports NON_CANONICAL_OPERAND for right-aligned bytes4 operand", () => {
    // A right-aligned word for a left-aligned type can never match a canonical value.
    const issues = PolicyValidator.validate(rawPolicy("bytes4", Scope.CALLDATA, "0x0000", [op(Op.EQ, 0x11223344n)]));
    expectIssueCode(issues, "NON_CANONICAL_OPERAND");
  });

  test("accepts left-aligned bytes4 operand", () => {
    const issues = PolicyValidator.validate(
      rawPolicy("bytes4", Scope.CALLDATA, "0x0000", [op(Op.EQ, 0x11223344n << 224n)]),
    );
    expect(issues).toHaveLength(0);
  });
});

///////////////////////////////////////////////////////////////////////////
// Bound Contradictions
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bound contradictions", () => {
  test("reports CONFLICTING_EQUALITY for eq(5) + eq(10)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).eq(10n)));
    expectIssueCode(issues, "CONFLICTING_EQUALITY");
  });

  test("reports EQ_NEQ_CONTRADICTION for eq(5) + neq(5)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).neq(5n)));
    expectIssueCode(issues, "EQ_NEQ_CONTRADICTION");
  });

  test("reports IMPOSSIBLE_GT for gt(uint256.max)", () => {
    const max256 = (1n << 256n) - 1n;
    const issues = validate("uint256", (b) => b.add(arg(0).gt(max256)));
    expectIssueCode(issues, "IMPOSSIBLE_GT");
  });

  test("reports IMPOSSIBLE_LT for lt(0) on uint256", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lt(0n)));
    expectIssueCode(issues, "IMPOSSIBLE_LT");
  });

  test("reports IMPOSSIBLE_RANGE for gte(100) + lte(50)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(100n).lte(50n)));
    expectIssueCode(issues, "IMPOSSIBLE_RANGE");
  });

  test("reports BOUNDS_EXCLUDE_EQUALITY for eq(5) + gte(10)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).gte(10n)));
    expectIssueCode(issues, "BOUNDS_EXCLUDE_EQUALITY");
  });

  test("reports OUT_OF_PHYSICAL_BOUNDS for uint8 value > 255", () => {
    const issues = validate("uint8", (b) => b.add(arg(0).eq(256n)));
    expectIssueCode(issues, "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("reports OUT_OF_PHYSICAL_BOUNDS for uint8 isIn member > 255", () => {
    const issues = validate("uint8", (b) => b.add(arg(0).isIn([5n, 1000n])));
    expectIssueCode(issues, "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("reports OUT_OF_PHYSICAL_BOUNDS for int8 isIn member below min", () => {
    const issues = validate("int8", (b) => b.add(arg(0).isIn([-129n, -5n])));
    expectIssueCode(issues, "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("no issue for uint8 isIn members within range", () => {
    const issues = validate("uint8", (b) => b.add(arg(0).isIn([0n, 255n])));
    expect(issues).toHaveLength(0);
  });
});

///////////////////////////////////////////////////////////////////////////
// Bound Redundancy
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bound redundancy", () => {
  test("reports DOMINATED_BOUND for gte(10) + gte(5)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(10n).gte(5n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });

  test("reports REDUNDANT_BOUND for eq(5) + gte(3)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).gte(3n)));
    expectIssueCode(issues, "REDUNDANT_BOUND");
  });
});

///////////////////////////////////////////////////////////////////////////
// Bound Vacuity
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bound vacuity", () => {
  test("reports VACUOUS_GTE for gte(0) on uint256", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(0n)));
    expectIssueCode(issues, "VACUOUS_GTE");
  });

  test("reports VACUOUS_LTE for lte(uint256.max)", () => {
    const max256 = (1n << 256n) - 1n;
    const issues = validate("uint256", (b) => b.add(arg(0).lte(max256)));
    expectIssueCode(issues, "VACUOUS_LTE");
  });
});

///////////////////////////////////////////////////////////////////////////
// Bitmask
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bitmask", () => {
  test("reports BITMASK_CONTRADICTION for all(0xff) + none(0xff)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskAll(0xffn).bitmaskNone(0xffn)));
    expectIssueCode(issues, "BITMASK_CONTRADICTION");
  });

  test("reports BITMASK_ANY_IMPOSSIBLE when all bits forbidden", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskNone(0xffn).bitmaskAny(0xffn)));
    expectIssueCode(issues, "BITMASK_ANY_IMPOSSIBLE");
  });

  test("reports REDUNDANT_BITMASK for duplicate all", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskAll(0xffn).bitmaskAll(0x0fn)));
    expectIssueCode(issues, "REDUNDANT_BITMASK");
  });
});

///////////////////////////////////////////////////////////////////////////
// Set
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - set", () => {
  test("reports EMPTY_SET_INTERSECTION for disjoint isIn sets", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n]).isIn([4n, 5n, 6n])));
    expectIssueCode(issues, "EMPTY_SET_INTERSECTION");
  });

  test("reports SET_FULLY_EXCLUDED when all isIn values are excluded", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n]).notIn([1n, 2n])));
    expectIssueCode(issues, "SET_FULLY_EXCLUDED");
  });

  test("reports UNSORTED_IN_SET for unsorted set", () => {
    // Builder auto-sorts, so use raw with pre-built unsorted operator hex.
    const issues = PolicyValidator.validate(
      rawPolicy("uint256", Scope.CALLDATA, "0x0000", [inOp(Op.IN, [3n, 1n, 2n])]),
    );
    expectIssueCode(issues, "UNSORTED_IN_SET");
  });

  test("reports SET_EXCLUDES_EQUALITY when notIn excludes eq value", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).notIn([5n])));
    expectIssueCode(issues, "SET_EXCLUDES_EQUALITY");
  });

  test("reports SET_REDUNDANCY for partially overlapping isIn sets", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n]).isIn([2n, 3n, 4n])));
    expectIssueCode(issues, "SET_REDUNDANCY");
  });

  test("reports SET_REDUCTION when notIn value is in isIn set", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n]).notIn([2n])));
    expectIssueCode(issues, "SET_REDUCTION");
  });
});

///////////////////////////////////////////////////////////////////////////
// Length
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - length domain", () => {
  test("reports CONFLICTING_LENGTH for lengthEq(5) + lengthEq(10)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthEq(5n).lengthEq(10n)));
    expectIssueCode(issues, "CONFLICTING_LENGTH");
  });

  test("reports IMPOSSIBLE_LENGTH_GT for lengthGt(uint32.max)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGt(0xffffffffn)));
    expectIssueCode(issues, "IMPOSSIBLE_LENGTH_GT");
  });

  test("reports IMPOSSIBLE_LENGTH_LT for lengthLt(0)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthLt(0n)));
    expectIssueCode(issues, "IMPOSSIBLE_LENGTH_LT");
  });

  test("reports VACUOUS_LENGTH_GTE for lengthGte(0)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGte(0n)));
    expectIssueCode(issues, "VACUOUS_LENGTH_GTE");
  });

  test("reports VACUOUS_LENGTH_LTE for lengthLte(uint32.max)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthLte(0xffffffffn)));
    expectIssueCode(issues, "VACUOUS_LENGTH_LTE");
  });

  test("reports IMPOSSIBLE_LENGTH_RANGE for lengthGte(100) + lengthLte(50)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGte(100n).lengthLte(50n)));
    expectIssueCode(issues, "IMPOSSIBLE_LENGTH_RANGE");
  });

  test("reports LENGTH_EQ_NEQ_CONTRADICTION for lengthEq(5) + !lengthEq(5)", () => {
    // No lengthNeq() method on builder — use raw operator hex.
    const issues = PolicyValidator.validate(
      rawPolicy("bytes", Scope.CALLDATA, "0x0000", [op(Op.LENGTH_EQ, 5n), op(Op.LENGTH_EQ | Op.NOT, 5n)]),
    );
    expectIssueCode(issues, "LENGTH_EQ_NEQ_CONTRADICTION");
  });

  test("reports BOUNDS_EXCLUDE_LENGTH when lengthEq(0) contradicts composed strict ALL", () => {
    // Strict universality composes as lengthGt(0) + ALL; adding lengthEq(0) contradicts the length rule.
    const issues = validate("uint256[]", (b) =>
      b.add(arg(0).lengthEq(0n).lengthGt(0n)).add(arg(0, Quantifier.ALL).gt(0n)),
    );
    expectIssueCode(issues, "BOUNDS_EXCLUDE_LENGTH");
  });

  test("handles LENGTH_BETWEEN correctly", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthBetween(10n, 20n)));
    expect(issues).toHaveLength(0);
  });

  test("reports DOMINATED_LENGTH_BOUND for lengthGte(10) + lengthGte(5)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGte(10n).lengthGte(5n)));
    expectIssueCode(issues, "DOMINATED_LENGTH_BOUND");
  });

  test("reports DOMINATED_LENGTH_BOUND for lengthGte(5) superseded by lengthGte(10)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGte(5n).lengthGte(10n)));
    expectIssueCode(issues, "DOMINATED_LENGTH_BOUND");
  });

  test("reports DOMINATED_LENGTH_BOUND for lengthLte(100) superseded by lengthLte(50)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthLte(100n).lengthLte(50n)));
    expectIssueCode(issues, "DOMINATED_LENGTH_BOUND");
  });

  test("reports REDUNDANT_LENGTH_BOUND for lengthEq(5) + lengthGte(3)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthEq(5n).lengthGte(3n)));
    expectIssueCode(issues, "REDUNDANT_LENGTH_BOUND");
  });

  test("reports IMPOSSIBLE_LENGTH_RANGE for lengthBetween(100, 50)", () => {
    // ConstraintBuilder rejects min > max, so use raw.
    const issues = PolicyValidator.validate(
      rawPolicy("bytes", Scope.CALLDATA, "0x0000", [rangeOp(Op.LENGTH_BETWEEN, 100n, 50n)]),
    );
    expectIssueCode(issues, "IMPOSSIBLE_LENGTH_RANGE");
  });

  test("negated lengthBetween(5, 10) is satisfiable, no IMPOSSIBLE_LENGTH_RANGE", () => {
    // !lengthBetween(5, 10) is (len < 5 OR len > 10), satisfiable at e.g. 3 or 11.
    const issues = PolicyValidator.validate(
      rawPolicy("bytes", Scope.CALLDATA, "0x0000", [rangeOp(Op.LENGTH_BETWEEN | Op.NOT, 5n, 10n)]),
    );
    refuteIssueCode(issues, "IMPOSSIBLE_LENGTH_RANGE");
  });

  test("negated lengthEq produces no crash and correct issues", () => {
    // No lengthNeq() method on builder — use raw operator hex.
    const issues = PolicyValidator.validate(
      rawPolicy("bytes", Scope.CALLDATA, "0x0000", [op(Op.LENGTH_EQ | Op.NOT, 5n)]),
    );
    refuteIssueCode(issues, "IMPOSSIBLE_LENGTH_RANGE");
    refuteIssueCode(issues, "CONFLICTING_LENGTH");
  });
});

///////////////////////////////////////////////////////////////////////////
// Negated Operators
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - negated operators", () => {
  test("converts !gt(v) to lte(v)", () => {
    const max256 = (1n << 256n) - 1n;
    // !gt(max) should become lte(max) which is vacuous. Builder doesn't have a negated gt,
    // so we use raw op hex.
    const issues = PolicyValidator.validate(
      rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(Op.GT | Op.NOT, max256)]),
    );
    expectIssueCode(issues, "VACUOUS_LTE");
  });

  test("converts !lt(v) to gte(v)", () => {
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(Op.LT | Op.NOT, 0n)]));
    expectIssueCode(issues, "VACUOUS_GTE");
  });
});

///////////////////////////////////////////////////////////////////////////
// Between Operator
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - between", () => {
  test("decomposes between(lo, hi) into gte(lo) + lte(hi)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).between(10n, 20n)));
    expect(issues).toHaveLength(0);
  });

  test("detects impossible between(100, 50)", () => {
    // between() rejects min > max, so use raw.
    const issues = PolicyValidator.validate(
      rawPolicy("uint256", Scope.CALLDATA, "0x0000", [rangeOp(Op.BETWEEN, 100n, 50n)]),
    );
    expectIssueCode(issues, "IMPOSSIBLE_RANGE");
  });

  test("negated between(5, 10) is satisfiable, no IMPOSSIBLE_RANGE", () => {
    // !between(5, 10) is (x < 5 OR x > 10), satisfiable at e.g. 3 or 11. The negation
    // must not distribute over the decomposed bounds as (x < 5 AND x > 10).
    const issues = PolicyValidator.validate(
      rawPolicy("uint256", Scope.CALLDATA, "0x0000", [rangeOp(Op.BETWEEN | Op.NOT, 5n, 10n)]),
    );
    refuteIssueCode(issues, "IMPOSSIBLE_RANGE");
  });
});

///////////////////////////////////////////////////////////////////////////
// Empty Group
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - empty group", () => {
  test("reports EMPTY_GROUP for group with zero constraints", () => {
    // Builder rejects empty groups, so use raw.
    const data: PolicyData = {
      isSelectorless: true,
      selector: "0x00000000",
      descriptor: bytesToHex(DescriptorCoder.fromTypes("uint256")),
      groups: [[]],
    };
    expectIssueCode(PolicyValidator.validate(data), "EMPTY_GROUP");
  });
});

///////////////////////////////////////////////////////////////////////////
// Duplicate Constraint
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - duplicate detection", () => {
  test("reports DUPLICATE_CONSTRAINT for identical operators", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).eq(5n)));
    expectIssueCode(issues, "DUPLICATE_CONSTRAINT");
  });
});

///////////////////////////////////////////////////////////////////////////
// Valid Policies
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - valid policies", () => {
  test("produces no issues for a simple eq constraint", () => {
    expect(validate("uint256", (b) => b.add(arg(0).eq(100n)))).toHaveLength(0);
  });

  test("produces no issues for a valid range constraint", () => {
    expect(validate("uint256", (b) => b.add(arg(0).between(10n, 100n)))).toHaveLength(0);
  });

  test("produces no issues for a valid isIn set", () => {
    expect(validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n])))).toHaveLength(0);
  });

  test("produces no issues for valid bitmask operators", () => {
    expect(validate("uint256", (b) => b.add(arg(0).bitmaskAll(0x0fn).bitmaskNone(0xf0n)))).toHaveLength(0);
  });

  test("produces no issues for a valid length between", () => {
    expect(validate("bytes", (b) => b.add(arg(0).lengthBetween(10n, 100n)))).toHaveLength(0);
  });
});

///////////////////////////////////////////////////////////////////////////
// Fusible Ranges
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - fusible ranges", () => {
  test("reports FUSIBLE_RANGE for gte(10) + lte(100)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(10n).lte(100n)));
    expect(issues).toHaveLength(1);
    expect(issues[0]).toMatchObject({
      code: "FUSIBLE_RANGE",
      severity: "warning",
      category: "redundancy",
      groupIndex: 0,
      constraintIndex: 0,
    });
    expect(BigInt(issues[0].value1)).toBe(10n);
    expect(BigInt(issues[0].value2)).toBe(100n);
  });

  test("reports FUSIBLE_RANGE for equal bounds gte(50) + lte(50)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(50n).lte(50n)));
    expect(issues).toHaveLength(1);
    expect(issues[0].code).toBe("FUSIBLE_RANGE");
  });

  test("reports FUSIBLE_RANGE for a satisfiable signed pair", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(-5n).lte(5n)));
    expect(issues).toHaveLength(1);
    expect(issues[0].code).toBe("FUSIBLE_RANGE");
  });

  test("reports FUSIBLE_LENGTH_RANGE for lengthGte(2) + lengthLte(8)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGte(2n).lengthLte(8n)));
    expect(issues).toHaveLength(1);
    expect(issues[0]).toMatchObject({
      code: "FUSIBLE_LENGTH_RANGE",
      severity: "warning",
      category: "redundancy",
    });
    expect(BigInt(issues[0].value1)).toBe(2n);
    expect(BigInt(issues[0].value2)).toBe(8n);
  });

  test("does not fire for strict bounds gt + lt", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gt(10n).lt(100n)));
    refuteIssueCode(issues, "FUSIBLE_RANGE");
  });

  test("does not fire for an impossible range", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(100n).lte(50n)));
    expectIssueCode(issues, "IMPOSSIBLE_RANGE");
    refuteIssueCode(issues, "FUSIBLE_RANGE");
  });

  test("does not fire for an impossible signed range", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(5n).lte(-5n)));
    expectIssueCode(issues, "IMPOSSIBLE_RANGE");
    refuteIssueCode(issues, "FUSIBLE_RANGE");
  });

  test("does not fire when the gte is negated", () => {
    const issues = PolicyValidator.validate(
      rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(Op.GTE | Op.NOT, 10n), op(Op.LTE, 100n)]),
    );
    refuteIssueCode(issues, "FUSIBLE_RANGE");
  });

  test("does not fire for a duplicated lower bound", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(5n).gte(6n).lte(10n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
    refuteIssueCode(issues, "FUSIBLE_RANGE");
  });
});

///////////////////////////////////////////////////////////////////////////
// Context Scope
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - context scope", () => {
  test("validates msg.sender as address type", () => {
    const issues = validate("uint256", (b) => b.add(msgSender().gt(42n)));
    expectIssueCode(issues, "NUMERIC_OP_ON_NON_NUMERIC");
  });

  test("allows eq on msg.sender (address)", () => {
    const issues = validate("uint256", (b) => b.add(msgSender().eq("0x0000000000000000000000000000000000000001")));
    expect(issues).toHaveLength(0);
  });

  test("allows comparison on msg.value (uint256)", () => {
    const issues = validate("uint256", (b) => b.add(msgValue().gte(100n)));
    expect(issues).toHaveLength(0);
  });

  test("throws EMPTY_PATH on a path with no step, whichever scope carries it", () => {
    const context = rawPolicy("uint256", Scope.CONTEXT, "0x", [op(Op.EQ, 1n)]);
    expectErrorCode(() => PolicyValidator.validate(context), "EMPTY_PATH");
    const calldata = rawPolicy("uint256", Scope.CALLDATA, "0x", [op(Op.EQ, 1n)]);
    expectErrorCode(() => PolicyValidator.validate(calldata), "EMPTY_PATH");
  });
});

///////////////////////////////////////////////////////////////////////////
// Cross-constraint (same path)
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - cross-constraint analysis", () => {
  test("detects contradiction across constraints on same path", () => {
    // Builder rejects duplicate paths, so use raw multiConstraintPolicy.
    const data = multiConstraintPolicy("uint256", [
      { scope: Scope.CALLDATA, path: "0x0000", operators: [op(Op.EQ, 5n)] },
      { scope: Scope.CALLDATA, path: "0x0000", operators: [op(Op.GTE, 10n)] },
    ]);
    expectIssueCode(PolicyValidator.validate(data), "BOUNDS_EXCLUDE_EQUALITY");
  });
});

///////////////////////////////////////////////////////////////////////////
// Unknown Operator
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - unknown operator", () => {
  test("reports UNKNOWN_OPERATOR for invalid opcode", () => {
    // Builder doesn't accept raw opcodes, so use raw.
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(0x30, 0n)]));
    expectIssueCode(issues, "UNKNOWN_OPERATOR");
  });

  test("reports UNKNOWN_OPERATOR for unassigned gap opcode", () => {
    // First opcode in the unassigned gap before the bitmask range.
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(0x09, 0n)]));
    expectIssueCode(issues, "UNKNOWN_OPERATOR");
  });

  test("reports UNKNOWN_OPERATOR for mismatched payload size", () => {
    // A single-operand opcode carrying a two-word payload.
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x0000", [rangeOp(Op.EQ, 0n, 0n)]));
    expectIssueCode(issues, "UNKNOWN_OPERATOR");
  });

  test("reports UNKNOWN_OPERATOR for IN payload that is not a word multiple", () => {
    const truncatedIn: Hex = `0x${Op.IN.toString(16).padStart(2, "0")}${"00".repeat(48)}`;
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x0000", [truncatedIn]));
    expectIssueCode(issues, "UNKNOWN_OPERATOR");
  });
});

///////////////////////////////////////////////////////////////////////////
// Signed Integer Boundaries
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - signed integer boundaries", () => {
  const INT256_MIN = -(1n << 255n);
  const INT256_MAX = (1n << 255n) - 1n;

  test("reports IMPOSSIBLE_GT for gt(int256.max)", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gt(INT256_MAX)));
    expectIssueCode(issues, "IMPOSSIBLE_GT");
  });

  test("reports IMPOSSIBLE_LT for lt(int256.min)", () => {
    const issues = validate("int256", (b) => b.add(arg(0).lt(INT256_MIN)));
    expectIssueCode(issues, "IMPOSSIBLE_LT");
  });

  test("reports VACUOUS_GTE for gte(int256.min)", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(INT256_MIN)));
    expectIssueCode(issues, "VACUOUS_GTE");
  });

  test("reports VACUOUS_LTE for lte(int256.max)", () => {
    const issues = validate("int256", (b) => b.add(arg(0).lte(INT256_MAX)));
    expectIssueCode(issues, "VACUOUS_LTE");
  });

  test("reports OUT_OF_PHYSICAL_BOUNDS for int8 value above max", () => {
    const issues = validate("int8", (b) => b.add(arg(0).eq(128n)));
    expectIssueCode(issues, "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("reports IMPOSSIBLE_RANGE for inverted signed bounds", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(INT256_MAX).lte(0n)));
    expectIssueCode(issues, "IMPOSSIBLE_RANGE");
  });

  test("allows valid signed range around zero", () => {
    const nearMin = INT256_MIN + 1n;
    const issues = validate("int256", (b) => b.add(arg(0).gte(nearMin).lte(INT256_MAX)));
    refuteIssueCode(issues, "IMPOSSIBLE_RANGE");
  });
});

///////////////////////////////////////////////////////////////////////////
// Between Equal Bounds
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - between equal bounds", () => {
  test("produces no contradiction for between(x, x)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).between(42n, 42n)));
    refuteIssueCode(issues, "IMPOSSIBLE_RANGE");
  });
});

///////////////////////////////////////////////////////////////////////////
// Upper Bound Domain Updates
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - upper bound domain updates", () => {
  test("reports DOMINATED_BOUND for lte(100) + lte(200) (second is weaker)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lte(100n).lte(200n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });

  test("reports DOMINATED_BOUND for lt(100) + lt(100) (duplicate)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lt(100n).lt(100n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });

  test("reports DOMINATED_BOUND when lt(50) supersedes lte(100)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lte(100n).lt(50n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });

  test("reports DOMINATED_BOUND for lte(50) + lte(50) (same inclusive)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lte(50n).lte(50n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });

  test("reports DOMINATED_BOUND when lt(50) supersedes lte(50)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lte(50n).lt(50n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });

  test("reports REDUNDANT_BOUND for eq(5) + lte(10)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).lte(10n)));
    expectIssueCode(issues, "REDUNDANT_BOUND");
  });

  test("reports BOUNDS_EXCLUDE_EQUALITY for eq(50) + lte(10)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(50n).lte(10n)));
    expectIssueCode(issues, "BOUNDS_EXCLUDE_EQUALITY");
  });

  test("reports BOUNDS_EXCLUDE_EQUALITY for eq(50) + lt(50) (exclusive upper)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(50n).lt(50n)));
    expectIssueCode(issues, "BOUNDS_EXCLUDE_EQUALITY");
  });

  test("reports DOMINATED_BOUND for lte(100) superseded by lt(50)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lte(100n).lt(50n)));
    const issue = expectIssueCode(issues, "DOMINATED_BOUND");
    expect(issue.value1).toBe("0x0000000000000000000000000000000000000000000000000000000000000064");
  });

  test("reports DOMINATED_BOUND for lt(200) superseded by lte(100)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lt(200n).lte(100n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });
});

///////////////////////////////////////////////////////////////////////////
// Signed Domain Cross-checks (signed paths)
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - signed domain cross-checks", () => {
  test("reports DOMINATED_BOUND for gte(10) + gte(5) on int256", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(10n).gte(5n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });

  test("reports IMPOSSIBLE_RANGE for inverted signed upper/lower", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(100n).lte(50n)));
    expectIssueCode(issues, "IMPOSSIBLE_RANGE");
  });

  test("reports BOUNDS_EXCLUDE_EQUALITY for eq(5) + gt(10) on int256", () => {
    const issues = validate("int256", (b) => b.add(arg(0).eq(5n).gt(10n)));
    expectIssueCode(issues, "BOUNDS_EXCLUDE_EQUALITY");
  });

  test("reports REDUNDANT_BOUND for eq(50) + lte(100) on int256", () => {
    const issues = validate("int256", (b) => b.add(arg(0).eq(50n).lte(100n)));
    expectIssueCode(issues, "REDUNDANT_BOUND");
  });

  test("reports DOMINATED_BOUND for gte(-10) superseded by gte(5) on int256", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(-10n).gte(5n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });
});

///////////////////////////////////////////////////////////////////////////
// Bitmask_none + Bitmask_any Additional Paths
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bitmask additional paths", () => {
  test("reports BITMASK_CONTRADICTION for none(0xff) + all(0xff)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskNone(0xffn).bitmaskAll(0xffn)));
    expectIssueCode(issues, "BITMASK_CONTRADICTION");
  });

  test("reports REDUNDANT_BITMASK for duplicate none", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskNone(0xffn).bitmaskNone(0x0fn)));
    expectIssueCode(issues, "REDUNDANT_BITMASK");
  });

  test("reports REDUNDANT_BITMASK for bitmaskAny subset of mustBeOne", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskAll(0xffn).bitmaskAny(0x0fn)));
    expectIssueCode(issues, "REDUNDANT_BITMASK");
  });

  test("negated bitmask operators are ignored (no crash)", () => {
    // Builder doesn't expose negated bitmask, so use raw.
    const issues = PolicyValidator.validate(
      rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(Op.BITMASK_ALL | Op.NOT, 0xffn)]),
    );
    refuteIssueCode(issues, "BITMASK_CONTRADICTION");
  });
});

///////////////////////////////////////////////////////////////////////////
// Set_excludes_equality (isIn + eq not in set)
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - set excludes equality (isIn path)", () => {
  test("reports SET_EXCLUDES_EQUALITY when eq value is not in isIn set", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(99n).isIn([1n, 2n, 3n])));
    expectIssueCode(issues, "SET_EXCLUDES_EQUALITY");
  });

  test("no issue when eq value IS in isIn set", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(2n).isIn([1n, 2n, 3n])));
    refuteIssueCode(issues, "SET_EXCLUDES_EQUALITY");
  });
});

///////////////////////////////////////////////////////////////////////////
// Lower Bound Additional Paths
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - lower bound edge cases", () => {
  test("gt at same value as existing gt is redundant", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gt(50n).gt(50n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });

  test("gt(50) then gte(50) — weaker bound is silently ignored", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gt(50n).gte(50n)));
    refuteIssueCode(issues, "IMPOSSIBLE_RANGE");
  });

  test("reports IMPOSSIBLE_RANGE for gt(50) + lt(50)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gt(50n).lt(50n)));
    expectIssueCode(issues, "IMPOSSIBLE_RANGE");
  });

  test("reports IMPOSSIBLE_RANGE for gte(50) + lt(50)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(50n).lt(50n)));
    expectIssueCode(issues, "IMPOSSIBLE_RANGE");
  });

  test("reports DOMINATED_BOUND for gt(0) superseded by gte(3)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gt(0n).gte(3n)));
    const issue = expectIssueCode(issues, "DOMINATED_BOUND");
    // value1 is the superseded bound value (0), padded to 32-byte hex.
    expect(issue.value1).toBe("0x0000000000000000000000000000000000000000000000000000000000000000");
  });

  test("reports DOMINATED_BOUND for gte(5) superseded by gt(10)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(5n).gt(10n)));
    const issue = expectIssueCode(issues, "DOMINATED_BOUND");
    expect(issue.value1).toBe("0x0000000000000000000000000000000000000000000000000000000000000005");
  });

  test("reports DOMINATED_BOUND for gte(5) superseded by gt(5) (same value, stricter)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(5n).gt(5n)));
    expectIssueCode(issues, "DOMINATED_BOUND");
  });
});

///////////////////////////////////////////////////////////////////////////
// Set_partially_excluded
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - SET_PARTIALLY_EXCLUDED", () => {
  test("reports SET_PARTIALLY_EXCLUDED when some isIn values are excluded by neq", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n]).neq(1n)));
    expectIssueCode(issues, "SET_PARTIALLY_EXCLUDED");
  });

  test("reports SET_PARTIALLY_EXCLUDED when some isIn values are excluded by notIn", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n]).notIn([1n])));
    expectIssueCode(issues, "SET_PARTIALLY_EXCLUDED");
  });
});

///////////////////////////////////////////////////////////////////////////
// Bitmask Zero Mask
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bitmask zero mask", () => {
  test("does not report BITMASK_ANY_IMPOSSIBLE for bitmaskAny with zero mask", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskAny(0n)));
    refuteIssueCode(issues, "BITMASK_ANY_IMPOSSIBLE");
  });
});

///////////////////////////////////////////////////////////////////////////
// Duplicate Neq Deduplication
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - duplicate neq deduplication", () => {
  test("silently deduplicates identical neq values", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).neq(5n).neq(5n)));
    expectIssueCode(issues, "DUPLICATE_CONSTRAINT");
  });
});

///////////////////////////////////////////////////////////////////////////
// Neq Then Eq Contradiction
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - neq then eq contradiction", () => {
  test("reports EQ_NEQ_CONTRADICTION when eq value is in holes from prior neq", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).neq(5n).eq(5n)));
    expectIssueCode(issues, "EQ_NEQ_CONTRADICTION");
  });
});

///////////////////////////////////////////////////////////////////////////
// Length Domain: Bounds Exclude Length
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - length bounds exclude equality", () => {
  test("reports BOUNDS_EXCLUDE_LENGTH for lengthGt(10) + lengthEq(5)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGt(10n).lengthEq(5n)));
    expectIssueCode(issues, "BOUNDS_EXCLUDE_LENGTH");
  });
});

///////////////////////////////////////////////////////////////////////////
// Length Domain: Out Of Physical Length Bounds
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - out of physical length bounds", () => {
  test("reports OUT_OF_PHYSICAL_LENGTH_BOUNDS for lengthEq beyond uint32 max", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthEq((1n << 32n) + 1n)));
    expectIssueCode(issues, "OUT_OF_PHYSICAL_LENGTH_BOUNDS");
  });
});

///////////////////////////////////////////////////////////////////////////
// Unbounded Exclusion Tracking
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - unbounded exclusion tracking", () => {
  test("detects SET_FULLY_EXCLUDED with many neq holes", () => {
    const issues = validate("uint256", (b) => {
      const c = arg(0).isIn([1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n, 10n]);
      for (let i = 1; i <= 10; i++) c.neq(BigInt(i));
      b.add(c);
    });
    expectIssueCode(issues, "SET_FULLY_EXCLUDED");
  });

  test("detects SET_FULLY_EXCLUDED with a large notIn set", () => {
    const issues = validate("uint256", (b) => {
      b.add(arg(0).isIn([1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n, 10n]).notIn([1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n, 10n]));
    });
    expectIssueCode(issues, "SET_FULLY_EXCLUDED");
  });
});

///////////////////////////////////////////////////////////////////////////
// Unnavigable paths
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - unnavigable paths", () => {
  test("reports UNNAVIGABLE_PATH for an out-of-bounds arg index", () => {
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x0002", [op(Op.EQ, 1n)]));
    expect(issues).toHaveLength(1);
    const issue = issues[0];
    expect(issue.code).toBe("UNNAVIGABLE_PATH");
    expect(issue.severity).toBe("error");
    expect(issue.category).toBe("typeMismatch");
  });

  test("reports UNNAVIGABLE_PATH for an out-of-bounds tuple field", () => {
    const issues = PolicyValidator.validate(rawPolicy("(uint256)", Scope.CALLDATA, "0x00000005", [op(Op.EQ, 1n)]));
    expectIssueCode(issues, "UNNAVIGABLE_PATH");
  });

  test("reports UNNAVIGABLE_PATH for an out-of-bounds static array index", () => {
    const issues = PolicyValidator.validate(rawPolicy("uint256[3]", Scope.CALLDATA, "0x00000003", [op(Op.EQ, 1n)]));
    expectIssueCode(issues, "UNNAVIGABLE_PATH");
  });

  test("reports UNNAVIGABLE_PATH for a descent into an elementary type", () => {
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x00000000", [op(Op.EQ, 1n)]));
    expectIssueCode(issues, "UNNAVIGABLE_PATH");
  });

  test("collects other issues alongside UNNAVIGABLE_PATH", () => {
    const issues = PolicyValidator.validate(
      multiConstraintPolicy("uint256", [
        { scope: Scope.CALLDATA, path: "0x0000", operators: [op(Op.LENGTH_EQ, 5n)] },
        { scope: Scope.CALLDATA, path: "0x0002", operators: [op(Op.EQ, 1n)] },
      ]),
    );
    expect(issues).toHaveLength(2);
    expectIssueCode(issues, "LENGTH_ON_STATIC");
    expectIssueCode(issues, "UNNAVIGABLE_PATH");
  });
});

///////////////////////////////////////////////////////////////////////////
// Malformed descriptors
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - malformed descriptors", () => {
  const constraint: Constraint = { scope: Scope.CALLDATA, path: "0x0000", operators: [op(Op.EQ, 1n)] };

  test("throws on an unassigned type code", () => {
    const unassigned = (TypeCode.TUPLE + 1).toString(16).padStart(2, "0");
    const data: PolicyData = {
      isSelectorless: true,
      selector: "0x00000000",
      descriptor: `0x0201${unassigned}`,
      groups: [[constraint]],
    };
    expect(() => PolicyValidator.validate(data)).toThrow(CallciumError);
  });

  test("throws on trailing descriptor bytes", () => {
    const data: PolicyData = {
      isSelectorless: true,
      selector: "0x00000000",
      descriptor: "0x02014141",
      groups: [[constraint]],
    };
    expect(() => PolicyValidator.validate(data)).toThrow(CallciumError);
  });
});

///////////////////////////////////////////////////////////////////////////
// Malformed operators
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - malformed operators", () => {
  test("throws INVALID_HEX on non-hex operator characters", () => {
    const opcode = rawPolicy("uint256", Scope.CALLDATA, "0x0000", ["0xzz"]);
    expectErrorCode(() => PolicyValidator.validate(opcode), "INVALID_HEX");
    const payload = rawPolicy("uint256", Scope.CALLDATA, "0x0000", [`0x01${"zz".repeat(32)}`]);
    expectErrorCode(() => PolicyValidator.validate(payload), "INVALID_HEX");
  });

  test("throws INVALID_OPERATOR_BYTES on an operator carrying no opcode", () => {
    const data = rawPolicy("uint256", Scope.CALLDATA, "0x0000", ["0x"]);
    expectErrorCode(() => PolicyValidator.validate(data), "INVALID_OPERATOR_BYTES");
  });
});

///////////////////////////////////////////////////////////////////////////
// Hint mismatch (PV-6)
///////////////////////////////////////////////////////////////////////////

describe("hint mismatch", () => {
  /** Build policy data for `foo(uint256)` whose single constraint carries `hint`. */
  function withHint(hint?: Hex): PolicyData {
    const constraint: Constraint = { scope: Scope.CALLDATA, path: "0x0000", operators: [op(Op.EQ, 1n)] };
    if (hint !== undefined) constraint.hint = hint;
    return {
      isSelectorless: true,
      selector: "0x00000000",
      descriptor: bytesToHex(DescriptorCoder.fromTypes("uint256")),
      groups: [[constraint]],
    };
  }

  test("matching hint reports no issue", () => {
    refuteIssueCode(PolicyValidator.validate(withHint("0x0000000000000020")), "HINT_MISMATCH");
  });

  test("absent hint reports no issue", () => {
    refuteIssueCode(PolicyValidator.validate(withHint()), "HINT_MISMATCH");
  });

  test("empty hint reports no issue", () => {
    refuteIssueCode(PolicyValidator.validate(withHint("0x")), "HINT_MISMATCH");
  });

  test("divergent target delta reports an error", () => {
    const issues = PolicyValidator.validate(withHint("0x0000000020000020"));
    const issue = expectIssueCode(issues, "HINT_MISMATCH");
    expect(issue.severity).toBe("error");
    expect(issue.category).toBe("typeMismatch");
    expect(issue.groupIndex).toBe(0);
    expect(issue.constraintIndex).toBe(0);
  });

  test("spurious hop reports an error", () => {
    expectIssueCode(PolicyValidator.validate(withHint("0x0100000000ffff000000000000000020")), "HINT_MISMATCH");
  });

  test("unnavigable path reports the path alone", () => {
    // Compilation is undefined for a path the descriptor rejects, so no hint comparison runs.
    const data = withHint("0x0000000000000020");
    data.groups[0][0].path = "0x0003";
    const issues = PolicyValidator.validate(data);
    refuteIssueCode(issues, "HINT_MISMATCH");
    expectIssueCode(issues, "UNNAVIGABLE_PATH");
  });

  test("context constraint hint is ignored", () => {
    const data = withHint();
    data.groups[0][0] = { scope: Scope.CONTEXT, path: "0x0000", operators: [op(Op.EQ, 1n)], hint: "0x0000000020" };
    refuteIssueCode(PolicyValidator.validate(data), "HINT_MISMATCH");
  });
});

///////////////////////////////////////////////////////////////////////////
// Context reference operator (EQ_CTX)
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - EQ_CTX", () => {
  test("address target with an address property has no issues", () => {
    const issues = PolicyValidator.validate(
      rawPolicy("address", Scope.CALLDATA, "0x0000", [op(Op.EQ_CTX, BigInt(ContextProperty.MSG_SENDER))]),
    );
    expect(issues).toHaveLength(0);
  });

  test("uint target with a uint256 property has no issues", () => {
    const issues = PolicyValidator.validate(
      rawPolicy("uint128", Scope.CALLDATA, "0x0000", [op(Op.EQ_CTX, BigInt(ContextProperty.BLOCK_TIMESTAMP))]),
    );
    expect(issues).toHaveLength(0);
  });

  test("context subject with a context operand has no issues", () => {
    const issues = PolicyValidator.validate(
      rawPolicy("uint256", Scope.CONTEXT, "0x0000", [op(Op.EQ_CTX, BigInt(ContextProperty.TX_ORIGIN))]),
    );
    expect(issues).toHaveLength(0);
  });

  test("uint target with an address property reports CONTEXT_TYPE_MISMATCH", () => {
    const issues = PolicyValidator.validate(
      rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(Op.EQ_CTX, BigInt(ContextProperty.MSG_SENDER))]),
    );
    expectIssueCode(issues, "CONTEXT_TYPE_MISMATCH");
  });

  test("address target with a uint256 property reports CONTEXT_TYPE_MISMATCH", () => {
    const issues = PolicyValidator.validate(
      rawPolicy("address", Scope.CALLDATA, "0x0000", [op(Op.EQ_CTX, BigInt(ContextProperty.MSG_VALUE))]),
    );
    expectIssueCode(issues, "CONTEXT_TYPE_MISMATCH");
  });

  test("signed target reports CONTEXT_TYPE_MISMATCH", () => {
    const issues = PolicyValidator.validate(
      rawPolicy("int256", Scope.CALLDATA, "0x0000", [op(Op.EQ_CTX, BigInt(ContextProperty.MSG_VALUE))]),
    );
    expectIssueCode(issues, "CONTEXT_TYPE_MISMATCH");
  });

  test("unknown property operand reports UNKNOWN_CONTEXT_PROPERTY without a pairing verdict", () => {
    const issues = PolicyValidator.validate(
      rawPolicy("address", Scope.CALLDATA, "0x0000", [op(Op.EQ_CTX, BigInt(MAX_CONTEXT_PROPERTY_ID + 1))]),
    );
    const issue = expectIssueCode(issues, "UNKNOWN_CONTEXT_PROPERTY");
    expect(issue.severity).toBe("warning");
    refuteIssueCode(issues, "CONTEXT_TYPE_MISMATCH");
  });
});

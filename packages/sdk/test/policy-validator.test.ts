import { describe, expect, test } from "vitest";

import { PolicyBuilder, arg, msgSender, msgValue, Op, Scope } from "../src";
import { DescriptorBuilder } from "../src/descriptor-builder";
import { bytesToHex } from "../src/hex";
import { PolicyValidator } from "../src/policy-validator";
import { op, rangeOp, inOp } from "./helpers";

import type { Hex, Issue, PolicyData } from "../src/types";

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
    descriptor: bytesToHex(DescriptorBuilder.fromTypes(typesCsv)),
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
    descriptor: bytesToHex(DescriptorBuilder.fromTypes(typesCsv)),
    groups: [constraints],
  };
}

/** Validate via PolicyBuilder and return issues. */
function validate(typesCsv: string, build: (b: ReturnType<typeof PolicyBuilder.createRaw>) => void): Issue[] {
  const builder = PolicyBuilder.createRaw(typesCsv);
  build(builder);
  return builder.validate();
}

/** Find issue by code. */
function findIssue(issues: Issue[], code: string) {
  return issues.find((i) => i.code === code);
}

///////////////////////////////////////////////////////////////////////////
// Type Compatibility
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - type compatibility", () => {
  test("reports VALUE_OP_ON_DYNAMIC for eq on bytes", () => {
    // Builder rejects this at add() time, so use raw.
    const issues = PolicyValidator.validate(rawPolicy("bytes", Scope.CALLDATA, "0x0000", [op(Op.EQ, 42n)]));
    expect(findIssue(issues, "VALUE_OP_ON_DYNAMIC")).toBeDefined();
  });

  test("reports NUMERIC_OP_ON_NON_NUMERIC for gt on address", () => {
    const issues = validate("address", (b) => b.add(arg(0).gt(42n)));
    expect(findIssue(issues, "NUMERIC_OP_ON_NON_NUMERIC")).toBeDefined();
  });

  test("reports BITMASK_ON_INVALID for bitmask on int256", () => {
    const issues = validate("int256", (b) => b.add(arg(0).bitmaskAll(0xffn)));
    expect(findIssue(issues, "BITMASK_ON_INVALID")).toBeDefined();
  });

  test("reports LENGTH_ON_STATIC for lengthEq on uint256", () => {
    // Builder rejects LENGTH on static types, so use raw.
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(Op.LENGTH_EQ, 5n)]));
    expect(findIssue(issues, "LENGTH_ON_STATIC")).toBeDefined();
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
// Bound Contradictions
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bound contradictions", () => {
  test("reports CONFLICTING_EQUALITY for eq(5) + eq(10)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).eq(10n)));
    expect(findIssue(issues, "CONFLICTING_EQUALITY")).toBeDefined();
  });

  test("reports EQ_NEQ_CONTRADICTION for eq(5) + neq(5)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).neq(5n)));
    expect(findIssue(issues, "EQ_NEQ_CONTRADICTION")).toBeDefined();
  });

  test("reports IMPOSSIBLE_GT for gt(uint256.max)", () => {
    const max256 = (1n << 256n) - 1n;
    const issues = validate("uint256", (b) => b.add(arg(0).gt(max256)));
    expect(findIssue(issues, "IMPOSSIBLE_GT")).toBeDefined();
  });

  test("reports IMPOSSIBLE_LT for lt(0) on uint256", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lt(0n)));
    expect(findIssue(issues, "IMPOSSIBLE_LT")).toBeDefined();
  });

  test("reports IMPOSSIBLE_RANGE for gte(100) + lte(50)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(100n).lte(50n)));
    expect(findIssue(issues, "IMPOSSIBLE_RANGE")).toBeDefined();
  });

  test("reports BOUNDS_EXCLUDE_EQUALITY for eq(5) + gte(10)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).gte(10n)));
    expect(findIssue(issues, "BOUNDS_EXCLUDE_EQUALITY")).toBeDefined();
  });

  test("reports OUT_OF_PHYSICAL_BOUNDS for uint8 value > 255", () => {
    const issues = validate("uint8", (b) => b.add(arg(0).eq(256n)));
    expect(findIssue(issues, "OUT_OF_PHYSICAL_BOUNDS")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Bound Redundancy
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bound redundancy", () => {
  test("reports DOMINATED_BOUND for gte(10) + gte(5)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(10n).gte(5n)));
    expect(findIssue(issues, "DOMINATED_BOUND")).toBeDefined();
  });

  test("reports REDUNDANT_BOUND for eq(5) + gte(3)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).gte(3n)));
    expect(findIssue(issues, "REDUNDANT_BOUND")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Bound Vacuity
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bound vacuity", () => {
  test("reports VACUOUS_GTE for gte(0) on uint256", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(0n)));
    expect(findIssue(issues, "VACUOUS_GTE")).toBeDefined();
  });

  test("reports VACUOUS_LTE for lte(uint256.max)", () => {
    const max256 = (1n << 256n) - 1n;
    const issues = validate("uint256", (b) => b.add(arg(0).lte(max256)));
    expect(findIssue(issues, "VACUOUS_LTE")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Bitmask
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bitmask", () => {
  test("reports BITMASK_CONTRADICTION for all(0xff) + none(0xff)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskAll(0xffn).bitmaskNone(0xffn)));
    expect(findIssue(issues, "BITMASK_CONTRADICTION")).toBeDefined();
  });

  test("reports BITMASK_ANY_IMPOSSIBLE when all bits forbidden", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskNone(0xffn).bitmaskAny(0xffn)));
    expect(findIssue(issues, "BITMASK_ANY_IMPOSSIBLE")).toBeDefined();
  });

  test("reports REDUNDANT_BITMASK for duplicate all", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskAll(0xffn).bitmaskAll(0x0fn)));
    expect(findIssue(issues, "REDUNDANT_BITMASK")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Set
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - set", () => {
  test("reports EMPTY_SET_INTERSECTION for disjoint isIn sets", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n]).isIn([4n, 5n, 6n])));
    expect(findIssue(issues, "EMPTY_SET_INTERSECTION")).toBeDefined();
  });

  test("reports SET_FULLY_EXCLUDED when all isIn values are excluded", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n]).notIn([1n, 2n])));
    expect(findIssue(issues, "SET_FULLY_EXCLUDED")).toBeDefined();
  });

  test("reports UNSORTED_IN_SET for unsorted set", () => {
    // Builder auto-sorts, so use raw with pre-built unsorted operator hex.
    const issues = PolicyValidator.validate(
      rawPolicy("uint256", Scope.CALLDATA, "0x0000", [inOp(Op.IN, [3n, 1n, 2n])]),
    );
    expect(findIssue(issues, "UNSORTED_IN_SET")).toBeDefined();
  });

  test("reports SET_EXCLUDES_EQUALITY when notIn excludes eq value", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).notIn([5n])));
    expect(findIssue(issues, "SET_EXCLUDES_EQUALITY")).toBeDefined();
  });

  test("reports SET_REDUNDANCY for partially overlapping isIn sets", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n]).isIn([2n, 3n, 4n])));
    expect(findIssue(issues, "SET_REDUNDANCY")).toBeDefined();
  });

  test("reports SET_REDUCTION when notIn value is in isIn set", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n]).notIn([2n])));
    expect(findIssue(issues, "SET_REDUCTION")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Length
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - length domain", () => {
  test("reports CONFLICTING_LENGTH for lengthEq(5) + lengthEq(10)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthEq(5n).lengthEq(10n)));
    expect(findIssue(issues, "CONFLICTING_LENGTH")).toBeDefined();
  });

  test("reports IMPOSSIBLE_LENGTH_GT for lengthGt(uint32.max)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGt(0xffffffffn)));
    expect(findIssue(issues, "IMPOSSIBLE_LENGTH_GT")).toBeDefined();
  });

  test("reports IMPOSSIBLE_LENGTH_LT for lengthLt(0)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthLt(0n)));
    expect(findIssue(issues, "IMPOSSIBLE_LENGTH_LT")).toBeDefined();
  });

  test("reports VACUOUS_LENGTH_GTE for lengthGte(0)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGte(0n)));
    expect(findIssue(issues, "VACUOUS_LENGTH_GTE")).toBeDefined();
  });

  test("reports VACUOUS_LENGTH_LTE for lengthLte(uint32.max)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthLte(0xffffffffn)));
    expect(findIssue(issues, "VACUOUS_LENGTH_LTE")).toBeDefined();
  });

  test("reports IMPOSSIBLE_LENGTH_RANGE for lengthGte(100) + lengthLte(50)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGte(100n).lengthLte(50n)));
    expect(findIssue(issues, "IMPOSSIBLE_LENGTH_RANGE")).toBeDefined();
  });

  test("reports LENGTH_EQ_NEQ_CONTRADICTION for lengthEq(5) + !lengthEq(5)", () => {
    // No lengthNeq() method on builder — use raw operator hex.
    const issues = PolicyValidator.validate(
      rawPolicy("bytes", Scope.CALLDATA, "0x0000", [op(Op.LENGTH_EQ, 5n), op(Op.LENGTH_EQ | Op.NOT, 5n)]),
    );
    expect(findIssue(issues, "LENGTH_EQ_NEQ_CONTRADICTION")).toBeDefined();
  });

  test("handles LENGTH_BETWEEN correctly", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthBetween(10n, 20n)));
    expect(issues).toHaveLength(0);
  });

  test("reports DOMINATED_LENGTH_BOUND for lengthGte(10) + lengthGte(5)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGte(10n).lengthGte(5n)));
    expect(findIssue(issues, "DOMINATED_LENGTH_BOUND")).toBeDefined();
  });

  test("reports REDUNDANT_LENGTH_BOUND for lengthEq(5) + lengthGte(3)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthEq(5n).lengthGte(3n)));
    expect(findIssue(issues, "REDUNDANT_LENGTH_BOUND")).toBeDefined();
  });

  test("reports IMPOSSIBLE_LENGTH_RANGE for lengthBetween(100, 50)", () => {
    // ConstraintBuilder rejects min > max, so use raw.
    const issues = PolicyValidator.validate(
      rawPolicy("bytes", Scope.CALLDATA, "0x0000", [rangeOp(Op.LENGTH_BETWEEN, 100n, 50n)]),
    );
    expect(findIssue(issues, "IMPOSSIBLE_LENGTH_RANGE")).toBeDefined();
  });

  test("negated lengthEq produces no crash and correct issues", () => {
    // No lengthNeq() method on builder — use raw operator hex.
    const issues = PolicyValidator.validate(
      rawPolicy("bytes", Scope.CALLDATA, "0x0000", [op(Op.LENGTH_EQ | Op.NOT, 5n)]),
    );
    expect(findIssue(issues, "IMPOSSIBLE_LENGTH_RANGE")).toBeUndefined();
    expect(findIssue(issues, "CONFLICTING_LENGTH")).toBeUndefined();
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
    expect(findIssue(issues, "VACUOUS_LTE")).toBeDefined();
  });

  test("converts !lt(v) to gte(v)", () => {
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(Op.LT | Op.NOT, 0n)]));
    expect(findIssue(issues, "VACUOUS_GTE")).toBeDefined();
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
    expect(findIssue(issues, "IMPOSSIBLE_RANGE")).toBeDefined();
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
      descriptor: bytesToHex(DescriptorBuilder.fromTypes("uint256")),
      groups: [[]],
    };
    expect(findIssue(PolicyValidator.validate(data), "EMPTY_GROUP")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Duplicate Constraint
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - duplicate detection", () => {
  test("reports DUPLICATE_CONSTRAINT for identical operators", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).eq(5n)));
    expect(findIssue(issues, "DUPLICATE_CONSTRAINT")).toBeDefined();
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
    expect(validate("uint256", (b) => b.add(arg(0).gte(10n).lte(100n)))).toHaveLength(0);
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
// Context Scope
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - context scope", () => {
  test("validates msg.sender as address type", () => {
    const issues = validate("uint256", (b) => b.add(msgSender().gt(42n)));
    expect(findIssue(issues, "NUMERIC_OP_ON_NON_NUMERIC")).toBeDefined();
  });

  test("allows eq on msg.sender (address)", () => {
    const issues = validate("uint256", (b) => b.add(msgSender().eq("0x0000000000000000000000000000000000000001")));
    expect(issues).toHaveLength(0);
  });

  test("allows comparison on msg.value (uint256)", () => {
    const issues = validate("uint256", (b) => b.add(msgValue().gte(100n)));
    expect(issues).toHaveLength(0);
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
    expect(findIssue(PolicyValidator.validate(data), "BOUNDS_EXCLUDE_EQUALITY")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Unknown Operator
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - unknown operator", () => {
  test("reports UNKNOWN_OPERATOR for invalid opcode", () => {
    // Builder doesn't accept raw opcodes, so use raw.
    const issues = PolicyValidator.validate(rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(0x30, 0n)]));
    expect(findIssue(issues, "UNKNOWN_OPERATOR")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Signed Integer Boundaries
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - signed integer boundaries", () => {
  const INT256_MIN = 1n << 255n;
  const INT256_MAX = (1n << 255n) - 1n;

  test("reports IMPOSSIBLE_GT for gt(int256.max)", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gt(INT256_MAX)));
    expect(findIssue(issues, "IMPOSSIBLE_GT")).toBeDefined();
  });

  test("reports IMPOSSIBLE_LT for lt(int256.min)", () => {
    const issues = validate("int256", (b) => b.add(arg(0).lt(INT256_MIN)));
    expect(findIssue(issues, "IMPOSSIBLE_LT")).toBeDefined();
  });

  test("reports VACUOUS_GTE for gte(int256.min)", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(INT256_MIN)));
    expect(findIssue(issues, "VACUOUS_GTE")).toBeDefined();
  });

  test("reports VACUOUS_LTE for lte(int256.max)", () => {
    const issues = validate("int256", (b) => b.add(arg(0).lte(INT256_MAX)));
    expect(findIssue(issues, "VACUOUS_LTE")).toBeDefined();
  });

  test("reports OUT_OF_PHYSICAL_BOUNDS for int8 value above max", () => {
    const issues = validate("int8", (b) => b.add(arg(0).eq(128n)));
    expect(findIssue(issues, "OUT_OF_PHYSICAL_BOUNDS")).toBeDefined();
  });

  test("reports IMPOSSIBLE_RANGE for inverted signed bounds", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(INT256_MAX).lte(0n)));
    expect(findIssue(issues, "IMPOSSIBLE_RANGE")).toBeDefined();
  });

  test("allows valid signed range around zero", () => {
    const nearMin = INT256_MIN + 1n;
    const issues = validate("int256", (b) => b.add(arg(0).gte(nearMin).lte(INT256_MAX)));
    expect(findIssue(issues, "IMPOSSIBLE_RANGE")).toBeUndefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Between Equal Bounds
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - between equal bounds", () => {
  test("produces no contradiction for between(x, x)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).between(42n, 42n)));
    expect(findIssue(issues, "IMPOSSIBLE_RANGE")).toBeUndefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Upper Bound Domain Updates
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - upper bound domain updates", () => {
  test("reports DOMINATED_BOUND for lte(100) + lte(200) (second is weaker)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lte(100n).lte(200n)));
    expect(findIssue(issues, "DOMINATED_BOUND")).toBeDefined();
  });

  test("reports DOMINATED_BOUND for lt(100) + lt(100) (duplicate)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lt(100n).lt(100n)));
    expect(findIssue(issues, "DOMINATED_BOUND")).toBeDefined();
  });

  test("tightens upper bound when lt(50) follows lte(100)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lte(100n).lt(50n)));
    expect(findIssue(issues, "DOMINATED_BOUND")).toBeUndefined();
  });

  test("reports DOMINATED_BOUND for lte(50) + lte(50) (same inclusive)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lte(50n).lte(50n)));
    expect(findIssue(issues, "DOMINATED_BOUND")).toBeDefined();
  });

  test("lt replaces lte at same value (strictly better upper bound)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).lte(50n).lt(50n)));
    expect(findIssue(issues, "DOMINATED_BOUND")).toBeUndefined();
  });

  test("reports REDUNDANT_BOUND for eq(5) + lte(10)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(5n).lte(10n)));
    expect(findIssue(issues, "REDUNDANT_BOUND")).toBeDefined();
  });

  test("reports BOUNDS_EXCLUDE_EQUALITY for eq(50) + lte(10)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(50n).lte(10n)));
    expect(findIssue(issues, "BOUNDS_EXCLUDE_EQUALITY")).toBeDefined();
  });

  test("reports BOUNDS_EXCLUDE_EQUALITY for eq(50) + lt(50) (exclusive upper)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(50n).lt(50n)));
    expect(findIssue(issues, "BOUNDS_EXCLUDE_EQUALITY")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Signed Domain Cross-checks (signed paths)
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - signed domain cross-checks", () => {
  test("reports DOMINATED_BOUND for gte(10) + gte(5) on int256", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(10n).gte(5n)));
    expect(findIssue(issues, "DOMINATED_BOUND")).toBeDefined();
  });

  test("reports IMPOSSIBLE_RANGE for inverted signed upper/lower", () => {
    const issues = validate("int256", (b) => b.add(arg(0).gte(100n).lte(50n)));
    expect(findIssue(issues, "IMPOSSIBLE_RANGE")).toBeDefined();
  });

  test("reports BOUNDS_EXCLUDE_EQUALITY for eq(5) + gt(10) on int256", () => {
    const issues = validate("int256", (b) => b.add(arg(0).eq(5n).gt(10n)));
    expect(findIssue(issues, "BOUNDS_EXCLUDE_EQUALITY")).toBeDefined();
  });

  test("reports REDUNDANT_BOUND for eq(50) + lte(100) on int256", () => {
    const issues = validate("int256", (b) => b.add(arg(0).eq(50n).lte(100n)));
    expect(findIssue(issues, "REDUNDANT_BOUND")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Bitmask_none + Bitmask_any Additional Paths
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bitmask additional paths", () => {
  test("reports BITMASK_CONTRADICTION for none(0xff) + all(0xff)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskNone(0xffn).bitmaskAll(0xffn)));
    expect(findIssue(issues, "BITMASK_CONTRADICTION")).toBeDefined();
  });

  test("reports REDUNDANT_BITMASK for duplicate none", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskNone(0xffn).bitmaskNone(0x0fn)));
    expect(findIssue(issues, "REDUNDANT_BITMASK")).toBeDefined();
  });

  test("reports REDUNDANT_BITMASK for bitmaskAny subset of mustBeOne", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskAll(0xffn).bitmaskAny(0x0fn)));
    expect(findIssue(issues, "REDUNDANT_BITMASK")).toBeDefined();
  });

  test("negated bitmask operators are ignored (no crash)", () => {
    // Builder doesn't expose negated bitmask, so use raw.
    const issues = PolicyValidator.validate(
      rawPolicy("uint256", Scope.CALLDATA, "0x0000", [op(Op.BITMASK_ALL | Op.NOT, 0xffn)]),
    );
    expect(findIssue(issues, "BITMASK_CONTRADICTION")).toBeUndefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Set_excludes_equality (isIn + eq not in set)
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - set excludes equality (isIn path)", () => {
  test("reports SET_EXCLUDES_EQUALITY when eq value is not in isIn set", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(99n).isIn([1n, 2n, 3n])));
    expect(findIssue(issues, "SET_EXCLUDES_EQUALITY")).toBeDefined();
  });

  test("no issue when eq value IS in isIn set", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).eq(2n).isIn([1n, 2n, 3n])));
    expect(findIssue(issues, "SET_EXCLUDES_EQUALITY")).toBeUndefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Lower Bound Additional Paths
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - lower bound edge cases", () => {
  test("gt at same value as existing gt is redundant", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gt(50n).gt(50n)));
    expect(findIssue(issues, "DOMINATED_BOUND")).toBeDefined();
  });

  test("gt(50) then gte(50) — weaker bound is silently ignored", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gt(50n).gte(50n)));
    expect(findIssue(issues, "IMPOSSIBLE_RANGE")).toBeUndefined();
  });

  test("reports IMPOSSIBLE_RANGE for gt(50) + lt(50)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gt(50n).lt(50n)));
    expect(findIssue(issues, "IMPOSSIBLE_RANGE")).toBeDefined();
  });

  test("reports IMPOSSIBLE_RANGE for gte(50) + lt(50)", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).gte(50n).lt(50n)));
    expect(findIssue(issues, "IMPOSSIBLE_RANGE")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Set_partially_excluded
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - SET_PARTIALLY_EXCLUDED", () => {
  test("reports SET_PARTIALLY_EXCLUDED when some isIn values are excluded by neq", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n]).neq(1n)));
    expect(findIssue(issues, "SET_PARTIALLY_EXCLUDED")).toBeDefined();
  });

  test("reports SET_PARTIALLY_EXCLUDED when some isIn values are excluded by notIn", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).isIn([1n, 2n, 3n]).notIn([1n])));
    expect(findIssue(issues, "SET_PARTIALLY_EXCLUDED")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Bitmask Zero Mask
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - bitmask zero mask", () => {
  test("does not report BITMASK_ANY_IMPOSSIBLE for bitmaskAny with zero mask", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).bitmaskAny(0n)));
    expect(findIssue(issues, "BITMASK_ANY_IMPOSSIBLE")).toBeUndefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Duplicate Neq Deduplication
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - duplicate neq deduplication", () => {
  test("silently deduplicates identical neq values", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).neq(5n).neq(5n)));
    expect(findIssue(issues, "DUPLICATE_CONSTRAINT")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Neq Then Eq Contradiction
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - neq then eq contradiction", () => {
  test("reports EQ_NEQ_CONTRADICTION when eq value is in holes from prior neq", () => {
    const issues = validate("uint256", (b) => b.add(arg(0).neq(5n).eq(5n)));
    expect(findIssue(issues, "EQ_NEQ_CONTRADICTION")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Length Domain: Bounds Exclude Length
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - length bounds exclude equality", () => {
  test("reports BOUNDS_EXCLUDE_LENGTH for lengthGt(10) + lengthEq(5)", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthGt(10n).lengthEq(5n)));
    expect(findIssue(issues, "BOUNDS_EXCLUDE_LENGTH")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// Length Domain: Out Of Physical Length Bounds
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - out of physical length bounds", () => {
  test("reports OUT_OF_PHYSICAL_LENGTH_BOUNDS for lengthEq beyond uint32 max", () => {
    const issues = validate("bytes", (b) => b.add(arg(0).lengthEq((1n << 32n) + 1n)));
    expect(findIssue(issues, "OUT_OF_PHYSICAL_LENGTH_BOUNDS")).toBeDefined();
  });
});

///////////////////////////////////////////////////////////////////////////
// NEQ / NOT_IN Cap At 8
///////////////////////////////////////////////////////////////////////////

describe("PolicyValidator - exclusion caps", () => {
  test("silently drops neq holes beyond MAX_HOLES (8)", () => {
    const issues = validate("uint256", (b) => {
      const c = arg(0).isIn([1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n, 10n]);
      for (let i = 1; i <= 9; i++) c.neq(BigInt(i));
      b.add(c);
    });
    expect(findIssue(issues, "SET_FULLY_EXCLUDED")).toBeUndefined();
    expect(findIssue(issues, "SET_PARTIALLY_EXCLUDED")).toBeDefined();
  });

  test("silently drops notIn values beyond MAX_NOT_IN (8)", () => {
    const issues = validate("uint256", (b) => {
      b.add(arg(0).isIn([1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n, 10n]).notIn([1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n]));
    });
    expect(findIssue(issues, "SET_FULLY_EXCLUDED")).toBeUndefined();
    expect(findIssue(issues, "SET_PARTIALLY_EXCLUDED")).toBeDefined();
  });
});

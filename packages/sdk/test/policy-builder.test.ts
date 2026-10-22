import { describe, expect, test } from "vitest";

import { hexToBytes } from "../src/bytes";
import { ContextProperty, fieldMax, LoopQuantifier, Op, PolicyFormat as PF, Scope, Source } from "../src/constants";
import { arg, ConstraintBuilder, msgValue } from "../src/constraint";
import { ValidationError } from "../src/errors";
import { encodePath, Quantifier } from "../src/path";
import { PolicyBuilder } from "../src/policy-builder";
import { PolicyCoder } from "../src/policy-coder";
import { expectErrorCode, op } from "./helpers";

import type { Constraint } from "../src/types";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** A calldata constraint at `steps` carrying one equality, its path taken as given. */
function constraintAt(steps: number[]): Constraint {
  return new ConstraintBuilder(Scope.CALLDATA, encodePath(steps)).eq(1n);
}

/** A context constraint at `steps` carrying one equality, its path taken as given. */
function contextAt(steps: number[]): Constraint {
  return { scope: Scope.CONTEXT, path: encodePath(steps), operators: [op(Op.EQ, 1n)] };
}

/** `count` distinct ascending values. */
function values(count: number): bigint[] {
  return Array.from({ length: count }, (_, index) => BigInt(index));
}

/** The largest set of 32-byte members the rule's data length holds. */
const WORD_SET_LIMIT = Math.floor(fieldMax(PF.RULE_DATALENGTH_SIZE) / 32);

///////////////////////////////////////////////////////////////////////////
// Path faults
///////////////////////////////////////////////////////////////////////////

describe("PolicyBuilder.add path faults", () => {
  test("rejects a parameter index past the parameter count", () => {
    const builder = PolicyBuilder.create("bar(address,uint256)");
    expectErrorCode(() => builder.add(arg(2).eq(1n)), "PARAM_INDEX_OUT_OF_BOUNDS");
  });

  test("rejects a static array index past the declared length", () => {
    const builder = PolicyBuilder.create("foo(address[3])");
    expectErrorCode(() => builder.add(arg(0, 3).eq(1n)), "STATIC_ARRAY_INDEX_OUT_OF_BOUNDS");
  });

  test("rejects a step into an elementary type", () => {
    const builder = PolicyBuilder.create("foo(uint256)");
    expectErrorCode(() => builder.add(arg(0, 0).eq(1n)), "NOT_COMPOSITE");
  });

  test("rejects a quantifier on a node that is not an array", () => {
    const builder = PolicyBuilder.create("foo((address,uint256))");
    expectErrorCode(() => builder.add(arg(0, Quantifier.ALL).eq(1n)), "QUANTIFIER_ON_NON_ARRAY");
  });

  test("names a body step by its index in the whole path", () => {
    const builder = PolicyBuilder.create("foo((uint256,uint256)[])");
    const error = expectErrorCode(() => builder.add(arg(0, Quantifier.ALL, 2).eq(1n)), "TUPLE_FIELD_OUT_OF_BOUNDS");
    expect(error.message).toContain("Tuple field index 2");
  });

  test("rejects a second quantifier step", () => {
    const builder = PolicyBuilder.create("foo(uint256[][])");
    expectErrorCode(() => builder.add(constraintAt([0, Quantifier.ALL, Quantifier.ANY])), "INVALID_NESTED_LOOP");
  });

  test("rejects a reserved marker step other than a quantifier", () => {
    const builder = PolicyBuilder.create("foo(uint256[])");
    expectErrorCode(() => builder.add(constraintAt([0, PF.PATH_MARKER_BASE])), "UNKNOWN_PATH_STEP");
  });
});

///////////////////////////////////////////////////////////////////////////
// Intake errors
///////////////////////////////////////////////////////////////////////////

describe("PolicyBuilder.add intake errors", () => {
  test("rejects an empty path", () => {
    const constraint: Constraint = { scope: Scope.CALLDATA, path: "0x", operators: [op(Op.EQ, 1n)] };
    expectErrorCode(() => PolicyBuilder.create("foo(uint256)").add(constraint), "EMPTY_PATH");
  });

  test("rejects a constraint without operators", () => {
    expectErrorCode(() => PolicyBuilder.create("foo(uint256)").add(arg(0)), "NO_CONSTRAINT_OPERATORS");
  });

  test("rejects a context path of two steps", () => {
    expectErrorCode(() => PolicyBuilder.create("foo()").add(contextAt([0, 0])), "INVALID_CONTEXT_PATH");
  });

  test("rejects a scope a constraint cannot take", () => {
    const constraint = { scope: Scope.LOOP, path: encodePath([0]), operators: [op(Op.EQ, 42n)] };
    // @ts-expect-error -- the scope lies outside the union a caller from JavaScript can still pass.
    expectErrorCode(() => PolicyBuilder.create("foo(uint256)").add(constraint), "UNKNOWN_SCOPE");
  });

  test("rejects a comparison that does not apply to its target", () => {
    expectErrorCode(() => PolicyBuilder.create("foo(uint256)").add(arg(0).lengthEq(1n)), "OPERATOR_TARGET_MISMATCH");
  });

  test("rejects a context comparison that does not apply to its target", () => {
    const constraint = arg(0).gtCtx(ContextProperty.BLOCK_TIMESTAMP);
    expectErrorCode(() => PolicyBuilder.create("foo(bytes)").add(constraint), "OPERATOR_TARGET_MISMATCH");
  });
});

///////////////////////////////////////////////////////////////////////////
// Operand domain
///////////////////////////////////////////////////////////////////////////

describe("PolicyBuilder.add operand domain", () => {
  test("rejects an operand above a signed target's maximum", () => {
    expectErrorCode(() => PolicyBuilder.create("foo(int256)").add(arg(0).gt(2n ** 255n)), "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("rejects a range endpoint that folds into the domain", () => {
    expectErrorCode(() => PolicyBuilder.create("foo(uint256)").add(arg(0).between(-1n, 5n)), "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("rejects a set member that folds into the domain", () => {
    expectErrorCode(() => PolicyBuilder.create("foo(uint256)").add(arg(0).isIn([5n, -1n])), "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("rejects a negative operand on an unsigned context property", () => {
    expectErrorCode(() => PolicyBuilder.create("foo()").add(msgValue().lt(-1n)), "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("rejects an operand that folds into the element type under a quantifier", () => {
    expectErrorCode(
      () => PolicyBuilder.create("foo(uint256[])").add(arg(0, Quantifier.ALL).lte(-1n)),
      "OUT_OF_PHYSICAL_BOUNDS",
    );
  });

  test("rejects a folded operand under a negated operator", () => {
    expectErrorCode(() => PolicyBuilder.create("foo(uint256)").add(arg(0).neq(-1n)), "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("names the furthest of two folding operands", () => {
    const error = expectErrorCode(
      () => PolicyBuilder.create("foo(uint256)").add(arg(0).lte(-5n).gt(-1n)),
      "OUT_OF_PHYSICAL_BOUNDS",
    );
    expect(error.message).toContain("-5");
  });

  test("rejects an operand outside the target's width", () => {
    expectErrorCode(() => PolicyBuilder.create("foo(uint8)").add(arg(0).eq(256n)), "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("rejects a mask wider than the target", () => {
    expectErrorCode(() => PolicyBuilder.create("foo(uint8)").add(arg(0).bitmaskAll(0x100n)), "OUT_OF_PHYSICAL_BOUNDS");
  });

  test("takes -1 as the all-ones mask of a narrow target", () => {
    expect(() => PolicyBuilder.create("foo(uint8)").add(arg(0).bitmaskAll(-1n)).build()).not.toThrow();
  });

  test("leaves an operator of no whole words unread", () => {
    const constraint: Constraint = { scope: Scope.CALLDATA, path: encodePath([0]), operators: ["0x1001"] };
    const builder = PolicyBuilder.create("foo(uint8)").add(constraint);
    expectErrorCode(() => builder.build(), "INVALID_OPERATOR_BYTES");
  });

  test("rejects a set past what the data length holds at the target's width", () => {
    const builder = PolicyBuilder.create("foo(uint256)");
    expectErrorCode(() => builder.add(arg(0).isIn(values(WORD_SET_LIMIT + 1))), "SET_TOO_LARGE");
  });

  test("weighs the set limit after deduplication and builds a full set", () => {
    const members = values(WORD_SET_LIMIT + 1);
    members[members.length - 1] = 0n;
    expect(() => PolicyBuilder.create("foo(uint256)").add(arg(0).isIn(members)).build()).not.toThrow();
  });
});

///////////////////////////////////////////////////////////////////////////
// Loops
///////////////////////////////////////////////////////////////////////////

describe("PolicyBuilder.add loops", () => {
  test("joins one quantifier's constraints over one array into one loop", () => {
    const policy = PolicyBuilder.create("foo((address,uint256)[])")
      .add(arg(0, Quantifier.ANY, 0).eq("0x0000000000000000000000000000000000000001"))
      .add(arg(0, Quantifier.ANY, 1).gte(1000n))
      .add(arg(0, Quantifier.ALL, 1).lte(5000n))
      .build();

    const rules = PolicyCoder.decode(policy).groups[0];
    expect(rules.map((rule) => (rule.scope === Scope.LOOP ? [rule.quantifier, rule.body.length] : []))).toEqual([
      [LoopQuantifier.ALL, 1],
      [LoopQuantifier.ANY, 2],
    ]);
  });
});

///////////////////////////////////////////////////////////////////////////
// Or
///////////////////////////////////////////////////////////////////////////

describe("PolicyBuilder.or", () => {
  test("rejects starting a group after an empty one", () => {
    expectErrorCode(() => PolicyBuilder.create("foo(uint256)").or(), "EMPTY_GROUP");
  });
});

///////////////////////////////////////////////////////////////////////////
// Build
///////////////////////////////////////////////////////////////////////////

describe("PolicyBuilder.build", () => {
  test("validates the blob it encodes", () => {
    const contextBetween = Op.BETWEEN | (Source.CONTEXT << Op.SOURCE_SHIFT);
    const constraint: Constraint = {
      scope: Scope.CALLDATA,
      path: encodePath([0]),
      operators: [op(contextBetween, 1n)],
    };
    const builder = PolicyBuilder.create("foo(uint256)").add(constraint);
    expect(() => builder.buildUnsafe()).not.toThrow();
    expectErrorCode(() => builder.build(), "INVALID_CONTEXT_OPERAND");
  });

  test("throws every issue validation reports", () => {
    const builder = PolicyBuilder.create("foo(address,bool)").add(arg(0).gt(1n)).add(arg(1).bitmaskAll(1n));
    const issues = builder.validate();
    expect(issues.map((issue) => issue.code)).toEqual(["NUMERIC_OP_ON_NON_NUMERIC", "BITMASK_ON_INVALID"]);
    const error = expectErrorCode(() => builder.build(), "VALIDATION_ERROR");
    expect(error instanceof ValidationError && error.issues).toEqual(issues);
  });

  test("encodes operators on one path alike across adds", () => {
    const separate = PolicyBuilder.create("foo(uint256)").add(arg(0).gt(1n)).add(arg(0).lt(9n)).build();
    const joint = PolicyBuilder.create("foo(uint256)").add(arg(0).gt(1n).lt(9n)).build();
    expect(separate).toBe(joint);
  });

  test("createRaw sets the selectorless flag with a zero selector slot", () => {
    const blob = hexToBytes(PolicyBuilder.createRaw("uint256").add(arg(0).eq(1n)).build());
    expect(blob[0] & PF.FLAG_NO_SELECTOR).toBe(PF.FLAG_NO_SELECTOR);
    expect([...blob.subarray(PF.SELECTOR_OFFSET, PF.SELECTOR_OFFSET + PF.SELECTOR_SIZE)]).toEqual([0, 0, 0, 0]);
  });
});

import { ContextProperty, Op, PolicyCoder, type ScalarValue, Quantifier } from "@callcium/sdk";
import { describe, expect, it } from "vitest";
import { formatOpLabel } from "./format-path";
import {
  createSession,
  addConstraint,
  getOperatorLabel,
  getOperatorOptions,
  removeConstraint,
  addGroup,
  removeGroup,
  type ConstraintInput,
} from "./policy-builder";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

const ADDRESS_A = "0x1111111254eeb25477b68fb85ed929f73a960582";
const ADDRESS_B = "0x2222222222222222222222222222222222222222";

/** Operands satisfying one operator against a target of the given Solidity type. */
function operandsFor(method: string, targetType: string): ScalarValue[] {
  if (method === "eqCtx" || method === "neqCtx") {
    return [targetType === "address" ? ContextProperty.MSG_SENDER : ContextProperty.MSG_VALUE];
  }
  if (method === "isIn" || method === "notIn") return targetType === "address" ? [ADDRESS_A, ADDRESS_B] : [1n, 2n];
  if (method === "between" || method === "lengthBetween") return [1n, 2n];
  return [targetType === "address" ? ADDRESS_A : 1n];
}

///////////////////////////////////////////////////////////////////////////
// Session creation
///////////////////////////////////////////////////////////////////////////

describe("createSession", () => {
  it("creates a session from a function signature", () => {
    const session = createSession("transfer(address,uint256)");
    expect(session.signature).toBe("transfer(address,uint256)");
    expect(session.isSelectorless).toBe(false);
    expect(session.params).toHaveLength(2);
    expect(session.params[0].type).toBe("address");
    expect(session.params[1].type).toBe("uint256");
    expect(session.groups).toHaveLength(1);
    expect(session.groups[0].constraints).toEqual([]);
    expect(session.hex).toBeNull();
    expect(session.issues).toEqual([]);
    expect(session.errors).toEqual([]);
  });

  it("creates a selectorless session", () => {
    const session = createSession("address,uint256", { selectorless: true });
    expect(session.isSelectorless).toBe(true);
    expect(session.params).toHaveLength(2);
  });

  it("parses a tuple parameter into nested fields", () => {
    const session = createSession("submit((address,uint256,bytes))");
    expect(session.params).toHaveLength(1);
    expect(session.params[0].type).toBe("tuple");
    expect(session.params[0].children).toHaveLength(3);
    expect(session.params[0].children![0].type).toBe("address");
    expect(session.params[0].children![1].type).toBe("uint256");
    expect(session.params[0].children![2].type).toBe("bytes");
  });

  it("parses a dynamic array parameter", () => {
    const session = createSession("batch(uint256[])");
    expect(session.params[0].type).toBe("uint256[]");
    expect(session.params[0].element).toBeDefined();
    expect(session.params[0].element!.type).toBe("uint256");
  });

  it("returns an error for invalid signature", () => {
    const session = createSession("not valid");
    expect(session.error).toBeDefined();
    expect(session.params).toEqual([]);
  });
});

///////////////////////////////////////////////////////////////////////////
// Constraint management
///////////////////////////////////////////////////////////////////////////

describe("addConstraint", () => {
  it("adds a simple eq constraint and produces hex", () => {
    const s1 = createSession("approve(address,uint256)");
    const constraint: ConstraintInput = {
      scope: "calldata",
      path: [0],
      rules: [{ operator: "eq", values: ["0x1111111254eeb25477b68fb85ed929f73a960582"] }],
    };
    const s2 = addConstraint(s1, 0, constraint);
    expect(s2.groups[0].constraints).toHaveLength(1);
    expect(s2.hex).not.toBeNull();
    expect(s2.issues).toEqual([]);
    expect(s2.errors).toEqual([]);
  });

  it("adds a context constraint (msgSender)", () => {
    const s1 = createSession("transfer(address,uint256)");
    const constraint: ConstraintInput = {
      scope: "context",
      contextProperty: "msgSender",
      rules: [{ operator: "eq", values: ["0xd8da6bf26964af9d7eed9e03e53415d37aa96045"] }],
    };
    const s2 = addConstraint(s1, 0, constraint);
    expect(s2.groups[0].constraints).toHaveLength(1);
    expect(s2.hex).not.toBeNull();
  });

  it("adds an eqCtx constraint pairing an address arg with msg.sender", () => {
    const s1 = createSession("transfer(address,uint256)");
    const constraint: ConstraintInput = {
      scope: "calldata",
      path: [0],
      rules: [{ operator: "eqCtx", values: [ContextProperty.MSG_SENDER] }],
    };
    const s2 = addConstraint(s1, 0, constraint);
    expect(s2.hex).not.toBeNull();
    expect(s2.issues).toEqual([]);
    expect(s2.errors).toEqual([]);
  });

  it("adds a neqCtx constraint pairing an address arg with tx.origin", () => {
    const s1 = createSession("transfer(address,uint256)");
    const constraint: ConstraintInput = {
      scope: "calldata",
      path: [0],
      rules: [{ operator: "neqCtx", values: [ContextProperty.TX_ORIGIN] }],
    };
    const s2 = addConstraint(s1, 0, constraint);
    expect(s2.hex).not.toBeNull();
    expect(s2.issues).toEqual([]);
    expect(s2.errors).toEqual([]);
  });

  it("reports a context type mismatch for a uint target paired with an address property", () => {
    const s1 = createSession("transfer(address,uint256)");
    const constraint: ConstraintInput = {
      scope: "calldata",
      path: [1],
      rules: [{ operator: "eqCtx", values: [ContextProperty.MSG_SENDER] }],
    };
    const s2 = addConstraint(s1, 0, constraint);
    expect(s2.issues.map((issue) => issue.code)).toContain("CONTEXT_TYPE_MISMATCH");
  });

  it("reports duplicate-path as structural error for same arg in same group", () => {
    let s = createSession("approve(address,uint256)");
    s = addConstraint(s, 0, {
      scope: "calldata",
      path: [1],
      rules: [{ operator: "eq", values: [100n] }],
    });
    const s2 = addConstraint(s, 0, {
      scope: "calldata",
      path: [1],
      rules: [{ operator: "eq", values: [200n] }],
    });
    expect(s2.errors.length).toBeGreaterThan(0);
    expect(s2.errors[0]).toMatch(/DUPLICATE_PATH/);
    expect(s2.hex).toBeNull();
  });

  it("detects vacuous gte(0) as info issue", () => {
    const s = addConstraint(createSession("approve(address,uint256)"), 0, {
      scope: "calldata",
      path: [1],
      rules: [{ operator: "gte", values: [0n] }],
    });
    const vacuous = s.issues.find((i) => i.severity === "info");
    expect(vacuous).toBeDefined();
    expect(vacuous!.groupIndex).toBe(0);
    expect(vacuous!.constraintIndex).toBe(0);
    expect(s.hex).not.toBeNull();
  });

  it("reports structural error for invalid path", () => {
    const s1 = createSession("transfer(address,uint256)");
    const constraint: ConstraintInput = {
      scope: "calldata",
      path: [5],
      rules: [{ operator: "eq", values: [1n] }],
    };
    const s2 = addConstraint(s1, 0, constraint);
    expect(s2.errors).toHaveLength(1);
    expect(s2.errors[0]).toMatch(/out of range/i);
  });

  it("adds a constraint on a specific static array index", () => {
    const s1 = createSession("foo(uint256[3])");
    const s2 = addConstraint(s1, 0, {
      scope: "calldata",
      path: [0, 1],
      rules: [{ operator: "eq", values: [42n] }],
    });
    expect(s2.hex).not.toBeNull();
    expect(s2.errors).toEqual([]);
  });

  it("allows two different indexed paths on the same array in one group", () => {
    let s = createSession("foo(uint256[3])");
    s = addConstraint(s, 0, {
      scope: "calldata",
      path: [0, 0],
      rules: [{ operator: "eq", values: [10n] }],
    });
    const s2 = addConstraint(s, 0, {
      scope: "calldata",
      path: [0, 1],
      rules: [{ operator: "eq", values: [20n] }],
    });
    expect(s2.hex).not.toBeNull();
    expect(s2.errors).toEqual([]);
    expect(s2.groups[0].constraints).toHaveLength(2);
  });

  it("adds a quantified constraint on a tuple field inside an array", () => {
    const s1 = createSession("foo((address,uint256)[])");
    const s2 = addConstraint(s1, 0, {
      scope: "calldata",
      path: [0, Quantifier.ALL, 0],
      rules: [{ operator: "eq", values: ["0x1111111254eeb25477b68fb85ed929f73a960582"] }],
    });
    expect(s2.hex).not.toBeNull();
    expect(s2.errors).toEqual([]);
  });

  it("adds a quantified constraint on an array nested inside a tuple", () => {
    const s1 = createSession("swap((address,address,uint256,address[]))");
    const s2 = addConstraint(s1, 0, {
      scope: "calldata",
      path: [0, 3, Quantifier.ALL],
      rules: [{ operator: "eq", values: ["0x1111111254eeb25477b68fb85ed929f73a960582"] }],
    });
    expect(s2.hex).not.toBeNull();
    expect(s2.errors).toEqual([]);
  });

  it("constrains a leaf five tuple levels deep", () => {
    const s1 = createSession("foo(((((uint256)))))");
    const s2 = addConstraint(s1, 0, {
      scope: "calldata",
      path: [0, 0, 0, 0, 0],
      rules: [{ operator: "eq", values: [100n] }],
    });
    expect(s2.hex).not.toBeNull();
    expect(s2.errors).toEqual([]);
  });

  it("reports the descriptor error when a path descends past its leaf", () => {
    const s1 = createSession("foo(((((uint256)))))");
    const s2 = addConstraint(s1, 0, {
      scope: "calldata",
      path: [0, 0, 0, 0, 0, 0],
      rules: [{ operator: "eq", values: [100n] }],
    });
    expect(s2.hex).toBeNull();
    expect(s2.errors[0]).toContain("NOT_COMPOSITE");
  });

  it("adds a multi-operator constraint (gte + lte) and produces hex", () => {
    const s1 = createSession("approve(address,uint256)");
    const s2 = addConstraint(s1, 0, {
      scope: "calldata",
      path: [1],
      rules: [
        { operator: "gte", values: [100n] },
        { operator: "lte", values: [1000n] },
      ],
    });
    expect(s2.groups[0].constraints).toHaveLength(1);
    expect(s2.groups[0].constraints[0].rules).toHaveLength(2);
    expect(s2.hex).not.toBeNull();
    expect(s2.errors).toEqual([]);
  });

  it("rejects a constraint with empty rules", () => {
    const s1 = createSession("approve(address,uint256)");
    const s2 = addConstraint(s1, 0, {
      scope: "calldata",
      path: [0],
      rules: [],
    });
    expect(s2.errors).toHaveLength(1);
    expect(s2.errors[0]).toMatch(/at least one operator rule/);
    expect(s2.hex).toBeNull();
  });

  it("adds two multi-operator constraints on different paths", () => {
    let s = createSession("approve(address,uint256)");
    s = addConstraint(s, 0, {
      scope: "calldata",
      path: [0],
      rules: [{ operator: "eq", values: ["0x1111111254eeb25477b68fb85ed929f73a960582"] }],
    });
    s = addConstraint(s, 0, {
      scope: "calldata",
      path: [1],
      rules: [
        { operator: "gte", values: [100n] },
        { operator: "lte", values: [1000000n] },
      ],
    });
    expect(s.groups[0].constraints).toHaveLength(2);
    expect(s.hex).not.toBeNull();
    expect(s.errors).toEqual([]);
  });
});

describe("removeConstraint", () => {
  it("removes a constraint and rebuilds", () => {
    const s1 = createSession("approve(address,uint256)");
    const constraint: ConstraintInput = {
      scope: "calldata",
      path: [0],
      rules: [{ operator: "eq", values: ["0x1111111254eeb25477b68fb85ed929f73a960582"] }],
    };
    const s2 = addConstraint(s1, 0, constraint);
    expect(s2.groups[0].constraints).toHaveLength(1);
    const s3 = removeConstraint(s2, 0, 0);
    expect(s3.groups[0].constraints).toHaveLength(0);
    expect(s3.hex).toBeNull();
  });
});

///////////////////////////////////////////////////////////////////////////
// Operator options
///////////////////////////////////////////////////////////////////////////

describe("getOperatorOptions", () => {
  it("offers the context reference operators only on address and unsigned targets", () => {
    const session = createSession("f(address,uint256,bool,bytes32,bytes)");
    const offersCtx = session.params.map((param) => {
      const methods = getOperatorOptions(param.typeInfo).map((op) => op.value);
      return methods.includes("eqCtx") && methods.includes("neqCtx");
    });
    expect(offersCtx).toEqual([true, true, false, false, false]);
  });
});

describe("group management", () => {
  it("adds a new group", () => {
    const s1 = createSession("approve(address,uint256)");
    const s2 = addGroup(s1);
    expect(s2.groups).toHaveLength(2);
  });

  it("removes a group", () => {
    const s1 = createSession("approve(address,uint256)");
    const s2 = addGroup(s1);
    const s3 = removeGroup(s2, 1);
    expect(s3.groups).toHaveLength(1);
  });
});

///////////////////////////////////////////////////////////////////////////
// Operator dispatch
///////////////////////////////////////////////////////////////////////////

describe("operator dispatch", () => {
  // One target per operator family: address covers equality and set ops, uint256 adds
  // ordering and bitmask, bytes adds the length ops.
  const session = createSession("f(address,uint256,bytes)");

  const cases = session.params.flatMap((param) =>
    getOperatorOptions(param.typeInfo).map((option) => ({
      method: option.value,
      argIndex: param.index,
      targetType: param.type,
    })),
  );

  it("reaches every operator the UI can offer", () => {
    expect(new Set(cases.map((c) => c.method)).size).toBe(20);
  });

  it.each(cases)("encodes $method on $targetType", ({ method, argIndex, targetType }) => {
    const next = addConstraint(session, 0, {
      scope: "calldata",
      path: [argIndex],
      rules: [{ operator: method, values: operandsFor(method, targetType) }],
    });
    expect(next.errors).toEqual([]);
    expect(next.hex).not.toBeNull();

    // The encoded op must be the one the label promised, not a neighbour in the table.
    const rule = PolicyCoder.inspect(next.hex!).groups[0].rules[0];
    const opCode = rule.opCode.value;
    expect(formatOpLabel(opCode & ~Op.NOT, (opCode & Op.NOT) !== 0)).toBe(getOperatorLabel(method));
  });
});

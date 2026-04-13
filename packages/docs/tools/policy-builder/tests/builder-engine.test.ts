import { Quantifier } from "@callcium/sdk";
import { describe, expect, it } from "vitest";
import {
  createSession,
  addConstraint,
  removeConstraint,
  addGroup,
  removeGroup,
  moveConstraint,
  type ConstraintInput,
} from "../builder-engine";

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
      operator: "eq",
      values: ["0x1111111254eeb25477b68fb85ed929f73a960582"],
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
      operator: "eq",
      values: ["0xd8da6bf26964af9d7eed9e03e53415d37aa96045"],
    };
    const s2 = addConstraint(s1, 0, constraint);
    expect(s2.groups[0].constraints).toHaveLength(1);
    expect(s2.hex).not.toBeNull();
  });

  it("reports duplicate-path as structural error for same arg in same group", () => {
    let s = createSession("approve(address,uint256)");
    s = addConstraint(s, 0, {
      scope: "calldata",
      path: [1],
      operator: "eq",
      values: [100n],
    });
    const s2 = addConstraint(s, 0, {
      scope: "calldata",
      path: [1],
      operator: "eq",
      values: [200n],
    });
    expect(s2.errors.length).toBeGreaterThan(0);
    expect(s2.errors[0]).toMatch(/DUPLICATE_PATH/);
    expect(s2.hex).toBeNull();
  });

  it("detects vacuous gte(0) as info issue", () => {
    const s = addConstraint(createSession("approve(address,uint256)"), 0, {
      scope: "calldata",
      path: [1],
      operator: "gte",
      values: [0n],
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
      operator: "eq",
      values: [1n],
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
      operator: "eq",
      values: [42n],
    });
    expect(s2.hex).not.toBeNull();
    expect(s2.errors).toEqual([]);
  });

  it("allows two different indexed paths on the same array in one group", () => {
    let s = createSession("foo(uint256[3])");
    s = addConstraint(s, 0, {
      scope: "calldata",
      path: [0, 0],
      operator: "eq",
      values: [10n],
    });
    const s2 = addConstraint(s, 0, {
      scope: "calldata",
      path: [0, 1],
      operator: "eq",
      values: [20n],
    });
    expect(s2.hex).not.toBeNull();
    expect(s2.errors).toEqual([]);
    expect(s2.groups[0].constraints).toHaveLength(2);
  });

  it("adds a quantified constraint on a tuple field inside an array", () => {
    const s1 = createSession("foo((address,uint256)[])");
    const s2 = addConstraint(s1, 0, {
      scope: "calldata",
      path: [0, 0],
      operator: "eq",
      values: ["0x1111111254eeb25477b68fb85ed929f73a960582"],
      quantifier: Quantifier.ALL,
    });
    expect(s2.hex).not.toBeNull();
    expect(s2.errors).toEqual([]);
  });
});

describe("removeConstraint", () => {
  it("removes a constraint and rebuilds", () => {
    const s1 = createSession("approve(address,uint256)");
    const constraint: ConstraintInput = {
      scope: "calldata",
      path: [0],
      operator: "eq",
      values: ["0x1111111254eeb25477b68fb85ed929f73a960582"],
    };
    const s2 = addConstraint(s1, 0, constraint);
    expect(s2.groups[0].constraints).toHaveLength(1);
    const s3 = removeConstraint(s2, 0, 0);
    expect(s3.groups[0].constraints).toHaveLength(0);
    expect(s3.hex).toBeNull();
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

  it("moves a constraint between groups", () => {
    const s1 = createSession("approve(address,uint256)");
    const constraint: ConstraintInput = {
      scope: "calldata",
      path: [0],
      operator: "eq",
      values: ["0x1111111254eeb25477b68fb85ed929f73a960582"],
    };
    const s2 = addConstraint(s1, 0, constraint);
    const s3 = addGroup(s2);
    const s4 = moveConstraint(s3, 0, 0, 1);
    expect(s4.groups[0].constraints).toHaveLength(0);
    expect(s4.groups[1].constraints).toHaveLength(1);
  });
});

import { describe, expect, test } from "vitest";

import { Quantifier, Scope } from "../src/constants";
import { arg, msgSender } from "../src/constraint";
import { CallciumError } from "../src/errors";
import { PolicyBuilder } from "../src/policy-builder";
import { PolicyCoder } from "../src/policy-coder";

import type { Constraint } from "../src/types";

describe("PolicyBuilder", () => {
  ///////////////////////////////////////////////////////////////////////////
  // Happy paths
  ///////////////////////////////////////////////////////////////////////////

  test("create + add + build produces a valid hex blob", () => {
    const blob = PolicyBuilder.create("transfer(address,uint256)")
      .add(arg(0).eq("0x0000000000000000000000000000000000000001"))
      .build();

    expect(blob).toMatch(/^0x[0-9a-f]+$/);
  });

  test("round-trips through PolicyCoder.decode", () => {
    const blob = PolicyBuilder.create("transfer(address,uint256)")
      .add(arg(0).eq("0x0000000000000000000000000000000000000001"))
      .build();

    const decoded = PolicyCoder.decode(blob);
    expect(decoded.isSelectorless).toBe(false);
    expect(decoded.groups.length).toBe(1);
    expect(decoded.groups[0].length).toBe(1);
    expect(decoded.groups[0][0].scope).toBe(Scope.CALLDATA);
  });

  test("createRaw produces a selectorless policy", () => {
    const blob = PolicyBuilder.createRaw("uint256").add(arg(0).eq(42n)).build();
    const decoded = PolicyCoder.decode(blob);
    expect(decoded.isSelectorless).toBe(true);
    expect(decoded.selector).toBe("0x00000000");
  });

  test("or() creates multiple groups", () => {
    const blob = PolicyBuilder.create("transfer(address,uint256)")
      .add(arg(0).eq("0x0000000000000000000000000000000000000001"))
      .or()
      .add(arg(0).eq("0x0000000000000000000000000000000000000002"))
      .build();

    const decoded = PolicyCoder.decode(blob);
    expect(decoded.groups.length).toBe(2);
  });

  test("supports multiple constraints in the same group", () => {
    const blob = PolicyBuilder.create("transfer(address,uint256)")
      .add(arg(0).eq("0x0000000000000000000000000000000000000001"))
      .add(arg(1).lte(1000n))
      .build();

    const decoded = PolicyCoder.decode(blob);
    expect(decoded.groups[0].length).toBe(2);
  });

  test("supports context constraints (msgSender)", () => {
    const blob = PolicyBuilder.create("transfer(address,uint256)")
      .add(msgSender().eq("0x0000000000000000000000000000000000000001"))
      .build();

    const decoded = PolicyCoder.decode(blob);
    expect(decoded.groups[0][0].scope).toBe(Scope.CONTEXT);
  });

  test("validates without throwing and returns issues", () => {
    const issues = PolicyBuilder.create("transfer(address,uint256)")
      .add(arg(0).eq("0x0000000000000000000000000000000000000001"))
      .validate();

    expect(Array.isArray(issues)).toBe(true);
  });

  test("nested path validation: arg(0, 0) on tuple type works", () => {
    const blob = PolicyBuilder.create("foo((address,uint256))")
      .add(arg(0, 0).eq("0x0000000000000000000000000000000000000001"))
      .build();
    const decoded = PolicyCoder.decode(blob);
    expect(decoded.groups[0].length).toBe(1);
  });

  test("quantifier path: arg(0, Quantifier.ALL) on array type works", () => {
    const blob = PolicyBuilder.create("foo(uint256[])").add(arg(0, Quantifier.ALL).lte(100n)).build();
    const decoded = PolicyCoder.decode(blob);
    expect(decoded.groups[0].length).toBe(1);
  });

  ///////////////////////////////////////////////////////////////////////////
  // Error cases
  ///////////////////////////////////////////////////////////////////////////

  test("rejects invalid arg index", () => {
    expect(() => {
      PolicyBuilder.create("transfer(address,uint256)").add(arg(5).eq(1n));
    }).toThrow(CallciumError);
  });

  test("rejects duplicate path in same group", () => {
    expect(() => {
      PolicyBuilder.create("transfer(address,uint256)")
        .add(arg(0).eq("0x0000000000000000000000000000000000000001"))
        .add(arg(0).eq("0x0000000000000000000000000000000000000002"));
    }).toThrow(CallciumError);
  });

  test("rejects empty constraint (no operators)", () => {
    const empty: Constraint = { scope: Scope.CALLDATA, path: "0x0000", operators: [] };
    expect(() => {
      PolicyBuilder.create("transfer(address,uint256)").add(empty);
    }).toThrow(CallciumError);
  });

  test("or() rejects empty current group", () => {
    expect(() => {
      PolicyBuilder.create("transfer(address,uint256)").or();
    }).toThrow(CallciumError);
  });

  test("build() rejects if final group is empty", () => {
    expect(() => {
      PolicyBuilder.create("transfer(address,uint256)")
        .add(arg(0).eq("0x0000000000000000000000000000000000000001"))
        .or()
        .build();
    }).toThrow(CallciumError);
  });

  test("build() rejects if last group has no constraints (or then immediate build)", () => {
    const builder = PolicyBuilder.create("transfer(address,uint256)")
      .add(arg(0).eq("0x0000000000000000000000000000000000000001"))
      .or();

    expect(() => builder.build()).toThrow(CallciumError);
  });

  test("build() throws on validation errors (value op on dynamic type)", () => {
    // string is a dynamic type; eq is a value operator → type mismatch error.
    expect(() => {
      PolicyBuilder.create("foo(string)").add(arg(0).eq(42n)).build();
    }).toThrow(CallciumError);
  });

  test("rejects quantifier on non-array type", () => {
    expect(() => {
      PolicyBuilder.create("foo(uint256)").add(arg(0, Quantifier.ALL).eq(1n));
    }).toThrow(CallciumError);
  });

  test("rejects nested quantifiers", () => {
    expect(() => {
      PolicyBuilder.create("foo(uint256[][])").add(arg(0, Quantifier.ALL, Quantifier.ALL).eq(1n));
    }).toThrow(CallciumError);
  });

  test("rejects invalid scope value", () => {
    const invalid: Constraint = {
      scope: 0x05,
      path: "0x0000",
      operators: [`0x01${"0".repeat(64)}`],
    };
    expect(() => {
      PolicyBuilder.create("transfer(address,uint256)").add(invalid);
    }).toThrow(CallciumError);

    try {
      PolicyBuilder.create("transfer(address,uint256)").add(invalid);
      expect.unreachable("should have thrown");
    } catch (err) {
      if (err instanceof CallciumError) {
        expect(err.code).toBe("INVALID_SCOPE");
      } else {
        throw err;
      }
    }
  });

  test("or() immediately after creation throws EMPTY_GROUP", () => {
    try {
      PolicyBuilder.create("transfer(address,uint256)").or();
      expect.unreachable("should have thrown");
    } catch (err) {
      if (err instanceof CallciumError) {
        expect(err.code).toBe("EMPTY_GROUP");
      } else {
        throw err;
      }
    }
  });

  test("build() throws EMPTY_GROUP when last group has no constraints", () => {
    try {
      PolicyBuilder.create("transfer(address,uint256)")
        .add(arg(0).eq("0x0000000000000000000000000000000000000001"))
        .or()
        .build();
      expect.unreachable("should have thrown");
    } catch (err) {
      if (err instanceof CallciumError) {
        expect(err.code).toBe("EMPTY_GROUP");
      } else {
        throw err;
      }
    }
  });

  ///////////////////////////////////////////////////////////////////////////
  // Context path validation
  ///////////////////////////////////////////////////////////////////////////

  test("rejects context path that is not exactly 2 bytes", () => {
    const invalid: Constraint = {
      scope: Scope.CONTEXT,
      path: "0x000000", // 3 bytes, not 2.
      operators: [`0x01${"0".repeat(64)}`],
    };
    expect(() => {
      PolicyBuilder.create("transfer(address,uint256)").add(invalid);
    }).toThrow(CallciumError);

    try {
      PolicyBuilder.create("transfer(address,uint256)").add(invalid);
      expect.unreachable("should have thrown");
    } catch (err) {
      if (err instanceof CallciumError) {
        expect(err.code).toBe("INVALID_CONTEXT_PATH");
      } else {
        throw err;
      }
    }
  });

  test("rejects context path with unknown property ID", () => {
    const invalid: Constraint = {
      scope: Scope.CONTEXT,
      path: "0xffff", // Way beyond MAX_CONTEXT_PROPERTY_ID.
      operators: [`0x01${"0".repeat(64)}`],
    };
    expect(() => {
      PolicyBuilder.create("transfer(address,uint256)").add(invalid);
    }).toThrow(CallciumError);

    try {
      PolicyBuilder.create("transfer(address,uint256)").add(invalid);
      expect.unreachable("should have thrown");
    } catch (err) {
      if (err instanceof CallciumError) {
        expect(err.code).toBe("INVALID_CONTEXT_PROPERTY");
      } else {
        throw err;
      }
    }
  });

  ///////////////////////////////////////////////////////////////////////////
  // Calldata path validation edge cases
  ///////////////////////////////////////////////////////////////////////////

  test("rejects quantifier step on a tuple node", () => {
    expect(() => {
      PolicyBuilder.create("foo((address,uint256))").add(arg(0, Quantifier.ALL).eq(1n));
    }).toThrow(CallciumError);
  });

  test("rejects tuple field index out of range", () => {
    expect(() => {
      PolicyBuilder.create("foo((address,uint256))").add(arg(0, 5).eq(1n));
    }).toThrow(CallciumError);
  });

  test("rejects static array index out of range", () => {
    expect(() => {
      PolicyBuilder.create("foo(uint256[3])").add(arg(0, 10).eq(1n));
    }).toThrow(CallciumError);
  });

  test("allows valid static array index within range", () => {
    const blob = PolicyBuilder.create("foo(uint256[3])").add(arg(0, 2).eq(1n)).build();
    expect(blob).toMatch(/^0x[0-9a-f]+$/);
  });
});

import { describe, expect, test } from "vitest";

import {
  lookupOp,
  lookupScope,
  lookupContextProperty,
  lookupQuantifier,
  lookupTypeCode,
  classifyTypeCode,
  isValidOperatorData,
  Op,
  Scope,
  ContextProperty,
  Quantifier,
  TypeCode,
} from "../src/constants";
import { expectErrorCode } from "./helpers";

describe("lookupOp", () => {
  ///////////////////////////////////////////////////////////////////////////
  // COMPARISON OPERATORS
  ///////////////////////////////////////////////////////////////////////////

  test("EQ", () => {
    expect(lookupOp(Op.EQ)).toEqual({ label: "==", operands: "single" });
  });

  test("GT", () => {
    expect(lookupOp(Op.GT)).toEqual({ label: ">", operands: "single" });
  });

  test("LT", () => {
    expect(lookupOp(Op.LT)).toEqual({ label: "<", operands: "single" });
  });

  test("GTE", () => {
    expect(lookupOp(Op.GTE)).toEqual({ label: ">=", operands: "single" });
  });

  test("LTE", () => {
    expect(lookupOp(Op.LTE)).toEqual({ label: "<=", operands: "single" });
  });

  test("BETWEEN", () => {
    expect(lookupOp(Op.BETWEEN)).toEqual({ label: "between", operands: "range" });
  });

  test("IN", () => {
    expect(lookupOp(Op.IN)).toEqual({ label: "in", operands: "variadic" });
  });

  ///////////////////////////////////////////////////////////////////////////
  // BITMASK OPERATORS
  ///////////////////////////////////////////////////////////////////////////

  test("BITMASK_ALL", () => {
    expect(lookupOp(Op.BITMASK_ALL)).toEqual({ label: "bitmask all", operands: "single" });
  });

  test("BITMASK_ANY", () => {
    expect(lookupOp(Op.BITMASK_ANY)).toEqual({ label: "bitmask any", operands: "single" });
  });

  test("BITMASK_NONE", () => {
    expect(lookupOp(Op.BITMASK_NONE)).toEqual({ label: "bitmask none", operands: "single" });
  });

  ///////////////////////////////////////////////////////////////////////////
  // LENGTH OPERATORS
  ///////////////////////////////////////////////////////////////////////////

  test("LENGTH_EQ", () => {
    expect(lookupOp(Op.LENGTH_EQ)).toEqual({ label: "length ==", operands: "single" });
  });

  test("LENGTH_BETWEEN", () => {
    expect(lookupOp(Op.LENGTH_BETWEEN)).toEqual({ label: "length between", operands: "range" });
  });

  ///////////////////////////////////////////////////////////////////////////
  // NOT FLAG HANDLING
  ///////////////////////////////////////////////////////////////////////////

  test("strips NOT flag and returns base label", () => {
    expect(lookupOp(Op.EQ | Op.NOT)).toEqual({ label: "==", operands: "single" });
  });

  test("strips NOT flag for GT", () => {
    expect(lookupOp(Op.GT | Op.NOT)).toEqual({ label: ">", operands: "single" });
  });

  ///////////////////////////////////////////////////////////////////////////
  // ERROR CASES
  ///////////////////////////////////////////////////////////////////////////

  test("rejects unknown operator code", () => {
    expectErrorCode(() => lookupOp(0x00), "INVALID_OPERATOR");
  });

  test("rejects unknown operator code 0xff", () => {
    expectErrorCode(() => lookupOp(0xff), "INVALID_OPERATOR");
  });
});

describe("lookupScope", () => {
  test("CONTEXT", () => {
    expect(lookupScope(Scope.CONTEXT)).toEqual({ label: "context" });
  });

  test("CALLDATA", () => {
    expect(lookupScope(Scope.CALLDATA)).toEqual({ label: "calldata" });
  });

  test("rejects unknown scope code", () => {
    expectErrorCode(() => lookupScope(0x02), "INVALID_SCOPE");
  });
});

describe("lookupContextProperty", () => {
  test("MSG_SENDER", () => {
    expect(lookupContextProperty(ContextProperty.MSG_SENDER)).toEqual({
      label: "msg.sender",
      typeCode: 0x40,
    });
  });

  test("MSG_VALUE", () => {
    expect(lookupContextProperty(ContextProperty.MSG_VALUE)).toEqual({
      label: "msg.value",
      typeCode: 0x1f,
    });
  });

  test("BLOCK_TIMESTAMP", () => {
    expect(lookupContextProperty(ContextProperty.BLOCK_TIMESTAMP)).toEqual({
      label: "block.timestamp",
      typeCode: 0x1f,
    });
  });

  test("BLOCK_NUMBER", () => {
    expect(lookupContextProperty(ContextProperty.BLOCK_NUMBER)).toEqual({
      label: "block.number",
      typeCode: 0x1f,
    });
  });

  test("CHAIN_ID", () => {
    expect(lookupContextProperty(ContextProperty.CHAIN_ID)).toEqual({
      label: "block.chainid",
      typeCode: 0x1f,
    });
  });

  test("TX_ORIGIN", () => {
    expect(lookupContextProperty(ContextProperty.TX_ORIGIN)).toEqual({
      label: "tx.origin",
      typeCode: 0x40,
    });
  });

  test("rejects unknown context property code", () => {
    expectErrorCode(() => lookupContextProperty(0x0006), "INVALID_CONTEXT_PROPERTY");
  });
});

describe("lookupQuantifier", () => {
  test("ALL_OR_EMPTY", () => {
    expect(lookupQuantifier(Quantifier.ALL_OR_EMPTY)).toEqual({ label: "all or empty" });
  });

  test("ALL", () => {
    expect(lookupQuantifier(Quantifier.ALL)).toEqual({ label: "all" });
  });

  test("ANY", () => {
    expect(lookupQuantifier(Quantifier.ANY)).toEqual({ label: "any" });
  });

  test("rejects unknown quantifier code", () => {
    expectErrorCode(() => lookupQuantifier(0x0000), "INVALID_QUANTIFIER");
  });
});

describe("classifyTypeCode", () => {
  test("throws for reserved range 0x82-0x8f", () => {
    expect(() => classifyTypeCode(0x83)).toThrow();
  });

  test("returns tuple for TypeCode.TUPLE", () => {
    expect(classifyTypeCode(TypeCode.TUPLE).typeClass).toBe("tuple");
  });

  test("throws for unrecognized code beyond all ranges", () => {
    expect(() => classifyTypeCode(0xff)).toThrow();
  });
});

describe("isValidOperatorData", () => {
  test("returns false for unknown opcode", () => {
    expect(isValidOperatorData(0xff, 32)).toBe(false);
  });
});

describe("lookupTypeCode", () => {
  test("returns label and class for uint256", () => {
    const info = lookupTypeCode(TypeCode.UINT_MAX);
    expect(info.label).toBe("uint256");
    expect(info.typeClass).toBe("elementary");
  });

  test("returns label and class for int8", () => {
    const info = lookupTypeCode(TypeCode.INT_MIN);
    expect(info.label).toBe("int8");
    expect(info.typeClass).toBe("elementary");
  });

  test("returns label for address", () => {
    expect(lookupTypeCode(TypeCode.ADDRESS).label).toBe("address");
  });

  test("returns label for bool", () => {
    expect(lookupTypeCode(TypeCode.BOOL).label).toBe("bool");
  });

  test("returns label for bytes32", () => {
    expect(lookupTypeCode(TypeCode.FIXED_BYTES_MIN + 31).label).toBe("bytes32");
  });

  test("returns label for bytes (dynamic)", () => {
    expect(lookupTypeCode(TypeCode.BYTES).label).toBe("bytes");
  });

  test("returns label for string (dynamic)", () => {
    expect(lookupTypeCode(TypeCode.STRING).label).toBe("string");
  });

  test("returns label for tuple", () => {
    expect(lookupTypeCode(TypeCode.TUPLE).label).toBe("tuple");
  });

  test("returns label for static array", () => {
    expect(lookupTypeCode(TypeCode.STATIC_ARRAY).label).toBe("T[k]");
  });

  test("returns label for dynamic array", () => {
    expect(lookupTypeCode(TypeCode.DYNAMIC_ARRAY).label).toBe("T[]");
  });

  test("returns label for function", () => {
    expect(lookupTypeCode(TypeCode.FUNCTION).label).toBe("function");
  });

  test("throws for unknown type code", () => {
    expect(() => lookupTypeCode(0xff)).toThrow();
  });
});

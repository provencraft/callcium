import { describe, expect, test } from "vitest";

import {
  ContextProperty,
  lookupContextProperty,
  lookupOp,
  lookupQuantifier,
  lookupScope,
  LoopQuantifier,
  Op,
  Scope,
  Source,
  TypeCode,
} from "../src/constants";
import { expectErrorCode } from "./helpers";

describe("lookupOp", () => {
  test("labels a constant comparison", () => {
    expect(lookupOp(Op.BETWEEN)).toEqual({ label: "between", operands: "range" });
  });

  test("labels a context source", () => {
    expect(lookupOp(Op.GTE | (Source.CONTEXT << Op.SOURCE_SHIFT))).toEqual({ label: ">= ctx", operands: "single" });
  });

  test("throws on a reserved comparison", () => {
    const error = expectErrorCode(() => lookupOp(0x08), "UNKNOWN_OPERATOR");
    expect(error.message).toBe("Unknown operator code 0x08");
  });

  test("throws on a reserved source", () => {
    expectErrorCode(() => lookupOp(Op.EQ | (2 << Op.SOURCE_SHIFT)), "UNKNOWN_OPERATOR");
  });
});

describe("lookupScope", () => {
  test("labels the loop scope", () => {
    expect(lookupScope(Scope.LOOP)).toEqual({ label: "loop" });
  });

  test("throws on a reserved scope", () => {
    const error = expectErrorCode(() => lookupScope(0x03), "UNKNOWN_SCOPE");
    expect(error.message).toBe("Unknown scope value 3");
  });
});

describe("lookupQuantifier", () => {
  test("labels both loop quantifiers", () => {
    expect(lookupQuantifier(LoopQuantifier.ALL)).toEqual({ label: "all" });
    expect(lookupQuantifier(LoopQuantifier.ANY)).toEqual({ label: "any" });
  });

  test("throws on a reserved quantifier", () => {
    const error = expectErrorCode(() => lookupQuantifier(0x00), "UNKNOWN_QUANTIFIER");
    expect(error.message).toBe("Unknown quantifier value 0");
  });
});

describe("lookupContextProperty", () => {
  test("MSG_SENDER", () => {
    expect(lookupContextProperty(ContextProperty.MSG_SENDER)).toEqual({
      label: "msg.sender",
      contextKey: "msgSender",
      typeCode: TypeCode.ADDRESS,
    });
  });

  test("MSG_VALUE", () => {
    expect(lookupContextProperty(ContextProperty.MSG_VALUE)).toEqual({
      label: "msg.value",
      contextKey: "msgValue",
      typeCode: TypeCode.UINT_MAX,
    });
  });

  test("BLOCK_TIMESTAMP", () => {
    expect(lookupContextProperty(ContextProperty.BLOCK_TIMESTAMP)).toEqual({
      label: "block.timestamp",
      contextKey: "blockTimestamp",
      typeCode: TypeCode.UINT_MAX,
    });
  });

  test("BLOCK_NUMBER", () => {
    expect(lookupContextProperty(ContextProperty.BLOCK_NUMBER)).toEqual({
      label: "block.number",
      contextKey: "blockNumber",
      typeCode: TypeCode.UINT_MAX,
    });
  });

  test("CHAIN_ID", () => {
    expect(lookupContextProperty(ContextProperty.CHAIN_ID)).toEqual({
      label: "block.chainid",
      contextKey: "chainId",
      typeCode: TypeCode.UINT_MAX,
    });
  });

  test("TX_ORIGIN", () => {
    expect(lookupContextProperty(ContextProperty.TX_ORIGIN)).toEqual({
      label: "tx.origin",
      contextKey: "txOrigin",
      typeCode: TypeCode.ADDRESS,
    });
  });

  test("BASE_FEE", () => {
    expect(lookupContextProperty(ContextProperty.BASE_FEE)).toEqual({
      label: "block.basefee",
      contextKey: "baseFee",
      typeCode: TypeCode.UINT_MAX,
    });
  });

  test("GAS_PRICE", () => {
    expect(lookupContextProperty(ContextProperty.GAS_PRICE)).toEqual({
      label: "tx.gasprice",
      contextKey: "gasPrice",
      typeCode: TypeCode.UINT_MAX,
    });
  });

  test("names a code the ID field cannot hold in its own decimal form", () => {
    expect(expectErrorCode(() => lookupContextProperty(-1), "UNKNOWN_CONTEXT_PROPERTY").message).toContain(
      "property ID -1",
    );
  });
});

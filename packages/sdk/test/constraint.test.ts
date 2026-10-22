import { describe, expect, expectTypeOf, test } from "vitest";

import { ContextProperty, MAX_CONTEXT_PROPERTY_ID, Op, Scope, Source } from "../src/constants";
import {
  arg,
  baseFee,
  blockNumber,
  blockTimestamp,
  chainId,
  gasPrice,
  msgSender,
  msgValue,
  txOrigin,
} from "../src/constraint";
import { expectErrorCode, inOp, op } from "./helpers";

import type { ConstraintBuilder, ScalarValue } from "../src/constraint";
import type { Address } from "../src/types";

///////////////////////////////////////////////////////////////////////////
// Context factories
///////////////////////////////////////////////////////////////////////////

describe("context factories", () => {
  test("each names its property ID as a one-step context path", () => {
    const factories = [msgSender, msgValue, blockTimestamp, blockNumber, chainId, txOrigin, baseFee, gasPrice];
    const ids = [
      ContextProperty.MSG_SENDER,
      ContextProperty.MSG_VALUE,
      ContextProperty.BLOCK_TIMESTAMP,
      ContextProperty.BLOCK_NUMBER,
      ContextProperty.CHAIN_ID,
      ContextProperty.TX_ORIGIN,
      ContextProperty.BASE_FEE,
      ContextProperty.GAS_PRICE,
    ];
    for (const [index, factory] of factories.entries()) {
      expect(factory().scope).toBe(Scope.CONTEXT);
      expect(factory().path).toBe(`0x${ids[index].toString(16).padStart(4, "0")}`);
    }
  });

  test("an address property takes an address operand and nothing else", () => {
    expectTypeOf(msgSender()).toEqualTypeOf<ConstraintBuilder<Address>>();
    expectTypeOf(txOrigin()).toEqualTypeOf<ConstraintBuilder<Address>>();
  });

  test("a uint256 property takes a bigint operand and nothing else", () => {
    expectTypeOf(msgValue()).toEqualTypeOf<ConstraintBuilder<bigint>>();
    expectTypeOf(blockTimestamp()).toEqualTypeOf<ConstraintBuilder<bigint>>();
    expectTypeOf(blockNumber()).toEqualTypeOf<ConstraintBuilder<bigint>>();
    expectTypeOf(chainId()).toEqualTypeOf<ConstraintBuilder<bigint>>();
  });

  test("a calldata target keeps the wide operand union", () => {
    expectTypeOf(arg(0)).toEqualTypeOf<ConstraintBuilder>();
    expectTypeOf<ScalarValue>().toEqualTypeOf<bigint | boolean | string>();
  });
});

///////////////////////////////////////////////////////////////////////////
// Operators
///////////////////////////////////////////////////////////////////////////

describe("operators", () => {
  test("a context operator carries the context source and the property ID", () => {
    expect(arg(0).gtCtx(ContextProperty.MSG_VALUE).operators[0]).toBe(
      op(Op.GT | (Source.CONTEXT << Op.SOURCE_SHIFT), BigInt(ContextProperty.MSG_VALUE)),
    );
  });

  test("rejects a context property past the highest defined ID", () => {
    expectErrorCode(() => arg(0).eqCtx(MAX_CONTEXT_PROPERTY_ID + 1), "UNKNOWN_CONTEXT_PROPERTY");
  });

  test("sorts and deduplicates a set", () => {
    expect(arg(0).isIn([3n, 1n, 3n]).operators[0]).toBe(inOp(Op.IN, [1n, 3n]));
  });

  test("rejects an empty set", () => {
    expectErrorCode(() => arg(0).isIn([]), "EMPTY_SET");
  });

  test("rejects a range whose minimum exceeds its maximum as written", () => {
    expectErrorCode(() => arg(0).between(1n, -1n), "INVALID_RANGE");
  });

  test("accepts equal range bounds", () => {
    expect(arg(0).between(5n, 5n).operators).toHaveLength(1);
  });

  test("rejects an operand of a type no operand takes", () => {
    // @ts-expect-error -- a JavaScript caller can pass a number.
    expectErrorCode(() => arg(0).eq(5), "MALFORMED_OPERAND");
    // @ts-expect-error -- a JavaScript caller can pass a number.
    expectErrorCode(() => arg(0).isIn([5]), "MALFORMED_OPERAND");
  });

  test("rejects an operand outside the word's range", () => {
    expectErrorCode(() => arg(0).eq(2n ** 256n), "OPERAND_OVERFLOW");
    expectErrorCode(() => arg(0).eq(-(2n ** 255n) - 1n), "OPERAND_OVERFLOW");
  });
});

import { describe, expect, test } from "vitest";

import { Scope, ContextProperty, Op } from "../src/constants";
import { arg, msgSender, msgValue, blockTimestamp, blockNumber, chainId, txOrigin } from "../src/constraint";
import { CallciumError } from "../src/errors";

///////////////////////////////////////////////////////////////////////////
// Target factories
///////////////////////////////////////////////////////////////////////////

describe("arg()", () => {
  test("arg(0) — scope=CALLDATA, path=0x0000, no operators", () => {
    const c = arg(0);
    expect(c.scope).toBe(Scope.CALLDATA);
    expect(c.path).toBe("0x0000");
    expect(c.operators).toHaveLength(0);
  });

  test("arg(0, 1) — two-step path", () => {
    const c = arg(0, 1);
    expect(c.path).toBe("0x00000001");
  });

  test("arg(0, 1, 2) — three-step path", () => {
    const c = arg(0, 1, 2);
    expect(c.path).toBe("0x000000010002");
  });

  test("arg(0, 1, 2, 3) — four-step path", () => {
    const c = arg(0, 1, 2, 3);
    expect(c.path).toBe("0x0000000100020003");
  });
});

describe("context factories", () => {
  test("msgSender() — scope=CONTEXT, path=0x0000", () => {
    const c = msgSender();
    expect(c.scope).toBe(Scope.CONTEXT);
    expect(c.path).toBe(`0x${ContextProperty.MSG_SENDER.toString(16).padStart(4, "0")}`);
  });

  test("msgValue() — path=0x0001", () => {
    expect(msgValue().path).toBe(`0x${ContextProperty.MSG_VALUE.toString(16).padStart(4, "0")}`);
  });

  test("blockTimestamp() — path=0x0002", () => {
    expect(blockTimestamp().path).toBe(`0x${ContextProperty.BLOCK_TIMESTAMP.toString(16).padStart(4, "0")}`);
  });

  test("blockNumber() — path=0x0003", () => {
    expect(blockNumber().path).toBe(`0x${ContextProperty.BLOCK_NUMBER.toString(16).padStart(4, "0")}`);
  });

  test("chainId() — path=0x0004", () => {
    expect(chainId().path).toBe(`0x${ContextProperty.CHAIN_ID.toString(16).padStart(4, "0")}`);
  });

  test("txOrigin() — path=0x0005", () => {
    expect(txOrigin().path).toBe(`0x${ContextProperty.TX_ORIGIN.toString(16).padStart(4, "0")}`);
  });
});

///////////////////////////////////////////////////////////////////////////
// Value operators
///////////////////////////////////////////////////////////////////////////

describe(".eq() / .neq()", () => {
  test(".eq(42n) — opCode=0x01, last byte=0x2a, total length=33 bytes", () => {
    const c = arg(0).eq(42n);
    expect(c.operators).toHaveLength(1);
    const op = c.operators[0];
    // 0x + 2 chars opCode + 64 chars data = 68 chars total
    expect(op).toHaveLength(2 + 2 + 64);
    expect(op.slice(2, 4)).toBe(Op.EQ.toString(16).padStart(2, "0"));
    expect(op.slice(-2)).toBe("2a");
  });

  test(".neq(42n) — opCode=0x81", () => {
    const op = arg(0).neq(42n).operators[0];
    expect(op.slice(2, 4)).toBe((Op.EQ | Op.NOT).toString(16).padStart(2, "0"));
  });

  test(".gt() — opCode=0x02", () => {
    const op = arg(0).gt(1n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.GT.toString(16).padStart(2, "0"));
  });

  test(".lt() — opCode=0x03", () => {
    const op = arg(0).lt(1n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.LT.toString(16).padStart(2, "0"));
  });

  test(".gte() — opCode=0x04", () => {
    const op = arg(0).gte(1n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.GTE.toString(16).padStart(2, "0"));
  });

  test(".lte() — opCode=0x05", () => {
    const op = arg(0).lte(1n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.LTE.toString(16).padStart(2, "0"));
  });
});

describe(".between()", () => {
  test(".between(10n, 100n) — opCode=0x06, 65 bytes total", () => {
    const op = arg(0).between(10n, 100n).operators[0];
    // 0x + 2 opCode + 128 data = 132 chars
    expect(op).toHaveLength(2 + 2 + 128);
    expect(op.slice(2, 4)).toBe(Op.BETWEEN.toString(16).padStart(2, "0"));
  });

  test(".between(100n, 10n) — throws (min > max)", () => {
    expect(() => arg(0).between(100n, 10n)).toThrow(CallciumError);
  });
});

///////////////////////////////////////////////////////////////////////////
// Boolean and address encoding
///////////////////////////////////////////////////////////////////////////

describe("value encoding", () => {
  test(".eq(true) — last byte=0x01", () => {
    const op = arg(0).eq(true).operators[0];
    expect(op.slice(-2)).toBe("01");
  });

  test(".eq(false) — last byte=0x00", () => {
    const op = arg(0).eq(false).operators[0];
    expect(op.slice(-2)).toBe("00");
  });

  test(".eq(address) — 12 zero bytes + 20 address bytes", () => {
    const addr = "0x0000000000000000000000000000000000000001";
    const op = arg(0).eq(addr).operators[0];
    // data portion starts at index 4 (after "0x" + opCode byte)
    const data = op.slice(4); // 64 hex chars = 32 bytes
    expect(data.slice(0, 24)).toBe("000000000000000000000000"); // 12 zero bytes
    expect(data.slice(24)).toBe("0000000000000000000000000000000000000001");
  });
});

///////////////////////////////////////////////////////////////////////////
// Operator accumulation
///////////////////////////////////////////////////////////////////////////

describe("operator accumulation", () => {
  test(".gte(10n).lte(100n) — 2 operators", () => {
    const c = arg(0).gte(10n).lte(100n);
    expect(c.operators).toHaveLength(2);
    expect(c.operators[0].slice(2, 4)).toBe(Op.GTE.toString(16).padStart(2, "0"));
    expect(c.operators[1].slice(2, 4)).toBe(Op.LTE.toString(16).padStart(2, "0"));
  });
});

///////////////////////////////////////////////////////////////////////////
// Set membership
///////////////////////////////////////////////////////////////////////////

describe(".isIn() / .notIn()", () => {
  test(".isIn([3n, 1n, 2n, 1n]) — sorted, deduped: 3 values, opCode=0x07", () => {
    const op = arg(0).isIn([3n, 1n, 2n, 1n]).operators[0];
    expect(op.slice(2, 4)).toBe(Op.IN.toString(16).padStart(2, "0"));
    // 3 values × 32 bytes = 96 bytes = 192 hex chars + 2 (opCode) + 2 (0x) = 196
    expect(op).toHaveLength(2 + 2 + 192);
    // Verify sorted order: first word = 1, last word = 3
    const data = op.slice(4);
    const word1 = BigInt("0x" + data.slice(0, 64));
    const word2 = BigInt("0x" + data.slice(64, 128));
    const word3 = BigInt("0x" + data.slice(128, 192));
    expect(word1).toBe(1n);
    expect(word2).toBe(2n);
    expect(word3).toBe(3n);
  });

  test(".notIn([1n, 2n]) — opCode=0x87", () => {
    const op = arg(0).notIn([1n, 2n]).operators[0];
    expect(op.slice(2, 4)).toBe((Op.IN | Op.NOT).toString(16).padStart(2, "0"));
  });

  test(".isIn([true, false]) — boolean values encoded as 1n and 0n", () => {
    const c = arg(0).isIn([true, false]);
    const opHex = c.operators[0];
    const data = opHex.slice(4);
    // Sorted: false (0) first, true (1) second.
    expect(BigInt("0x" + data.slice(0, 64))).toBe(0n);
    expect(BigInt("0x" + data.slice(64, 128))).toBe(1n);
  });

  test(".isIn([]) — throws EMPTY_SET", () => {
    expect(() => arg(0).isIn([])).toThrow(CallciumError);
    try {
      arg(0).isIn([]);
    } catch (e) {
      if (e instanceof CallciumError) {
        expect(e.code).toBe("EMPTY_SET");
      }
    }
  });
});

///////////////////////////////////////////////////////////////////////////
// Bitmask operators
///////////////////////////////////////////////////////////////////////////

describe("bitmask operators", () => {
  test(".bitmaskAll(0xffn) — opCode=0x10", () => {
    const op = arg(0).bitmaskAll(0xffn).operators[0];
    expect(op.slice(2, 4)).toBe(Op.BITMASK_ALL.toString(16).padStart(2, "0"));
  });

  test(".bitmaskAny() — opCode=0x11", () => {
    const op = arg(0).bitmaskAny(0x0fn).operators[0];
    expect(op.slice(2, 4)).toBe(Op.BITMASK_ANY.toString(16).padStart(2, "0"));
  });

  test(".bitmaskNone() — opCode=0x12", () => {
    const op = arg(0).bitmaskNone(0x01n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.BITMASK_NONE.toString(16).padStart(2, "0"));
  });
});

///////////////////////////////////////////////////////////////////////////
// Length operators
///////////////////////////////////////////////////////////////////////////

describe("length operators", () => {
  test(".lengthEq(10n) — opCode=0x20", () => {
    const op = arg(0).lengthEq(10n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.LENGTH_EQ.toString(16).padStart(2, "0"));
  });

  test(".lengthGt() — opCode=0x21", () => {
    const op = arg(0).lengthGt(5n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.LENGTH_GT.toString(16).padStart(2, "0"));
  });

  test(".lengthLt() — opCode=0x22", () => {
    const op = arg(0).lengthLt(5n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.LENGTH_LT.toString(16).padStart(2, "0"));
  });

  test(".lengthGte() — opCode=0x23", () => {
    const op = arg(0).lengthGte(5n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.LENGTH_GTE.toString(16).padStart(2, "0"));
  });

  test(".lengthLte() — opCode=0x24", () => {
    const op = arg(0).lengthLte(5n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.LENGTH_LTE.toString(16).padStart(2, "0"));
  });

  test(".lengthBetween(1n, 100n) — opCode=0x25, 65 bytes total", () => {
    const op = arg(0).lengthBetween(1n, 100n).operators[0];
    expect(op.slice(2, 4)).toBe(Op.LENGTH_BETWEEN.toString(16).padStart(2, "0"));
    expect(op).toHaveLength(2 + 2 + 128);
  });

  test(".lengthBetween(100n, 1n) — throws", () => {
    expect(() => arg(0).lengthBetween(100n, 1n)).toThrow(CallciumError);
  });

  test("rejects address with invalid hex characters", () => {
    expect(() => arg(0).eq("0xGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG")).toThrow(CallciumError);
  });

  test("rejects address with wrong length", () => {
    expect(() => arg(0).eq("0x1234")).toThrow(CallciumError);
  });
});

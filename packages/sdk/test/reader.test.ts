import { describe, expect, test } from "vitest";

import { load32, readPointer } from "../src/reader";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** Encode a uint256 value as 32 bytes (big-endian). */
function word(value: number): Uint8Array {
  const buf = new Uint8Array(32);
  buf[28] = (value >>> 24) & 0xff;
  buf[29] = (value >>> 16) & 0xff;
  buf[30] = (value >>> 8) & 0xff;
  buf[31] = value & 0xff;
  return buf;
}

/** Concatenate multiple Uint8Arrays. */
function concat(...arrays: Uint8Array[]): Uint8Array {
  const total = arrays.reduce((sum, arr) => sum + arr.length, 0);
  const result = new Uint8Array(total);
  let offset = 0;
  for (const arr of arrays) {
    result.set(arr, offset);
    offset += arr.length;
  }
  return result;
}

///////////////////////////////////////////////////////////////////////////
// load32 and readPointer
///////////////////////////////////////////////////////////////////////////

describe("load32", () => {
  test("reads 32 bytes at offset 0", () => {
    const callData = word(42);
    const result = load32(callData, 0);
    expect(result).toBeInstanceOf(Uint8Array);
    if (result instanceof Uint8Array) {
      expect(result[31]).toBe(42);
    }
  });

  test("reads 32 bytes at nonzero offset", () => {
    const callData = concat(word(0), word(99));
    const result = load32(callData, 32);
    expect(result).toBeInstanceOf(Uint8Array);
    if (result instanceof Uint8Array) {
      expect(result[31]).toBe(99);
    }
  });

  test("returns CALLDATA_OUT_OF_BOUNDS when offset exceeds bounds", () => {
    const callData = word(1);
    const result = load32(callData, 1);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("returns CALLDATA_OUT_OF_BOUNDS for empty callData", () => {
    const result = load32(new Uint8Array(0), 0);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("returns CALLDATA_OUT_OF_BOUNDS for negative offset", () => {
    const result = load32(word(1), -1);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("succeeds at exact boundary (offset + 32 == length)", () => {
    const callData = word(7);
    const result = load32(callData, 0);
    expect(result).toBeInstanceOf(Uint8Array);
  });
});

describe("readPointer", () => {
  test("reads a small value", () => {
    const callData = word(0x60);
    const result = readPointer(callData, 0);
    expect(result).toBe(0x60);
  });

  test("reads zero", () => {
    const result = readPointer(word(0), 0);
    expect(result).toBe(0);
  });

  test("reads max uint32", () => {
    // 0xFFFFFFFF in the last 4 bytes.
    const buf = new Uint8Array(32);
    buf[28] = 0xff;
    buf[29] = 0xff;
    buf[30] = 0xff;
    buf[31] = 0xff;
    const result = readPointer(buf, 0);
    expect(result).toBe(0xffffffff);
  });

  test("rejects value with nonzero high bytes", () => {
    const buf = new Uint8Array(32);
    buf[0] = 1; // High byte nonzero
    const result = readPointer(buf, 0);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("rejects value with byte 27 nonzero", () => {
    const buf = new Uint8Array(32);
    buf[27] = 1;
    const result = readPointer(buf, 0);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("propagates CALLDATA_OUT_OF_BOUNDS", () => {
    const result = readPointer(new Uint8Array(16), 0);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });
});

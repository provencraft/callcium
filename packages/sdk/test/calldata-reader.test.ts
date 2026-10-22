import { describe, expect, test } from "vitest";

import { loadWord, readPointer } from "../src/calldata-reader";
import { word, words } from "./helpers";

describe("loadWord", () => {
  test("succeeds at exact boundary (offset + 32 == length)", () => {
    const callData = words(0n, 0n, 7n);
    const result = loadWord(callData, callData.length - 32);
    expect(result).toBeInstanceOf(Uint8Array);
    if (result instanceof Uint8Array) {
      expect(result[31]).toBe(7);
    }
  });

  test("returns CALLDATA_OUT_OF_BOUNDS when offset exceeds bounds", () => {
    const callData = word(1n);
    const result = loadWord(callData, 1);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("returns CALLDATA_OUT_OF_BOUNDS for negative offset", () => {
    const result = loadWord(word(1n), -1);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });
});

describe("readPointer", () => {
  test("reads max uint32", () => {
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
    buf[0] = 1;
    const result = readPointer(buf, 0);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("propagates CALLDATA_OUT_OF_BOUNDS", () => {
    const result = readPointer(new Uint8Array(16), 0);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });
});

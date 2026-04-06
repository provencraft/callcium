import { describe, expect, test } from "vitest";

import { bytesToHex, hexToBytes } from "../src/hex";

describe("hexToBytes", () => {
  test("converts 0x-prefixed hex", () => {
    expect(hexToBytes("0x0102ff")).toEqual(new Uint8Array([0x01, 0x02, 0xff]));
  });

  test("converts empty hex", () => {
    expect(hexToBytes("0x")).toEqual(new Uint8Array([]));
  });

  test("throws on odd-length hex", () => {
    expect(() => hexToBytes("0x123")).toThrow("Odd-length hex string");
  });
});

describe("bytesToHex", () => {
  test("converts bytes to 0x-prefixed hex", () => {
    expect(bytesToHex(new Uint8Array([0x01, 0x02, 0xff]))).toBe("0x0102ff");
  });

  test("converts empty bytes", () => {
    expect(bytesToHex(new Uint8Array([]))).toBe("0x");
  });

  test("pads single-digit values", () => {
    expect(bytesToHex(new Uint8Array([0x00, 0x0a]))).toBe("0x000a");
  });
});

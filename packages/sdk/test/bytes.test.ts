import { describe, expect, test } from "vitest";

import { bytesToHex, hexToBytes, toAddress } from "../src/bytes";

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

  test("throws on invalid hex characters", () => {
    expect(() => hexToBytes("0xGG")).toThrow("Invalid hex characters");
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

describe("toAddress", () => {
  test("accepts valid 40-char hex with prefix", () => {
    const addr = toAddress("0x" + "ab".repeat(20));
    expect(addr).toBe("0x" + "ab".repeat(20));
  });

  test("throws on too-short address (39 hex chars)", () => {
    expect(() => toAddress("0x" + "a".repeat(39))).toThrow("expected 40 hex chars, got 39");
  });

  test("throws on too-long address (41 hex chars)", () => {
    expect(() => toAddress("0x" + "a".repeat(41))).toThrow("expected 40 hex chars, got 41");
  });

  test("throws on invalid hex characters in address", () => {
    expect(() => toAddress("0x" + "GG".repeat(20))).toThrow("Invalid hex characters");
  });
});

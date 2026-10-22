import { describe, expect, test } from "vitest";

import { hexToBytes, toAddress } from "../src/bytes";
import { expectErrorCode } from "./helpers";

describe("hexToBytes", () => {
  test("converts hex with no 0x prefix", () => {
    expect(hexToBytes("0102ff")).toEqual(new Uint8Array([0x01, 0x02, 0xff]));
  });

  test("throws on odd-length hex", () => {
    expect(expectErrorCode(() => hexToBytes("0x123"), "INVALID_HEX").message).toBe("Odd-length hex string");
  });

  test("throws on a value that is not a string", () => {
    const notString: string = JSON.parse("42");
    expectErrorCode(() => hexToBytes(notString), "INVALID_HEX");
  });

  test("throws on invalid hex characters", () => {
    expect(expectErrorCode(() => hexToBytes("0xGG"), "INVALID_HEX").message).toBe("Invalid hex characters");
  });
});

describe("toAddress", () => {
  test("throws on too-short address (39 hex chars)", () => {
    expect(expectErrorCode(() => toAddress("0x" + "a".repeat(39)), "INVALID_HEX").message).toBe(
      "Invalid address length: expected 40 hex chars, got 39",
    );
  });

  test("throws on too-long address (41 hex chars)", () => {
    expect(expectErrorCode(() => toAddress("0x" + "a".repeat(41)), "INVALID_HEX").message).toBe(
      "Invalid address length: expected 40 hex chars, got 41",
    );
  });

  test("throws on invalid hex characters in address", () => {
    expect(expectErrorCode(() => toAddress("0x" + "GG".repeat(20)), "INVALID_HEX").message).toBe(
      "Invalid hex characters in address",
    );
  });
});

import { describe, expect, test } from "vitest";

import { hexToBytes } from "../src/bytes";
import { DescriptorFormat as DF } from "../src/constants";
import { Descriptor } from "../src/descriptor";
import { expectErrorCode } from "./helpers";

describe("Descriptor.paramCount", () => {
  test("throws MALFORMED_HEADER for a buffer too short to hold a header", () => {
    expectErrorCode(() => Descriptor.paramCount(new Uint8Array(0)), "MALFORMED_HEADER");
  });
});

describe("Descriptor.inspect", () => {
  test("throws UNEXPECTED_END for a node starting past the descriptor", () => {
    const desc = new Uint8Array([DF.VERSION, 0x01]);
    expectErrorCode(() => Descriptor.inspect(desc, DF.HEADER_SIZE), "UNEXPECTED_END");
  });
});

describe("Descriptor.validateMeta", () => {
  test("rejects a node length other than the span of the node's children", () => {
    // Tuple of (uint256,uint256) declaring nodeLength 9 over fields spanning 8, then a trailing byte.
    const desc = hexToBytes("0x0201900020090002202020");
    expect(expectErrorCode(() => Descriptor.validateMeta(desc), "NODE_LENGTH_MISMATCH").offset).toBe(2);
  });

  test("names the inner node when an inner node disagrees", () => {
    // Tuple of ((uint256,bytes)) whose inner tuple, at offset 8, declares staticWords 2.
    const desc = hexToBytes("0x02019000000e00019000200800022070");
    expect(expectErrorCode(() => Descriptor.validateMeta(desc), "STATIC_WORDS_MISMATCH").offset).toBe(8);
  });

  test("names the element node when an array's element disagrees", () => {
    // Dynamic array of (uint256,bytes) whose element, at offset 6, declares staticWords 2.
    const desc = hexToBytes("0x02018100000c9000200800022070");
    expect(expectErrorCode(() => Descriptor.validateMeta(desc), "STATIC_WORDS_MISMATCH").offset).toBe(6);
  });
});

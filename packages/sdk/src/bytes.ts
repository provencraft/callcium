import { bytesToHex as encodeHex, hexToBytes as decodeHex } from "@noble/hashes/utils.js";

import { CallciumError } from "./errors";

import type { Address, Hex } from "./types";

const hexBodyPattern = /^[0-9a-fA-F]*$/;

/** Convert a hex string to a byte array, stripping the 0x prefix if present. */
export function hexToBytes(hex: string): Uint8Array {
  if (typeof hex !== "string") throw new CallciumError("INVALID_HEX", "Hex value is not a string");
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) {
    throw new CallciumError("INVALID_HEX", "Odd-length hex string");
  }
  try {
    return decodeHex(clean);
  } catch {
    throw new CallciumError("INVALID_HEX", "Invalid hex characters");
  }
}

/** Convert a byte array to a 0x-prefixed lowercase hex string. */
export function bytesToHex(bytes: Uint8Array): Hex {
  return `0x${encodeHex(bytes)}`;
}

/** Extract a subarray and return it as a 0x-prefixed hex string. */
export function toHex(data: Uint8Array, start: number, end: number): Hex {
  return bytesToHex(data.subarray(start, end));
}

/** Read a big-endian uint16 from a byte array at the given offset. */
export function readU16(data: Uint8Array, offset: number): number {
  return (data[offset]! << 8) | data[offset + 1]!;
}

/** Read a big-endian uint24 from a byte array at the given offset. */
export function readU24(data: Uint8Array, offset: number): number {
  return (data[offset]! << 16) | (data[offset + 1]! << 8) | data[offset + 2]!;
}

/** Read a big-endian uint32 from a byte array at the given offset. */
export function readU32(data: Uint8Array, offset: number): number {
  return ((data[offset]! << 24) | (data[offset + 1]! << 16) | (data[offset + 2]! << 8) | data[offset + 3]!) >>> 0;
}

/** Write a 16-bit big-endian value into a Uint8Array at offset. */
export function writeBE16(buffer: Uint8Array, offset: number, value: number): void {
  buffer[offset] = (value >>> 8) & 0xff;
  buffer[offset + 1] = value & 0xff;
}

/** Write a 24-bit big-endian value into a Uint8Array at offset. */
export function writeBE24(buffer: Uint8Array, offset: number, value: number): void {
  buffer[offset] = (value >>> 16) & 0xff;
  buffer[offset + 1] = (value >>> 8) & 0xff;
  buffer[offset + 2] = value & 0xff;
}

/** Write a 32-bit big-endian value into a Uint8Array at offset. */
export function writeBE32(buffer: Uint8Array, offset: number, value: number): void {
  buffer[offset] = (value >>> 24) & 0xff;
  buffer[offset + 1] = (value >>> 16) & 0xff;
  buffer[offset + 2] = (value >>> 8) & 0xff;
  buffer[offset + 3] = value & 0xff;
}

/** Format a bigint as a zero-padded 32-byte hex string. */
export function bigintToHex(value: bigint): Hex {
  return `0x${value.toString(16).padStart(64, "0")}`;
}

/** Validate and brand a hex string as an address. Throws if the body is not exactly 40 hex characters. */
export function toAddress(hex: string): Address {
  const body = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (body.length !== 40) {
    throw new CallciumError("INVALID_HEX", `Invalid address length: expected 40 hex chars, got ${body.length}`);
  }
  if (!hexBodyPattern.test(body)) {
    throw new CallciumError("INVALID_HEX", "Invalid hex characters in address");
  }
  return `0x${body}`;
}

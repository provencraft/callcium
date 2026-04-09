import { CallciumError } from "./errors";

import type { Address, Hex } from "./types";

/** Regex that matches a valid hex body (even number of hex chars). */
const HEX_BODY_RE = /^[0-9a-fA-F]*$/;

/** Convert a hex string to a byte array, stripping the 0x prefix if present. */
export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) {
    throw new CallciumError("INVALID_HEX", "Odd-length hex string");
  }
  if (!HEX_BODY_RE.test(clean)) {
    throw new CallciumError("INVALID_HEX", "Invalid hex characters");
  }
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
  }
  return bytes;
}

// Pre-computed hex lookup avoids per-byte toString + padStart in the hot path.
const HEX_LUT = Array.from({ length: 256 }, (_, i) => i.toString(16).padStart(2, "0"));

/** Convert a byte array to a 0x-prefixed lowercase hex string. */
export function bytesToHex(bytes: Uint8Array): Hex {
  let body = "";
  for (let i = 0; i < bytes.length; i++) body += HEX_LUT[bytes[i]!];
  return `0x${body}`;
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
export function writeBE16(buf: Uint8Array, offset: number, value: number): void {
  buf[offset] = (value >>> 8) & 0xff;
  buf[offset + 1] = value & 0xff;
}

/** Write a 24-bit big-endian value into a Uint8Array at offset. */
export function writeBE24(buf: Uint8Array, offset: number, value: number): void {
  buf[offset] = (value >>> 16) & 0xff;
  buf[offset + 1] = (value >>> 8) & 0xff;
  buf[offset + 2] = value & 0xff;
}

/** Format a bigint as a zero-padded 32-byte hex string. */
export function bigintToHex(value: bigint): Hex {
  return `0x${value.toString(16).padStart(64, "0")}`;
}

/** Validate and brand a hex string as an address. Throws if the runtime length is not exactly 20 bytes. */
export function toAddress(hex: string): Address {
  const body = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (body.length !== 40) {
    throw new CallciumError("INVALID_HEX", `Invalid address length: expected 40 hex chars, got ${body.length}`);
  }
  if (!HEX_BODY_RE.test(body)) {
    throw new CallciumError("INVALID_HEX", "Invalid hex characters in address");
  }
  return `0x${body}`;
}

import type { Address, Hex } from "./types";

/** Convert a hex string to a byte array, stripping the 0x prefix if present. */
export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) {
    throw new Error("Odd-length hex string");
  }
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
  }
  return bytes;
}

/** Convert a byte array to a 0x-prefixed lowercase hex string. */
export function bytesToHex(bytes: Uint8Array): Hex {
  let body = "";
  for (let i = 0; i < bytes.length; i++) {
    body += bytes[i]!.toString(16).padStart(2, "0");
  }
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

/** Validate and brand a hex string as an address. Throws if the runtime length is not exactly 20 bytes. */
export function toAddress(hex: string): Address {
  const body = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (body.length !== 40) {
    throw new Error(`Invalid address length: expected 40 hex chars, got ${body.length}`);
  }
  return `0x${body}`;
}

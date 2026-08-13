import type { NavigationViolationCode } from "./types";

///////////////////////////////////////////////////////////////////////////
// Result types
///////////////////////////////////////////////////////////////////////////

/** Result of a calldata read: success with data, or failure with a navigation violation code. */
export type ReadResult<T> = T | { code: NavigationViolationCode };

///////////////////////////////////////////////////////////////////////////
// Calldata reading primitives
///////////////////////////////////////////////////////////////////////////

/** Read 32 bytes at offset, bounds-checked. */
export function load32(callData: Uint8Array, offset: number): ReadResult<Uint8Array> {
  if (offset < 0 || offset + 32 > callData.length) {
    return { code: "CALLDATA_OUT_OF_BOUNDS" };
  }
  return callData.subarray(offset, offset + 32);
}

/**
 * Read ABI pointer (offset or length) from a 32-byte slot.
 * Validates high 28 bytes are zero (rejects values > 32-bit).
 */
export function readPointer(callData: Uint8Array, head: number): ReadResult<number> {
  const word = load32(callData, head);
  if (word instanceof Uint8Array) {
    for (let i = 0; i < 28; i++) {
      if (word[i] !== 0) return { code: "CALLDATA_OUT_OF_BOUNDS" };
    }
    return ((word[28]! << 24) | (word[29]! << 16) | (word[30]! << 8) | word[31]!) >>> 0;
  }
  return word; // propagate CALLDATA_OUT_OF_BOUNDS
}

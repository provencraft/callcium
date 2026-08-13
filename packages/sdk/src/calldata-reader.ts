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
export function loadWord(callData: Uint8Array, offset: number): ReadResult<Uint8Array> {
  if (offset < 0 || offset + 32 > callData.length) {
    return { code: "CALLDATA_OUT_OF_BOUNDS" };
  }
  return callData.subarray(offset, offset + 32);
}

/**
 * Read an ABI pointer (offset or length) from a 32-byte slot.
 *
 * A number cannot hold a 256-bit word, so the high 28 bytes must be zero for the narrowing to be
 * lossless; a wider value is rejected as out of bounds, which is the verdict a bounds comparison
 * over the full word reaches for any offset that far past the end of calldata.
 */
export function readPointer(callData: Uint8Array, head: number): ReadResult<number> {
  const word = loadWord(callData, head);
  if (word instanceof Uint8Array) {
    for (let i = 0; i < 28; i++) {
      if (word[i] !== 0) return { code: "CALLDATA_OUT_OF_BOUNDS" };
    }
    return ((word[28]! << 24) | (word[29]! << 16) | (word[30]! << 8) | word[31]!) >>> 0;
  }
  return word; // propagate CALLDATA_OUT_OF_BOUNDS
}

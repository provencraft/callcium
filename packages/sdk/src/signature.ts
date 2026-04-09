import { keccak_256 } from "@noble/hashes/sha3";

import { CallciumError } from "./errors";
import { bytesToHex } from "./hex";

import type { Hex } from "./types";

///////////////////////////////////////////////////////////////////////////
// SignatureParser
///////////////////////////////////////////////////////////////////////////

/** Parsed components of an ABI function signature. */
export type ParsedSignature = {
  /** The 4-byte function selector as a 0x-prefixed hex string. */
  selector: Hex;
  /** Comma-separated parameter types, empty string for no-argument functions. */
  types: string;
};

/** Return true if the char code is an ASCII letter. */
function _isAlpha(c: number): boolean {
  return (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);
}

/** Return true if the char code is an ASCII alphanumeric character. */
function _isAlphanum(c: number): boolean {
  return _isAlpha(c) || (c >= 0x30 && c <= 0x39);
}

export const SignatureParser = {
  /**
   * Parse an ABI function signature into its selector and types.
   *
   * Strict mode: no whitespace, name must match `[A-Za-z_][A-Za-z0-9_]*`,
   * structure must be `name(types)` with the final `)` as the last character.
   *
   * @param signature - A function signature string, e.g. `"transfer(address,uint256)"`.
   * @returns The 4-byte selector and the comma-separated types string.
   * @throws {CallciumError} with code `"INVALID_SIGNATURE"` if the signature is malformed.
   */
  parse(signature: string): ParsedSignature {
    if (signature.length < 3) {
      throw new CallciumError("INVALID_SIGNATURE", `Invalid signature: too short, got "${signature}"`);
    }

    // Scan for whitespace, non-ASCII, and the opening parenthesis in one pass.
    let openParen = -1;
    for (let i = 0; i < signature.length; i++) {
      const c = signature.charCodeAt(i);
      if (c === 0x20 || c === 0x09 || c === 0x0a || c === 0x0d) {
        throw new CallciumError("INVALID_SIGNATURE", "Signature must not contain whitespace");
      }
      if (c > 0x7e) {
        throw new CallciumError("INVALID_SIGNATURE", "Signature must contain only ASCII characters");
      }
      if (openParen === -1 && c === 0x28) {
        openParen = i;
      }
    }

    if (openParen < 1) {
      throw new CallciumError(
        "INVALID_SIGNATURE",
        `Invalid signature: must have a function name followed by parentheses, got "${signature}"`,
      );
    }

    if (!signature.endsWith(")")) {
      throw new CallciumError("INVALID_SIGNATURE", `Invalid signature: must end with ")", got "${signature}"`);
    }

    // Validate function name: [A-Za-z_][A-Za-z0-9_]*.
    const firstChar = signature.charCodeAt(0);
    if (!_isAlpha(firstChar) && firstChar !== 0x5f) {
      throw new CallciumError("INVALID_SIGNATURE", "Function name must start with a letter or underscore");
    }
    for (let i = 1; i < openParen; i++) {
      const c = signature.charCodeAt(i);
      if (!_isAlphanum(c) && c !== 0x5f) {
        throw new CallciumError(
          "INVALID_SIGNATURE",
          "Function name must contain only alphanumeric characters or underscores",
        );
      }
    }

    const types = signature.slice(openParen + 1, signature.length - 1);
    const encoded = new Uint8Array(signature.length);
    for (let i = 0; i < signature.length; i++) encoded[i] = signature.charCodeAt(i);
    const hash = keccak_256(encoded);
    const selector = bytesToHex(hash.subarray(0, 4));

    return { selector, types };
  },
};

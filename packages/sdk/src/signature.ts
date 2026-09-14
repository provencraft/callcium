import { keccak_256 } from "@noble/hashes/sha3.js";
import { utf8ToBytes } from "@noble/hashes/utils.js";

import { bytesToHex } from "./bytes";
import { CallciumError } from "./errors";

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
function isAlpha(char: number): boolean {
  return (char >= 0x41 && char <= 0x5a) || (char >= 0x61 && char <= 0x7a);
}

/** Return true if the char code is an ASCII alphanumeric character. */
function isAlphanum(char: number): boolean {
  return isAlpha(char) || (char >= 0x30 && char <= 0x39);
}

/**
 * Parse an ABI function signature into its selector and types.
 *
 * Strict mode: no whitespace, name must match `[A-Za-z_][A-Za-z0-9_]*`,
 * structure must be `name(types)` with the final `)` as the last character.
 *
 * @param signature - A function signature string, e.g. `"transfer(address,uint256)"`.
 * @returns The 4-byte selector and the comma-separated types string.
 * @throws {CallciumError} with code `"MALFORMED_SIGNATURE"`, `"SIGNATURE_CONTAINS_WHITESPACE"`, or
 * `"INVALID_FUNCTION_NAME"` if the signature is malformed. The types between the parentheses are
 * returned unread; whether they name types is for the type parser to say.
 */
function parse(signature: string): ParsedSignature {
  if (signature.length < 3) {
    throw new CallciumError("MALFORMED_SIGNATURE", `Invalid signature: too short, got "${signature}"`);
  }

  // Scan for whitespace and the opening parenthesis in one pass.
  let openParen = -1;
  for (let i = 0; i < signature.length; i++) {
    const char = signature.charCodeAt(i);
    if (char === 0x20 || char === 0x09 || char === 0x0a || char === 0x0d) {
      throw new CallciumError("SIGNATURE_CONTAINS_WHITESPACE", "Signature must not contain whitespace");
    }
    if (openParen === -1 && char === 0x28) {
      openParen = i;
    }
  }

  if (openParen === -1) {
    throw new CallciumError(
      "MALFORMED_SIGNATURE",
      `Invalid signature: must have a function name followed by parentheses, got "${signature}"`,
    );
  }

  if (!signature.endsWith(")")) {
    throw new CallciumError("MALFORMED_SIGNATURE", `Invalid signature: must end with ")", got "${signature}"`);
  }

  if (openParen === 0) {
    throw new CallciumError("INVALID_FUNCTION_NAME", "Function name must not be empty");
  }

  // Validate function name: [A-Za-z_][A-Za-z0-9_]*. Every character outside ASCII carries a code
  // unit above the alphanumeric ranges, so the same test rejects it.
  const firstChar = signature.charCodeAt(0);
  if (!isAlpha(firstChar) && firstChar !== 0x5f) {
    throw new CallciumError("INVALID_FUNCTION_NAME", "Function name must start with a letter or underscore");
  }
  for (let i = 1; i < openParen; i++) {
    const char = signature.charCodeAt(i);
    if (!isAlphanum(char) && char !== 0x5f) {
      throw new CallciumError(
        "INVALID_FUNCTION_NAME",
        "Function name must contain only alphanumeric characters or underscores",
      );
    }
  }

  const hash = keccak_256(utf8ToBytes(signature));

  const selector = bytesToHex(hash.subarray(0, 4));
  const types = signature.slice(openParen + 1, signature.length - 1);
  return { selector, types };
}

/** ABI function signature parser. */
export const SignatureParser = { parse };

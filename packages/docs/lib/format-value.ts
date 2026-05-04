import { type Hex, lookupOp, TypeCode } from "@callcium/sdk";
import { getAddress } from "viem";

const TWO_POW_256 = 2n ** 256n;
const TWO_POW_255 = 2n ** 255n;

///////////////////////////////////////////////////////////////////////////
// Word normalization
///////////////////////////////////////////////////////////////////////////

/** Normalize a hex string to 64 characters (32 bytes), zero-padding short input on the left. */
function toWord64(hex: Hex): string {
  const body = hex.slice(2);
  if (body.length >= 64) return body.slice(body.length - 64);
  return body.padStart(64, "0");
}

///////////////////////////////////////////////////////////////////////////
// Type-aware decoding
///////////////////////////////////////////////////////////////////////////

/**
 * Decode a single 32-byte ABI word into a human-readable string per type code.
 *
 * Renders integers as decimal, addresses as EIP-55 checksummed hex, bools as
 * `true`/`false`, fixed bytes as the left-aligned hex slice. Unknown types fall
 * back to a `0x`-prefixed hex word.
 */
export function decodeOperand(hex32: string, typeCode: number): string {
  const raw = BigInt(`0x${hex32}`);

  if (typeCode === TypeCode.ADDRESS) {
    const addr = `0x${hex32.slice(24)}`;
    try {
      return getAddress(addr);
    } catch {
      return addr;
    }
  }

  if (typeCode === TypeCode.BOOL) return raw === 0n ? "false" : "true";

  if (typeCode >= TypeCode.INT_MIN && typeCode <= TypeCode.INT_MAX) {
    return raw >= TWO_POW_255 ? (raw - TWO_POW_256).toString() : raw.toString();
  }

  if (typeCode >= TypeCode.UINT_MIN && typeCode <= TypeCode.UINT_MAX) return raw.toString();

  if (typeCode >= TypeCode.FIXED_BYTES_MIN && typeCode <= TypeCode.FIXED_BYTES_MAX) {
    const n = typeCode - TypeCode.FIXED_BYTES_MIN + 1;
    return `0x${hex32.slice(0, n * 2)}`;
  }

  return `0x${hex32}`;
}

/**
 * Split an operand payload into 32-byte hex chunks per operator arity.
 *
 * Variadic operators yield one chunk per 32-byte word, range operators yield
 * two, and the remainder yield one. Returned chunks are bare hex (no `0x`).
 */
export function operandChunks(dataHex: Hex, opBase: number): string[] {
  const hex = dataHex.slice(2);
  const { operands } = lookupOp(opBase);

  if (operands === "variadic") {
    const result: string[] = [];
    for (let i = 0; i < hex.length; i += 64) result.push(hex.slice(i, i + 64));
    return result;
  }
  if (operands === "range") return [hex.slice(0, 64), hex.slice(64, 128)];
  return [hex.slice(0, 64)];
}

/**
 * Decode an operator's operand payload into one human-readable string per operand.
 *
 * Operand arity is resolved from the operator code via `operandChunks`. Each
 * chunk is decoded against the supplied type code.
 */
export function decodeOperandsFromData(dataHex: Hex, typeCode: number, opBase: number): string[] {
  return operandChunks(dataHex, opBase).map((chunk) => decodeOperand(chunk, typeCode));
}

/**
 * Decode a single hex value into a human-readable string per type code.
 *
 * Defensively normalizes inputs to a 32-byte word — callers passing a full ABI
 * word receive lossless decoding (essential for left-aligned `bytesN`); callers
 * passing compact bigint hex receive correct decoding for right-aligned types
 * (integers, addresses, bools) at the cost of zeroed high bytes for fixed-bytes
 * types.
 */
export function decodeValue(hex: Hex, typeCode: number): string {
  return decodeOperand(toWord64(hex), typeCode);
}

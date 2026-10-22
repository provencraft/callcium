import { type DecodedOperator, type Hex, lookupContextProperty, type Operands, Source, TypeCode } from "@callcium/sdk";
import { getAddress } from "viem";

const TWO_POW_256 = 2n ** 256n;
const TWO_POW_255 = 2n ** 255n;

///////////////////////////////////////////////////////////////////////////
// Type-aware decoding
///////////////////////////////////////////////////////////////////////////

/**
 * Decode a single 32-byte ABI word into a human-readable string per type code.
 *
 * Renders integers as decimal, addresses as EIP-55 checksummed hex, bools as `true`/`false`, fixed bytes as the
 * left-aligned hex slice. Unknown types fall back to a `0x`-prefixed hex word.
 */
function decodeOperand(hex32: string, typeCode: number): string {
  const raw = BigInt(`0x${hex32}`);

  if (typeCode === TypeCode.ADDRESS) {
    const address = `0x${hex32.slice(24)}`;
    try {
      return getAddress(address);
    } catch {
      return address;
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
 * Decode an operator's operands into one human-readable string each: a constant per the operand type, a context operand
 * as its property's label.
 */
export function decodeOperands(operator: DecodedOperator): string[] {
  if (operator.source === Source.CONTEXT) return [lookupContextProperty(operator.contextPropertyId).label];
  return operator.values.map((value) => decodeValue(value, operator.operandType));
}

/** Decode a 32-byte word into a human-readable string per type code. */
export function decodeValue(word: Hex, typeCode: number): string {
  return decodeOperand(word.slice(2), typeCode);
}

///////////////////////////////////////////////////////////////////////////
// Operand list rendering
///////////////////////////////////////////////////////////////////////////

/**
 * Join rendered operands into one display string, bracketed by operator arity.
 *
 * A set is braced (`{a, b}`), matching the spec's notation for `OP_IN`; an inclusive range is bracketed (`[lo, hi]`). A
 * single operand carries no brackets.
 */
export function formatOperandList(arity: Operands, operands: readonly string[]): string {
  if (arity === "variadic") return `{${operands.join(", ")}}`;
  if (arity === "range") return `[${operands.join(", ")}]`;
  return operands.join(", ");
}

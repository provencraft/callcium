import { Op, TypeCode } from "./constants";
import { CallciumError } from "./errors";

/** Read a big-endian 256-bit unsigned integer from a 32-byte window. */
export function toBigInt(bytes: Uint8Array, offset = 0): bigint {
  const view = new DataView(bytes.buffer, bytes.byteOffset + offset, 32);
  return (
    (view.getBigUint64(0, false) << 192n) |
    (view.getBigUint64(8, false) << 128n) |
    (view.getBigUint64(16, false) << 64n) |
    view.getBigUint64(24, false)
  );
}

/** Return true when the type code represents a signed integer (int8 through int256). */
export function isSigned(typeCode: number): boolean {
  return typeCode >= TypeCode.INT_MIN && typeCode <= TypeCode.INT_MAX;
}

/**
 * Canonicalize a raw 256-bit calldata word to its ABI value for the declared type (Policy Spec §7.8).
 * A scalar loaded from untrusted calldata may carry bits outside the declared width; masking
 * unsigned/address/bool/function/bytesN to width and sign-extending signed integers makes the
 * comparison use the canonical ABI value rather than the raw bytes.
 * @param value - The raw 256-bit word loaded from calldata.
 * @param typeCode - The declared type code of the value.
 * @returns The canonicalized 256-bit value.
 */
export function canonicalize(value: bigint, typeCode: number): bigint {
  // Unsigned integers: mask to the low N bits.
  if (typeCode <= TypeCode.UINT_MAX) {
    const bits = BigInt((typeCode + 1) * 8);
    return bits === 256n ? value : value & ((1n << bits) - 1n);
  }

  // Signed integers: sign-extend from the type's most-significant byte.
  if (typeCode <= TypeCode.INT_MAX) {
    const bits = (typeCode - TypeCode.INT_MIN + 1) * 8;
    return bits === 256 ? value : BigInt.asUintN(256, BigInt.asIntN(bits, value));
  }

  // Address: mask to the low 160 bits.
  if (typeCode === TypeCode.ADDRESS) return value & ((1n << 160n) - 1n);

  // Boolean: collapse to the low bit.
  if (typeCode === TypeCode.BOOL) return value & 1n;

  // Function pointer: encoded identical to bytes24 (left-aligned), clear the low 8 padding bytes.
  if (typeCode === TypeCode.FUNCTION) return (value >> 64n) << 64n;

  // Fixed bytes: left-aligned, clear the low (32 - N) padding bytes.
  if (typeCode >= TypeCode.FIXED_BYTES_MIN && typeCode <= TypeCode.FIXED_BYTES_MAX) {
    const n = typeCode - TypeCode.FIXED_BYTES_MIN + 1;
    if (n === 32) return value;
    const padBits = BigInt((32 - n) * 8);
    return (value >> padBits) << padBits;
  }

  return value;
}

/** Return true when the operator code (with or without NOT flag) is a LENGTH_* variant. */
export function isLengthOp(opCode: number): boolean {
  const base = opCode & ~Op.NOT;
  return base >= Op.LENGTH_EQ && base <= Op.LENGTH_BETWEEN;
}

/** Return true when LENGTH_* operators are valid for the given type code (bytes, string, or dynamic array). */
export function isLengthValidType(typeCode: number): boolean {
  return typeCode === TypeCode.BYTES || typeCode === TypeCode.STRING || typeCode === TypeCode.DYNAMIC_ARRAY;
}

/** Compare two 256-bit values, using two's complement interpretation for signed type codes. */
function compareTyped(a: bigint, b: bigint, typeCode: number): number {
  if (isSigned(typeCode)) {
    const sa = BigInt.asIntN(256, a);
    const sb = BigInt.asIntN(256, b);
    return sa < sb ? -1 : sa > sb ? 1 : 0;
  }
  return a < b ? -1 : a > b ? 1 : 0;
}

/** Binary search over a sorted array of 32-byte words. Comparison is always unsigned. */
function isIn(value: bigint, data: Uint8Array): boolean {
  const count = data.length / 32;
  let lo = 0;
  let hi = count - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >>> 1;
    const elem = toBigInt(data, mid * 32);
    if (value === elem) return true;
    if (value < elem) hi = mid - 1;
    else lo = mid + 1;
  }
  return false;
}

/**
 * Apply a single operator against a value and operand data.
 * Handles the NOT flag internally by inverting the base operator result.
 * @param opCode - Operator code, potentially OR'd with the NOT flag.
 * @param value - The 256-bit value to test (ignored for LENGTH_* operators).
 * @param valueLength - Runtime byte or element count, only meaningful for LENGTH_* operators.
 * @param operandData - Raw operand bytes (32 per operand, 64 for range operators).
 * @param typeCode - ABI type code, used to select signed vs. unsigned comparison.
 * @returns Whether the value satisfies the operator.
 */
export function applyOperator(
  opCode: number,
  value: bigint,
  valueLength: number,
  operandData: Uint8Array,
  typeCode: number,
): boolean {
  const negate = (opCode & Op.NOT) !== 0;
  const base = opCode & ~Op.NOT;

  let result: boolean;

  switch (base) {
    case Op.EQ:
      result = value === toBigInt(operandData, 0);
      break;

    case Op.GT:
      result = compareTyped(value, toBigInt(operandData, 0), typeCode) > 0;
      break;

    case Op.LT:
      result = compareTyped(value, toBigInt(operandData, 0), typeCode) < 0;
      break;

    case Op.GTE:
      result = compareTyped(value, toBigInt(operandData, 0), typeCode) >= 0;
      break;

    case Op.LTE:
      result = compareTyped(value, toBigInt(operandData, 0), typeCode) <= 0;
      break;

    case Op.BETWEEN: {
      const min = toBigInt(operandData, 0);
      const max = toBigInt(operandData, 32);
      result = compareTyped(value, min, typeCode) >= 0 && compareTyped(value, max, typeCode) <= 0;
      break;
    }

    case Op.IN:
      result = isIn(value, operandData);
      break;

    case Op.BITMASK_ALL: {
      const mask = toBigInt(operandData, 0);
      result = (value & mask) === mask;
      break;
    }

    case Op.BITMASK_ANY: {
      const mask = toBigInt(operandData, 0);
      result = (value & mask) !== 0n;
      break;
    }

    case Op.BITMASK_NONE: {
      const mask = toBigInt(operandData, 0);
      result = (value & mask) === 0n;
      break;
    }

    case Op.LENGTH_EQ:
      result = BigInt(valueLength) === toBigInt(operandData, 0);
      break;

    case Op.LENGTH_GT:
      result = BigInt(valueLength) > toBigInt(operandData, 0);
      break;

    case Op.LENGTH_LT:
      result = BigInt(valueLength) < toBigInt(operandData, 0);
      break;

    case Op.LENGTH_GTE:
      result = BigInt(valueLength) >= toBigInt(operandData, 0);
      break;

    case Op.LENGTH_LTE:
      result = BigInt(valueLength) <= toBigInt(operandData, 0);
      break;

    case Op.LENGTH_BETWEEN: {
      const length = BigInt(valueLength);
      const min = toBigInt(operandData, 0);
      const max = toBigInt(operandData, 32);
      result = length >= min && length <= max;
      break;
    }

    default:
      throw new CallciumError("INVALID_OPERATOR", `Unknown operator code 0x${base.toString(16).padStart(2, "0")}.`);
  }

  return negate ? !result : result;
}

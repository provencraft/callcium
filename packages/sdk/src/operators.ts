import { Op, TypeCode, operandsOf } from "./constants";
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
 * Return true when the type code represents a left-aligned type (fixed bytes or function),
 * whose value occupies the high bytes of the word with zero padding below.
 */
export function isLeftAligned(typeCode: number): boolean {
  return (
    (typeCode >= TypeCode.FIXED_BYTES_MIN && typeCode <= TypeCode.FIXED_BYTES_MAX) || typeCode === TypeCode.FUNCTION
  );
}

/**
 * Canonicalize a raw 256-bit calldata word to its ABI value for the declared type.
 * A scalar loaded from untrusted calldata may carry bits outside the declared width; masking
 * unsigned/address/bool/function/bytesN to width and sign-extending signed integers makes the
 * comparison use the canonical ABI value rather than the raw bytes.
 * @param value - The raw 256-bit word loaded from calldata.
 * @param typeCode - The declared type code of the value.
 * @returns The canonicalized 256-bit value.
 */
export function canonicalize(value: bigint, typeCode: number): bigint {
  // Unsigned integers: mask to the low N bits.
  if (typeCode >= TypeCode.UINT_MIN && typeCode <= TypeCode.UINT_MAX) {
    const bits = BigInt(typeCode * 8);
    return bits === 256n ? value : value & ((1n << bits) - 1n);
  }

  // Signed integers: sign-extend from the type's most-significant byte.
  if (typeCode >= TypeCode.INT_MIN && typeCode <= TypeCode.INT_MAX) {
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

/** Map a LENGTH_* opcode base to its core value-comparison twin. */
function lengthToValueOp(base: number): number {
  if (base === Op.LENGTH_EQ) return Op.EQ;
  if (base === Op.LENGTH_GT) return Op.GT;
  if (base === Op.LENGTH_LT) return Op.LT;
  if (base === Op.LENGTH_GTE) return Op.GTE;
  if (base === Op.LENGTH_LTE) return Op.LTE;
  return Op.BETWEEN;
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
  let low = 0;
  let high = count - 1;
  while (low <= high) {
    const mid = (low + high) >>> 1;
    const elem = toBigInt(data, mid * 32);
    if (value === elem) return true;
    if (value < elem) high = mid - 1;
    else low = mid + 1;
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
  let base = opCode & ~Op.NOT;

  // Length operators reuse the value-comparison core: the runtime count becomes the compared
  // value and the opcode maps onto its EQ/GT/LT/GTE/LTE/BETWEEN twin. Counts are non-negative,
  // so the comparison is always unsigned — force an unsigned type code regardless of the target.
  if (isLengthOp(base)) {
    value = BigInt(valueLength);
    typeCode = TypeCode.UINT_MAX;
    base = lengthToValueOp(base);
  }

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

    default:
      throw new CallciumError("UNKNOWN_OPERATOR", `Unknown operator code 0x${base.toString(16).padStart(2, "0")}`);
  }

  const negate = (opCode & Op.NOT) !== 0;
  return negate ? !result : result;
}

/**
 * Check whether an operator's data payload has the correct length.
 * @param opBase - Base operator code with the NOT flag stripped.
 * @param dataLength - Byte length of the operator's data payload.
 * @returns True if the data length is valid for the given operator.
 */
export function isValidOperatorData(opBase: number, dataLength: number): boolean {
  const operands = operandsOf(opBase);
  if (operands === "single") return dataLength === 32;
  if (operands === "range") return dataLength === 64;
  if (operands === "variadic") return dataLength > 0 && dataLength % 32 === 0;
  return false;
}

///////////////////////////////////////////////////////////////////////////
// Type code classification
///////////////////////////////////////////////////////////////////////////

/** Structural category for a descriptor type code. */
export type TypeClass = "elementary" | "tuple" | "staticArray" | "dynamicArray";

/** Structural classification without label. */
export type TypeClassInfo = { typeClass: TypeClass; isDynamic: boolean };

/** Display metadata for a descriptor type code. */
export type TypeCodeInfo = TypeClassInfo & { label: string };

/** Throw an UNKNOWN_TYPE_CODE error. */
function unknownTypeCode(code: number): never {
  throw new CallciumError("UNKNOWN_TYPE_CODE", `Unknown type code 0x${code.toString(16).padStart(2, "0")}`);
}

// Pre-allocated constant objects for fixed type codes (avoids per-call allocation).
const ELEMENTARY = { typeClass: "elementary", isDynamic: false } as const;
const ELEMENTARY_DYNAMIC = { typeClass: "elementary", isDynamic: true } as const;
const STATIC_ARR = { typeClass: "staticArray", isDynamic: false } as const;
const DYNAMIC_ARR = { typeClass: "dynamicArray", isDynamic: true } as const;
const TUPLE = { typeClass: "tuple", isDynamic: false } as const;

/**
 * Classify a type code into its structural category and dynamism.
 * Lightweight variant of `lookupTypeCode` that skips label computation.
 * @param code - A single-byte descriptor type code.
 * @returns Type class and whether the type is ABI-dynamic.
 * @throws {CallciumError} If the code is not a recognised type code.
 */
export function classifyTypeCode(code: number): TypeClassInfo {
  if (code >= TypeCode.UINT_MIN && code <= TypeCode.UINT_MAX) return ELEMENTARY;
  if (code >= TypeCode.INT_MIN && code <= TypeCode.INT_MAX) return ELEMENTARY;
  if (code === TypeCode.ADDRESS || code === TypeCode.BOOL || code === TypeCode.FUNCTION) return ELEMENTARY;
  if (code >= 0x44 && code <= 0x4f) unknownTypeCode(code);
  if (code >= TypeCode.FIXED_BYTES_MIN && code <= TypeCode.FIXED_BYTES_MAX) return ELEMENTARY;
  if (code === TypeCode.BYTES || code === TypeCode.STRING) return ELEMENTARY_DYNAMIC;
  if (code >= 0x72 && code <= 0x7f) unknownTypeCode(code);
  if (code === TypeCode.STATIC_ARRAY) return STATIC_ARR;
  if (code === TypeCode.DYNAMIC_ARRAY) return DYNAMIC_ARR;
  if (code >= 0x82 && code <= 0x8f) unknownTypeCode(code);
  if (code === TypeCode.TUPLE) return TUPLE;
  unknownTypeCode(code);
}

/**
 * Determine whether a type code names a value an operator can read: a scalar word or a declared
 * length. Tuples, static arrays, and undefined codes address nothing.
 * @param code - A single-byte descriptor type code.
 * @returns True when an operator can be applied to a target of this type.
 */
export function isAddressableTarget(code: number): boolean {
  let info: TypeClassInfo;
  try {
    // An undefined code is reported by a throw, and addresses nothing either way.
    info = classifyTypeCode(code);
  } catch {
    return false;
  }
  return info.typeClass === "elementary" || info.typeClass === "dynamicArray";
}

/** Compute the ABI type label for a type code. */
function typeCodeLabel(code: number): string {
  if (code >= TypeCode.UINT_MIN && code <= TypeCode.UINT_MAX) return `uint${(code - TypeCode.UINT_MIN + 1) * 8}`;
  if (code >= TypeCode.INT_MIN && code <= TypeCode.INT_MAX) return `int${(code - TypeCode.INT_MIN + 1) * 8}`;
  if (code === TypeCode.ADDRESS) return "address";
  if (code === TypeCode.BOOL) return "bool";
  if (code === TypeCode.FUNCTION) return "function";
  if (code >= TypeCode.FIXED_BYTES_MIN && code <= TypeCode.FIXED_BYTES_MAX)
    return `bytes${code - TypeCode.FIXED_BYTES_MIN + 1}`;
  if (code === TypeCode.BYTES) return "bytes";
  if (code === TypeCode.STRING) return "string";
  if (code === TypeCode.STATIC_ARRAY) return "T[k]";
  if (code === TypeCode.DYNAMIC_ARRAY) return "T[]";
  if (code === TypeCode.TUPLE) return "tuple";
  return `0x${code.toString(16).padStart(2, "0")}`;
}

/**
 * Map a raw type code byte to its ABI type label, structural category, and dynamism.
 * @param code - A single-byte descriptor type code.
 * @returns Label, type class, and whether the type is ABI-dynamic.
 * @throws {CallciumError} If the code is not a recognised type code.
 */
export function lookupTypeCode(code: number): TypeCodeInfo {
  return { label: typeCodeLabel(code), ...classifyTypeCode(code) };
}

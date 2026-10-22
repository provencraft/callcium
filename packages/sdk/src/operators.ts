import { bigintToHex, readU16 } from "./bytes";
import {
  comparisonOf,
  ContextProperty,
  DescriptorFormat as DF,
  formatCode,
  isComparisonCode,
  isSourceCode,
  Op,
  PolicyFormat as PF,
  Source,
  sourceOf,
  TypeCode,
} from "./constants";
import { CallciumError } from "./errors";

import type { DecodedOperator, Hex } from "./types";

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

/** Type code of the type a length compares as, `uint32`. */
export const LENGTH_TYPE = 0x04;

/** Return true when the operator code (with or without NOT flag) is a LENGTH_* variant. */
export function isLengthOp(opCode: number): boolean {
  const base = comparisonOf(opCode);
  return base >= Op.LENGTH_EQ && base <= Op.LENGTH_BETWEEN;
}

/** Return true when the operator admits a context property operand: EQ, GT, LT, GTE or LTE. */
export function acceptsContextSource(opBase: number): boolean {
  return opBase >= Op.EQ && opBase <= Op.LTE;
}

/** Return true when the type code has its length encoded in calldata (bytes, string, or dynamic array). */
export function hasCalldataLength(typeCode: number): boolean {
  return typeCode === TypeCode.BYTES || typeCode === TypeCode.STRING || typeCode === TypeCode.DYNAMIC_ARRAY;
}

/**
 * Return the byte width of a value of a static elementary type.
 * @param typeCode - A single-byte descriptor type code.
 * @returns The width in bytes, or undefined when the code names no static elementary type.
 */
export function operandWidth(typeCode: number): number | undefined {
  if (typeCode >= TypeCode.UINT_MIN && typeCode <= TypeCode.UINT_MAX) return typeCode - TypeCode.UINT_MIN + 1;
  if (typeCode >= TypeCode.INT_MIN && typeCode <= TypeCode.INT_MAX) return typeCode - TypeCode.INT_MIN + 1;
  if (typeCode === TypeCode.ADDRESS) return 20;
  if (typeCode === TypeCode.BOOL) return 1;
  if (typeCode === TypeCode.FUNCTION) return 24;
  if (typeCode >= TypeCode.FIXED_BYTES_MIN && typeCode <= TypeCode.FIXED_BYTES_MAX) {
    return typeCode - TypeCode.FIXED_BYTES_MIN + 1;
  }
  return undefined;
}

/** Return the type code a context property carries: `address` for msg.sender and tx.origin, `uint256` otherwise. */
export function contextPropertyType(contextPropertyId: number): number {
  const isAddress = contextPropertyId === ContextProperty.MSG_SENDER || contextPropertyId === ContextProperty.TX_ORIGIN;
  return isAddress ? TypeCode.ADDRESS : TypeCode.UINT_MAX;
}

/**
 * Return the type a comparison's constants take against a target type. A length comparison compares a type with a
 * calldata length as `LENGTH_TYPE`, any other comparison a static elementary type as itself.
 * @param comparison - Comparison bits of the operator code.
 * @param typeCode - The target's type code.
 * @returns The operand type code, or undefined where the comparison does not apply to the target.
 */
export function operandTypeOf(comparison: number, typeCode: number): number | undefined {
  if (isLengthOp(comparison)) return hasCalldataLength(typeCode) ? LENGTH_TYPE : undefined;
  return operandWidth(typeCode) === undefined ? undefined : typeCode;
}

/**
 * Check whether an operator's data payload has the correct length.
 * @param opBase - Comparison bits of the operator code, a defined comparison.
 * @param dataLength - Byte length of the operator's data payload.
 * @param width - Byte width of one operand, at least one.
 * @returns True if the data length is valid for the given operator.
 */
export function isValidPayloadSize(opBase: number, dataLength: number, width: number): boolean {
  // Range operators carry a lower and an upper operand; IN carries one or more; every other operator one.
  if (opBase === Op.BETWEEN || opBase === Op.LENGTH_BETWEEN) return dataLength === 2 * width;
  if (opBase === Op.IN) return dataLength > 0 && dataLength % width === 0;
  return dataLength === width;
}

/** Return true when the type code represents a signed integer (int8 through int256). */
export function isSigned(typeCode: number): boolean {
  return typeCode >= TypeCode.INT_MIN && typeCode <= TypeCode.INT_MAX;
}

/**
 * Return true when the type code represents a left-aligned type (fixed bytes or function), whose value occupies the
 * high bytes of the word with zero padding below.
 */
export function isLeftAligned(typeCode: number): boolean {
  return (
    (typeCode >= TypeCode.FIXED_BYTES_MIN && typeCode <= TypeCode.FIXED_BYTES_MAX) || typeCode === TypeCode.FUNCTION
  );
}

/**
 * Return the canonical encoding of a 256-bit word for the declared type. Masks unsigned/address/bool to width, clears
 * bytesN/function padding, and sign-extends signed integers. A word is canonical when this leaves it unchanged.
 * @param value - The 256-bit word.
 * @param typeCode - The declared type code of the value.
 * @returns The canonicalized 256-bit value.
 */
export function canonicalize(value: bigint, typeCode: number): bigint {
  // Unsigned integers: mask to the low N bits.
  if (typeCode >= TypeCode.UINT_MIN && typeCode <= TypeCode.UINT_MAX) {
    const bits = BigInt((typeCode - TypeCode.UINT_MIN + 1) * 8);
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
    const width = typeCode - TypeCode.FIXED_BYTES_MIN + 1;
    if (width === 32) return value;
    const padBits = BigInt((32 - width) * 8);
    return (value >> padBits) << padBits;
  }

  return value;
}

/** Read the `width`-byte big-endian member at `offset`. */
export function readMember(data: Uint8Array, offset: number, width: number): bigint {
  let value = 0n;
  for (let index = 0; index < width; index++) value = (value << 8n) | BigInt(data[offset + index]!);
  return value;
}

/**
 * Return the word an operand of a static elementary type loads to: placed at its type's alignment, and sign-extended
 * for a signed integer.
 * @param data - The bytes containing the operand.
 * @param offset - Byte offset of the operand.
 * @param typeCode - Type code of the operand.
 * @returns The loaded 256-bit word.
 * @throws {CallciumError} If the type code names no static elementary type.
 */
export function loadOperand(data: Uint8Array, offset: number, typeCode: number): bigint {
  const width = operandWidth(typeCode);
  if (width === undefined) throw new CallciumError("MALFORMED_HINT", "Target type code addresses no value");
  const member = readMember(data, offset, width);
  if (isLeftAligned(typeCode)) return member << BigInt(256 - 8 * width);
  if (isSigned(typeCode)) return BigInt.asUintN(256, BigInt.asIntN(8 * width, member));
  return member;
}

/**
 * Read the operator at `opOffset` of a policy, applied to a target of `typeCode`.
 * @param data - A policy blob storage validation accepts.
 * @param opOffset - Byte offset of the operator code.
 * @param typeCode - The target's type code.
 * @returns The operator with its comparison, its polarity and its operands, each constant loaded to its 32-byte word.
 * @throws {CallciumError} If the operator code names no defined comparison or source.
 */
export function readOperator(data: Uint8Array, opOffset: number, typeCode: number): DecodedOperator {
  const opCode = data[opOffset]!;
  const comparison = comparisonOf(opCode);
  const source = sourceOf(opCode);
  if (!isComparisonCode(comparison) || !isSourceCode(source)) {
    throw new CallciumError(
      "UNKNOWN_OPERATOR",
      `Unknown operator code ${formatCode(opCode & ~Op.NOT, PF.RULE_OPCODE_SIZE)}`,
      opOffset,
    );
  }
  const negated = (opCode & Op.NOT) !== 0;
  const dataLength = readU16(data, opOffset + PF.RULE_OPCODE_SIZE);
  const dataOffset = opOffset + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;

  switch (source) {
    case Source.CONTEXT: {
      const contextPropertyId = readU16(data, dataOffset);
      const operandType = contextPropertyType(contextPropertyId);
      return { opCode, comparison, negated, operandType, source, contextPropertyId };
    }
    case Source.CONSTANT: {
      const operandType = operandTypeOf(comparison, typeCode)!;
      const width = operandWidth(operandType)!;
      const values: Hex[] = [];
      for (let offset = 0; offset < dataLength; offset += width) {
        values.push(bigintToHex(loadOperand(data, dataOffset + offset, operandType)));
      }
      return { opCode, comparison, negated, operandType, source, values };
    }
    default:
      return source satisfies never;
  }
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

/** Each defined type code's ABI type label, structural category, and dynamism. */
function typeCodeEntries(): [number, TypeCodeInfo][] {
  const entries: [number, TypeCodeInfo][] = [];
  const add = (code: number, label: string, typeClass: TypeClass, isDynamic: boolean) =>
    entries.push([code, { label, typeClass, isDynamic }]);
  for (let code = TypeCode.UINT_MIN; code <= TypeCode.UINT_MAX; code++) {
    add(code, `uint${(code - TypeCode.UINT_MIN + 1) * 8}`, "elementary", false);
  }
  for (let code = TypeCode.INT_MIN; code <= TypeCode.INT_MAX; code++) {
    add(code, `int${(code - TypeCode.INT_MIN + 1) * 8}`, "elementary", false);
  }
  add(TypeCode.ADDRESS, "address", "elementary", false);
  add(TypeCode.BOOL, "bool", "elementary", false);
  add(TypeCode.FUNCTION, "function", "elementary", false);
  for (let code = TypeCode.FIXED_BYTES_MIN; code <= TypeCode.FIXED_BYTES_MAX; code++) {
    add(code, `bytes${code - TypeCode.FIXED_BYTES_MIN + 1}`, "elementary", false);
  }
  add(TypeCode.BYTES, "bytes", "elementary", true);
  add(TypeCode.STRING, "string", "elementary", true);
  add(TypeCode.STATIC_ARRAY, "T[k]", "staticArray", false);
  add(TypeCode.DYNAMIC_ARRAY, "T[]", "dynamicArray", true);
  add(TypeCode.TUPLE, "tuple", "tuple", false);
  return entries;
}

const typeCodeByCode: ReadonlyMap<number, TypeCodeInfo> = new Map<number, TypeCodeInfo>(typeCodeEntries());

/**
 * Map a raw type code byte to its ABI type label, structural category, and dynamism.
 * @param code - A single-byte descriptor type code.
 * @returns Label, type class, and whether the code alone implies ABI dynamism (false for tuples and static arrays).
 * @throws {CallciumError} If the code is not a recognised type code.
 */
export function lookupTypeCode(code: number): TypeCodeInfo {
  const info = typeCodeByCode.get(code);
  if (!info) throw new CallciumError("UNKNOWN_TYPE_CODE", `Unknown type code ${formatCode(code, DF.TYPECODE_SIZE)}`);
  return info;
}

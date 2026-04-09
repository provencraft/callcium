import { DescriptorFormat as DF, TypeCode } from "./constants";
import { CallciumError } from "./errors";
import { readU24, writeBE16, writeBE24 } from "./hex";

///////////////////////////////////////////////////////////////////////////
// Internal helpers
///////////////////////////////////////////////////////////////////////////

/**
 * Extract the staticWords count from a descriptor node.
 *
 * For elementary types (typeCode < STATIC_ARRAY), returns 1 unless the type is
 * BYTES or STRING, which are ABI-dynamic and return 0. For composite types,
 * reads the 24-bit meta field at offset 1 and shifts right by
 * META_STATIC_WORDS_SHIFT.
 */
function _extractStaticWords(desc: Uint8Array): number {
  const typeCode = desc[0]!;
  if (typeCode < TypeCode.STATIC_ARRAY) {
    return typeCode === TypeCode.BYTES || typeCode === TypeCode.STRING ? 0 : 1;
  }
  return readU24(desc, 1) >> DF.META_STATIC_WORDS_SHIFT;
}

///////////////////////////////////////////////////////////////////////////
// Elementary types
///////////////////////////////////////////////////////////////////////////

/** Build a descriptor node for `address`. */
export function address(): Uint8Array {
  return new Uint8Array([TypeCode.ADDRESS]);
}

/** Build a descriptor node for `bool`. */
export function bool(): Uint8Array {
  return new Uint8Array([TypeCode.BOOL]);
}

/** Build a descriptor node for `function`. */
export function function_(): Uint8Array {
  return new Uint8Array([TypeCode.FUNCTION]);
}

/** Build a descriptor node for `uint256`. */
export function uint256(): Uint8Array {
  return new Uint8Array([TypeCode.UINT_MAX]);
}

/** Build a descriptor node for `int256`. */
export function int256(): Uint8Array {
  return new Uint8Array([TypeCode.INT_MAX]);
}

/**
 * Build a descriptor node for `uintN`.
 * @param bits - Bit width, 8–256 in steps of 8.
 * @throws {CallciumError} If bits is out of range or not a multiple of 8.
 */
export function uintN(bits: number): Uint8Array {
  if (bits < 8 || bits > 256 || bits % 8 !== 0) {
    throw new CallciumError("INVALID_TYPE_STRING", `Invalid uintN bits: ${bits}. Must be 8–256 in steps of 8.`);
  }
  return new Uint8Array([TypeCode.UINT_MIN + (bits / 8 - 1)]);
}

/**
 * Build a descriptor node for `intN`.
 * @param bits - Bit width, 8–256 in steps of 8.
 * @throws {CallciumError} If bits is out of range or not a multiple of 8.
 */
export function intN(bits: number): Uint8Array {
  if (bits < 8 || bits > 256 || bits % 8 !== 0) {
    throw new CallciumError("INVALID_TYPE_STRING", `Invalid intN bits: ${bits}. Must be 8–256 in steps of 8.`);
  }
  return new Uint8Array([TypeCode.INT_MIN + (bits / 8 - 1)]);
}

/** Build a descriptor node for `bytes` (dynamic). */
export function bytes(): Uint8Array {
  return new Uint8Array([TypeCode.BYTES]);
}

/** Build a descriptor node for `string`. */
export function string_(): Uint8Array {
  return new Uint8Array([TypeCode.STRING]);
}

/**
 * Build a descriptor node for `bytesN`.
 * @param n - Byte width, 1–32.
 * @throws {CallciumError} If n is out of range.
 */
export function bytesN(n: number): Uint8Array {
  if (n < 1 || n > 32) {
    throw new CallciumError("INVALID_TYPE_STRING", `Invalid bytesN size: ${n}. Must be 1–32.`);
  }
  return new Uint8Array([TypeCode.FIXED_BYTES_MIN + (n - 1)]);
}

/** Build a descriptor node for `bytes32`. */
export function bytes32(): Uint8Array {
  return bytesN(32);
}

/**
 * Build a descriptor node for an enum type (alias for `uintN`).
 * @param bits - Bit width, default 8.
 */
export function enum_(bits: number = 8): Uint8Array {
  return uintN(bits);
}

///////////////////////////////////////////////////////////////////////////
// Composite types
///////////////////////////////////////////////////////////////////////////

/**
 * Build a descriptor node for a dynamic array `T[]` or static array `T[length]`.
 *
 * Dynamic form: `[0x81][meta:3][elemDesc]`
 * Static form:  `[0x80][meta:3][elemDesc][length:be16]`
 *
 * @param elemDesc - Descriptor bytes for the element type.
 * @param length - Fixed array length. When omitted, produces a dynamic array.
 * @throws {CallciumError} If length is 0 or exceeds MAX_STATIC_ARRAY_LENGTH.
 */
export function array(elemDesc: Uint8Array, length?: number): Uint8Array {
  if (length === undefined) {
    // Dynamic array T[].
    const nodeLength = DF.ARRAY_HEADER_SIZE + elemDesc.length;
    if (nodeLength > DF.MAX_NODE_LENGTH) {
      throw new CallciumError(
        "DESCRIPTOR_TOO_LARGE",
        `Dynamic array node length ${nodeLength} exceeds maximum ${DF.MAX_NODE_LENGTH}.`,
      );
    }
    const meta24 = (0 << DF.META_STATIC_WORDS_SHIFT) | nodeLength;
    const buf = new Uint8Array(1 + DF.COMPOSITE_META_SIZE + elemDesc.length);
    buf[0] = TypeCode.DYNAMIC_ARRAY;
    writeBE24(buf, 1, meta24);
    buf.set(elemDesc, 4);
    return buf;
  }

  // Static array T[length].
  if (length <= 0 || length > DF.MAX_STATIC_ARRAY_LENGTH) {
    throw new CallciumError(
      "INVALID_ARRAY_LENGTH",
      `Static array length ${length} out of range. Must be 1–${DF.MAX_STATIC_ARRAY_LENGTH}.`,
    );
  }
  const nodeLength = DF.ARRAY_HEADER_SIZE + elemDesc.length + DF.ARRAY_LENGTH_SIZE;
  if (nodeLength > DF.MAX_NODE_LENGTH) {
    throw new CallciumError(
      "DESCRIPTOR_TOO_LARGE",
      `Static array node length ${nodeLength} exceeds maximum ${DF.MAX_NODE_LENGTH}.`,
    );
  }
  const elemStaticWords = _extractStaticWords(elemDesc);
  const staticWords = elemStaticWords === 0 ? 0 : length * elemStaticWords;
  if (staticWords > DF.META_NODE_LENGTH_MASK) {
    throw new CallciumError(
      "DESCRIPTOR_TOO_LARGE",
      `Static array static words ${staticWords} exceeds 12-bit maximum ${DF.META_NODE_LENGTH_MASK}.`,
    );
  }
  const meta24 = (staticWords << DF.META_STATIC_WORDS_SHIFT) | nodeLength;
  const buf = new Uint8Array(1 + DF.COMPOSITE_META_SIZE + elemDesc.length + DF.ARRAY_LENGTH_SIZE);
  buf[0] = TypeCode.STATIC_ARRAY;
  writeBE24(buf, 1, meta24);
  buf.set(elemDesc, 4);
  writeBE16(buf, 4 + elemDesc.length, length);
  return buf;
}

/**
 * Build a descriptor node for a tuple.
 *
 * Format: `[0x90][meta:3][fieldCount:be16][field0][field1]...`
 *
 * @param fieldDescs - Descriptor bytes for each field, in order.
 * @throws {CallciumError} If fieldDescs is empty, exceeds MAX_TUPLE_FIELDS, or nodeLength overflows MAX_NODE_LENGTH.
 */
export function tuple(fieldDescs: Uint8Array[]): Uint8Array {
  if (fieldDescs.length === 0 || fieldDescs.length > DF.MAX_TUPLE_FIELDS) {
    throw new CallciumError(
      "INVALID_TUPLE_FIELD_COUNT",
      `Tuple field count ${fieldDescs.length} out of range. Must be 1–${DF.MAX_TUPLE_FIELDS}.`,
    );
  }
  const totalFieldBytes = fieldDescs.reduce((sum, f) => sum + f.length, 0);
  const nodeLength = DF.TUPLE_HEADER_SIZE + totalFieldBytes;
  if (nodeLength > DF.MAX_NODE_LENGTH) {
    throw new CallciumError(
      "INVALID_TUPLE_FIELD_COUNT",
      `Tuple node length ${nodeLength} exceeds maximum ${DF.MAX_NODE_LENGTH}.`,
    );
  }

  let anyDynamic = false;
  let staticWordsSum = 0;
  for (const field of fieldDescs) {
    const staticWords = _extractStaticWords(field);
    if (staticWords === 0) {
      anyDynamic = true;
    }
    staticWordsSum += staticWords;
  }
  const staticWords = anyDynamic ? 0 : staticWordsSum;
  if (staticWords > DF.META_NODE_LENGTH_MASK) {
    throw new CallciumError(
      "DESCRIPTOR_TOO_LARGE",
      `Tuple static words ${staticWords} exceeds 12-bit maximum ${DF.META_NODE_LENGTH_MASK}.`,
    );
  }
  const meta24 = (staticWords << DF.META_STATIC_WORDS_SHIFT) | nodeLength;

  const buf = new Uint8Array(1 + DF.COMPOSITE_META_SIZE + DF.TUPLE_FIELDCOUNT_SIZE + totalFieldBytes);
  buf[0] = TypeCode.TUPLE;
  writeBE24(buf, 1, meta24);
  writeBE16(buf, 4, fieldDescs.length);
  let offset = 6;
  for (const field of fieldDescs) {
    buf.set(field, offset);
    offset += field.length;
  }
  return buf;
}

/**
 * Build a descriptor node for a struct (alias for `tuple`).
 * @param fieldDescs - Descriptor bytes for each field, in order.
 */
export function struct(fieldDescs: Uint8Array[]): Uint8Array {
  return tuple(fieldDescs);
}

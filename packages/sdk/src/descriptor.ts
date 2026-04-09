import { DescriptorFormat as DF, TypeCode } from "./constants";
import { CallciumError } from "./errors";
import { readU16, readU24 } from "./hex";

///////////////////////////////////////////////////////////////////////////
// Public types
///////////////////////////////////////////////////////////////////////////

/** Structural type information extracted from a descriptor node. */
export type TypeInfo = {
  typeCode: number;
  isDynamic: boolean;
  staticSize: number;
};

///////////////////////////////////////////////////////////////////////////
// Internal helpers
///////////////////////////////////////////////////////////////////////////

/**
 * Return the byte length of the node at `offset`.
 * Elementary nodes occupy exactly one byte; composite nodes encode their
 * length in the lower 12 bits of the 24-bit meta field.
 */
function _nodeLength(desc: Uint8Array, offset: number): number {
  const typeCode = desc[offset]!;
  if (typeCode < TypeCode.STATIC_ARRAY) return DF.TYPECODE_SIZE;
  return readU24(desc, offset + 1) & DF.META_NODE_LENGTH_MASK;
}

/**
 * Return the byte offset of the `fieldIndex`-th field inside a tuple node.
 * Starts at the first field and skips `fieldIndex` nodes using `_nodeLength`.
 */
function _tupleFieldOffset(desc: Uint8Array, tupleOffset: number, fieldIndex: number): number {
  let cursor = tupleOffset + DF.TUPLE_HEADER_SIZE;
  for (let i = 0; i < fieldIndex; i++) {
    cursor += _nodeLength(desc, cursor);
  }
  return cursor;
}

///////////////////////////////////////////////////////////////////////////
// Public interface
///////////////////////////////////////////////////////////////////////////

/** Inspect and navigate raw descriptor bytes. */
export const Descriptor = {
  /** Return paramCount from header byte 1. */
  paramCount(desc: Uint8Array): number {
    return desc[1]!;
  },

  /** Return byte offset of the N-th top-level param (0-indexed). */
  paramOffset(desc: Uint8Array, index: number): number {
    const count = desc[1]!;
    if (index >= count) {
      throw new CallciumError("INVALID_PATH", `Param index ${index} out of range (paramCount=${count}).`);
    }
    let cursor = DF.HEADER_SIZE;
    for (let i = 0; i < index; i++) {
      cursor += _nodeLength(desc, cursor);
    }
    return cursor;
  },

  /**
   * Inspect the type node at a given byte offset.
   * @param desc - Raw descriptor bytes.
   * @param offset - Byte position of the node.
   * @returns typeCode, isDynamic, and staticSize in bytes.
   */
  inspect(desc: Uint8Array, offset: number): TypeInfo {
    const typeCode = desc[offset]!;
    let staticWords: number;
    if (typeCode < TypeCode.STATIC_ARRAY) {
      staticWords = typeCode === TypeCode.BYTES || typeCode === TypeCode.STRING ? 0 : 1;
    } else {
      staticWords = readU24(desc, offset + 1) >> DF.META_STATIC_WORDS_SHIFT;
    }
    // For composite types, dynamism is reflected by staticWords=0 in the encoded meta,
    // which captures cases like a tuple whose fields include a dynamic type.
    const isDynamic = staticWords === 0;
    return { typeCode, isDynamic, staticSize: staticWords * 32 };
  },

  /**
   * Resolve the type at a calldata path (array of step indices).
   *
   * The first step selects a top-level param. Each subsequent step descends
   * into the current node: for tuples it selects a field, for arrays it
   * advances to the element descriptor.
   *
   * @param desc - Raw descriptor bytes.
   * @param steps - Path steps, length >= 1.
   * @returns TypeInfo for the node at the resolved path.
   * @throws {CallciumError} On empty steps, out-of-bounds param, or descent into elementary type.
   */
  typeAt(desc: Uint8Array, steps: number[]): TypeInfo {
    if (steps.length === 0) {
      throw new CallciumError("INVALID_PATH", "Path must have at least one step.");
    }

    const paramIndex = steps[0]!;
    const paramCount = desc[1]!;
    if (paramIndex >= paramCount) {
      throw new CallciumError("INVALID_PATH", `Param index ${paramIndex} out of range (paramCount=${paramCount}).`);
    }

    let cursor = Descriptor.paramOffset(desc, paramIndex);

    for (let stepIndex = 1; stepIndex < steps.length; stepIndex++) {
      const typeCode = desc[cursor]!;
      const step = steps[stepIndex]!;

      if (typeCode === TypeCode.TUPLE) {
        const fieldCount = Descriptor.tupleFieldCount(desc, cursor);
        if (step >= fieldCount) {
          throw new CallciumError(
            "INVALID_PATH",
            `Tuple field index ${step} out of range (tuple has ${fieldCount} fields).`,
          );
        }
        cursor = _tupleFieldOffset(desc, cursor, step);
      } else if (typeCode === TypeCode.STATIC_ARRAY || typeCode === TypeCode.DYNAMIC_ARRAY) {
        // Element descriptor starts immediately after the 4-byte array header.
        cursor = cursor + DF.ARRAY_HEADER_SIZE;
      } else {
        throw new CallciumError("INVALID_PATH", `Cannot descend into elementary type at offset ${cursor}.`);
      }
    }

    return Descriptor.inspect(desc, cursor);
  },

  /**
   * Return the byte offset of the `fieldIndex`-th field inside a tuple node.
   * @param desc - Raw descriptor bytes.
   * @param tupleOffset - Byte position of the tuple node.
   * @param fieldIndex - Field index (0-based).
   */
  tupleFieldOffset(desc: Uint8Array, tupleOffset: number, fieldIndex: number): number {
    return _tupleFieldOffset(desc, tupleOffset, fieldIndex);
  },

  /**
   * Return tuple field count at a tuple node offset.
   * @param desc - Raw descriptor bytes.
   * @param offset - Byte position of the tuple node.
   */
  tupleFieldCount(desc: Uint8Array, offset: number): number {
    return readU16(desc, offset + 4);
  },

  /**
   * Return static array length at a static array node offset.
   * @param desc - Raw descriptor bytes.
   * @param offset - Byte position of the static array node.
   */
  staticArrayLength(desc: Uint8Array, offset: number): number {
    // The element descriptor starts at offset+4; its length determines where the length field is.
    const elemLen = _nodeLength(desc, offset + DF.ARRAY_HEADER_SIZE);
    const lengthOffset = offset + DF.ARRAY_HEADER_SIZE + elemLen;
    return readU16(desc, lengthOffset);
  },
};

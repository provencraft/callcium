import { readU16, readU24, writeBE32 } from "./bytes";
import { DescriptorFormat as DF, PolicyFormat as PF, TypeCode, isQuantifier } from "./constants";
import { CallciumError } from "./errors";

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
function nodeLength(desc: Uint8Array, offset: number): number {
  const typeCode = desc[offset]!;
  if (typeCode < TypeCode.STATIC_ARRAY) return DF.TYPECODE_SIZE;
  return readU24(desc, offset + 1) & DF.META_NODE_LENGTH_MASK;
}

/**
 * Return the byte offset of the `fieldIndex`-th field inside a tuple node.
 * Starts at the first field and skips `fieldIndex` nodes using `nodeLength`.
 */
function tupleFieldOffset(desc: Uint8Array, tupleOffset: number, fieldIndex: number): number {
  let cursor = tupleOffset + DF.TUPLE_HEADER_SIZE;
  for (let i = 0; i < fieldIndex; i++) {
    cursor += nodeLength(desc, cursor);
  }
  return cursor;
}

///////////////////////////////////////////////////////////////////////////
// Public interface
///////////////////////////////////////////////////////////////////////////

/** Return paramCount from header byte 1. */
function paramCount(desc: Uint8Array): number {
  return desc[1]!;
}

/** Return byte offset of the N-th top-level param (0-indexed). */
function paramOffset(desc: Uint8Array, index: number): number {
  const count = desc[1]!;
  if (index >= count) {
    throw new CallciumError("INVALID_PATH", `Param index ${index} out of range (paramCount=${count}).`);
  }
  let cursor = DF.HEADER_SIZE;
  for (let i = 0; i < index; i++) {
    cursor += nodeLength(desc, cursor);
  }
  return cursor;
}

/**
 * Inspect the type node at a given byte offset.
 * @param desc - Raw descriptor bytes.
 * @param offset - Byte position of the node.
 * @returns typeCode, isDynamic, and staticSize in bytes.
 */
function inspect(desc: Uint8Array, offset: number): TypeInfo {
  const typeCode = desc[offset]!;
  let staticWords: number;
  if (typeCode < TypeCode.STATIC_ARRAY) {
    staticWords = typeCode === TypeCode.BYTES || typeCode === TypeCode.STRING ? 0 : 1;
  } else {
    staticWords = readU24(desc, offset + 1) >> DF.META_STATIC_WORDS_SHIFT;
  }
  const isDynamic = staticWords === 0;
  return { typeCode, isDynamic, staticSize: staticWords * 32 };
}

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
 * @throws {CallciumError} On empty steps, out-of-bounds param or array index, or descent into elementary type.
 */
function typeAt(desc: Uint8Array, steps: number[]): TypeInfo {
  return walkPath(desc, steps).typeInfo;
}

/**
 * Resolve the type at the path and the declared length of the static array a
 * quantifier step descends into (zero when the path holds no quantifier step
 * over a static array).
 * @param desc - Raw descriptor bytes.
 * @param steps - Path steps, length >= 1.
 * @returns TypeInfo at the resolved path and the quantified static array length.
 * @throws {CallciumError} On empty steps, out-of-bounds param or array index, or descent into elementary type.
 */
function walkPath(desc: Uint8Array, steps: number[]): { typeInfo: TypeInfo; quantifiedStaticLength: number } {
  if (steps.length === 0) {
    throw new CallciumError("INVALID_PATH", "Path must have at least one step.");
  }

  const paramIndex = steps[0]!;
  const count = desc[1]!;
  if (paramIndex >= count) {
    throw new CallciumError("INVALID_PATH", `Param index ${paramIndex} out of range (paramCount=${count}).`);
  }

  let cursor = paramOffset(desc, paramIndex);
  let quantifiedStaticLength = 0;

  for (let stepIndex = 1; stepIndex < steps.length; stepIndex++) {
    const typeCode = desc[cursor]!;
    const step = steps[stepIndex]!;

    if (typeCode === TypeCode.TUPLE) {
      const fields = tupleFieldCount(desc, cursor);
      if (step >= fields) {
        throw new CallciumError("INVALID_PATH", `Tuple field index ${step} out of range (tuple has ${fields} fields).`);
      }
      cursor = tupleFieldOffset(desc, cursor, step);
    } else if (typeCode === TypeCode.STATIC_ARRAY || typeCode === TypeCode.DYNAMIC_ARRAY) {
      // Quantifier sentinels descend into the element type; only concrete
      // indices are bounds-checked against the declared array length.
      if (typeCode === TypeCode.STATIC_ARRAY) {
        if (isQuantifier(step)) {
          quantifiedStaticLength = staticArrayLength(desc, cursor);
        } else {
          const length = staticArrayLength(desc, cursor);
          if (step >= length) {
            throw new CallciumError("INVALID_PATH", `Array index ${step} out of range (length=${length}).`);
          }
        }
      }
      cursor = arrayElementOffset(cursor);
    } else {
      throw new CallciumError("INVALID_PATH", `Cannot descend into elementary type at offset ${cursor}.`);
    }
  }

  return { typeInfo: inspect(desc, cursor), quantifiedStaticLength };
}

/**
 * Return tuple field count at a tuple node offset.
 * @param desc - Raw descriptor bytes.
 * @param offset - Byte position of the tuple node.
 */
function tupleFieldCount(desc: Uint8Array, offset: number): number {
  return readU16(desc, offset + 4);
}

/**
 * Return static array length at a static array node offset.
 * @param desc - Raw descriptor bytes.
 * @param offset - Byte position of the static array node.
 */
function staticArrayLength(desc: Uint8Array, offset: number): number {
  const elemOffset = arrayElementOffset(offset);
  const elemLen = nodeLength(desc, elemOffset);
  const lengthOffset = elemOffset + elemLen;
  return readU16(desc, lengthOffset);
}

/**
 * Return the byte offset of the array element descriptor.
 * @param offset - Byte position of the array node (static or dynamic).
 */
function arrayElementOffset(offset: number): number {
  return offset + DF.ARRAY_HEADER_SIZE;
}

/** Build the hint block for a path that does not compile to concrete offsets. */
function sentinelHint(): Uint8Array {
  const hint = new Uint8Array(PF.HINT_STATIC_SIZE);
  writeBE32(hint, 0, PF.HINT_SENTINEL_OFFSET);
  hint[PF.HINT_STATIC_SIZE - 1] = PF.HINT_TYPE_NONE;
  return hint;
}

/**
 * Compile a calldata rule path into its wire hint block.
 *
 * Returns the sentinel block for a path that is not compilable: one that navigates through a
 * dynamic node, quantifies over anything but a dynamic array of static elements, or does not
 * navigate the descriptor at all.
 *
 * @param desc - Raw descriptor bytes.
 * @param steps - Path steps, length >= 1.
 * @returns The hint block bytes.
 */
function compileHint(desc: Uint8Array, steps: number[]): Uint8Array {
  if (steps.length === 0) {
    throw new CallciumError("EMPTY_PATH", "Path must have at least one step.");
  }

  const argIndex = steps[0]!;
  if (argIndex >= paramCount(desc)) return sentinelHint();

  // Accumulate the argument's head offset by skipping the preceding parameters.
  let descOffset: number = DF.HEADER_SIZE;
  let head = 0;
  for (let i = 0; i < argIndex; i++) {
    const param = inspect(desc, descOffset);
    head += param.isDynamic ? 32 : param.staticSize;
    descOffset += nodeLength(desc, descOffset);
  }

  let arrayHead = 0;
  let elemStride = 0;
  let quantified = false;

  for (let stepIndex = 1; stepIndex < steps.length; stepIndex++) {
    const childIndex = steps[stepIndex]!;
    const node = inspect(desc, descOffset);

    if (isQuantifier(childIndex)) {
      // Only a dynamic array of static elements compiles: calldata supplies the element count,
      // the descriptor supplies a fixed stride.
      if (node.typeCode !== TypeCode.DYNAMIC_ARRAY) return sentinelHint();
      const quantifiedElemOffset = arrayElementOffset(descOffset);
      const element = inspect(desc, quantifiedElemOffset);
      if (element.isDynamic) return sentinelHint();

      arrayHead = head;
      elemStride = element.staticSize;
      quantified = true;
      // Offsets past the quantifier are relative to the element.
      head = 0;
      descOffset = quantifiedElemOffset;
      continue;
    }

    // A dynamic node places its subtree at a calldata-supplied offset, so nothing below it has a
    // fixed address.
    if (node.isDynamic) return sentinelHint();

    if (node.typeCode === TypeCode.TUPLE) {
      if (childIndex >= tupleFieldCount(desc, descOffset)) return sentinelHint();
      let fieldOffset = descOffset + DF.TUPLE_HEADER_SIZE;
      for (let i = 0; i < childIndex; i++) {
        head += inspect(desc, fieldOffset).staticSize;
        fieldOffset += nodeLength(desc, fieldOffset);
      }
      descOffset = fieldOffset;
    } else if (node.typeCode === TypeCode.STATIC_ARRAY) {
      if (childIndex >= staticArrayLength(desc, descOffset)) return sentinelHint();
      const elemOffset = arrayElementOffset(descOffset);
      head += childIndex * inspect(desc, elemOffset).staticSize;
      descOffset = elemOffset;
    } else {
      return sentinelHint();
    }
  }

  // An offset indistinguishable from the sentinel is not addressable through a hint.
  if (head >= PF.HINT_SENTINEL_OFFSET || arrayHead >= PF.HINT_SENTINEL_OFFSET) return sentinelHint();

  const targetCode = desc[descOffset]!;
  if (quantified) {
    const hint = new Uint8Array(PF.HINT_QUANTIFIED_SIZE);
    writeBE32(hint, 0, arrayHead);
    writeBE32(hint, PF.HINT_ELEM_STRIDE_OFFSET, elemStride);
    writeBE32(hint, PF.HINT_SUFFIX_OFFSET, head);
    hint[PF.HINT_QUANTIFIED_SIZE - 1] = targetCode;
    return hint;
  }

  const hint = new Uint8Array(PF.HINT_STATIC_SIZE);
  writeBE32(hint, 0, head);
  hint[PF.HINT_STATIC_SIZE - 1] = targetCode;
  return hint;
}

/** Inspect and navigate raw descriptor bytes. */
export const Descriptor = {
  paramCount,
  paramOffset,
  inspect,
  typeAt,
  tupleFieldOffset,
  tupleFieldCount,
  staticArrayLength,
  nodeLength,
  arrayElementOffset,
  walkPath,
  compileHint,
};

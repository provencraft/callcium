import { readU16, readU24 } from "./bytes";
import { DescriptorFormat as DF, TypeCode } from "./constants";
import { CallciumError } from "./errors";
import { lookupTypeCode } from "./operators";

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

/** A descriptor node's type code, static word count, and total byte length. */
type Node = { typeCode: number; staticWords: number; nodeLength: number };

/**
 * Read the node at `offset`. Elementary nodes occupy exactly one byte. Composite nodes encode their static word count
 * and length in the 24-bit meta field that follows the type code.
 * @throws {CallciumError} When the node starts past the descriptor, carries an undefined type code, or declares a
 * length below its own header or beyond the descriptor.
 */
export function readNode(desc: Uint8Array, offset: number): Node {
  if (offset >= desc.length) {
    throw new CallciumError("UNEXPECTED_END", "Unexpected end of descriptor", offset);
  }
  const typeCode = desc[offset]!;
  const info = lookupTypeCode(typeCode);
  if (info.typeClass === "elementary") {
    return { typeCode, staticWords: info.isDynamic ? 0 : 1, nodeLength: DF.TYPECODE_SIZE };
  }

  if (offset + DF.TYPECODE_SIZE + DF.COMPOSITE_META_SIZE > desc.length) {
    throw new CallciumError("UNEXPECTED_END", "Incomplete composite metadata", offset);
  }
  const meta = readU24(desc, offset + DF.TYPECODE_SIZE);
  const length = meta & DF.META_NODE_LENGTH_MASK;
  const minHeader = info.typeClass === "tuple" ? DF.TUPLE_HEADER_SIZE : DF.ARRAY_HEADER_SIZE;
  if (length < minHeader) {
    throw new CallciumError(
      "NODE_LENGTH_TOO_SMALL",
      `Composite node length ${length} is smaller than minimum header ${minHeader}`,
      offset,
    );
  }
  if (offset + length > desc.length) {
    throw new CallciumError("NODE_OVERFLOW", "Composite node extends beyond descriptor", offset);
  }
  return { typeCode, staticWords: meta >> DF.META_STATIC_WORDS_SHIFT, nodeLength: length };
}

/**
 * Return the byte length of the node at `offset`.
 * @throws {CallciumError} When the descriptor contains no readable node at `offset`.
 */
function nodeLength(desc: Uint8Array, offset: number): number {
  return readNode(desc, offset).nodeLength;
}

///////////////////////////////////////////////////////////////////////////
// Public interface
///////////////////////////////////////////////////////////////////////////

/**
 * Return the declared top-level parameter count.
 * @throws {CallciumError} When the descriptor is too short for a header.
 */
function paramCount(desc: Uint8Array): number {
  if (desc.length < DF.HEADER_SIZE) {
    throw new CallciumError("MALFORMED_HEADER", "Descriptor too short for header");
  }
  return desc[DF.HEADER_PARAMCOUNT_OFFSET]!;
}

/**
 * Inspect the type node at a given byte offset.
 * @param desc - Raw descriptor bytes.
 * @param offset - Byte position of the node.
 * @returns typeCode, isDynamic, and staticSize in bytes.
 * @throws {CallciumError} When the descriptor contains no readable node at `offset`.
 */
function inspect(desc: Uint8Array, offset: number): TypeInfo {
  const { typeCode, staticWords } = readNode(desc, offset);
  return { typeCode, isDynamic: staticWords === 0, staticSize: staticWords * 32 };
}

/**
 * Return tuple field count at a tuple node offset.
 * @param desc - Raw descriptor bytes.
 * @param offset - Byte position of the tuple node.
 */
function tupleFieldCount(desc: Uint8Array, offset: number): number {
  return readU16(desc, offset + DF.TYPECODE_SIZE + DF.COMPOSITE_META_SIZE);
}

/**
 * Return static array length at a static array node offset.
 * @param desc - Raw descriptor bytes.
 * @param offset - Byte position of the static array node.
 */
function staticArrayLength(desc: Uint8Array, offset: number): number {
  const elemOffset = arrayElementOffset(offset);
  const elemNodeLength = nodeLength(desc, elemOffset);
  const lengthOffset = elemOffset + elemNodeLength;
  return readU16(desc, lengthOffset);
}

/**
 * Return the byte offset of the array element descriptor.
 * @param offset - Byte position of the array node (static or dynamic).
 */
function arrayElementOffset(offset: number): number {
  return offset + DF.ARRAY_HEADER_SIZE;
}

///////////////////////////////////////////////////////////////////////////
// Metadata validity
///////////////////////////////////////////////////////////////////////////

/** Composite node metadata that disagrees with the node's children. */
export type MetaFault = "NODE_LENGTH" | "STATIC_WORDS";

/** A node's span and its type's static word count, or the first node whose metadata disagrees with them. */
type MetaWalk = { span: number; staticWords: number } | { fault: MetaFault; offset: number };

/** Walk the node at `offset` by the spans of its children. */
function walkMeta(desc: Uint8Array, offset: number): MetaWalk {
  const node = readNode(desc, offset);
  if (lookupTypeCode(node.typeCode).typeClass === "elementary") {
    return { span: DF.TYPECODE_SIZE, staticWords: node.staticWords };
  }

  let span: number;
  let staticWords = 0;
  if (node.typeCode === TypeCode.TUPLE) {
    span = DF.TUPLE_HEADER_SIZE;
    let hasDynamicField = false;
    const fieldCount = tupleFieldCount(desc, offset);
    for (let i = 0; i < fieldCount; i++) {
      const field = walkMeta(desc, offset + span);
      if ("fault" in field) return field;
      span += field.span;
      staticWords += field.staticWords;
      if (field.staticWords === 0) hasDynamicField = true;
    }
    if (hasDynamicField) staticWords = 0;
  } else {
    const element = walkMeta(desc, arrayElementOffset(offset));
    if ("fault" in element) return element;
    span = DF.ARRAY_HEADER_SIZE + element.span;
    if (node.typeCode === TypeCode.STATIC_ARRAY) {
      staticWords = element.staticWords * readU16(desc, offset + span);
      span += DF.ARRAY_LENGTH_SIZE;
    }
  }
  if (span !== node.nodeLength) return { fault: "NODE_LENGTH", offset };
  if (staticWords !== node.staticWords) return { fault: "STATIC_WORDS", offset };
  return { span, staticWords };
}

/**
 * Find the first composite node whose metadata disagrees with its children (DV-1, DV-2). A node's children are checked
 * before the node.
 * @param desc - A well-formed descriptor.
 * @returns The disagreement and the node's offset, or `undefined` when every node agrees.
 */
function tryValidateMeta(desc: Uint8Array): { fault: MetaFault; offset: number } | undefined {
  let cursor = DF.HEADER_SIZE;
  const count = paramCount(desc);
  for (let i = 0; i < count; i++) {
    const walk = walkMeta(desc, cursor);
    if ("fault" in walk) return walk;
    cursor += walk.span;
  }
  return undefined;
}

/**
 * Validate every composite node's metadata against its children (DV-1, DV-2).
 * @param desc - A well-formed descriptor.
 * @throws {CallciumError} With `NODE_LENGTH_MISMATCH` or `STATIC_WORDS_MISMATCH` at the first node at fault.
 */
function validateMeta(desc: Uint8Array): void {
  const found = tryValidateMeta(desc);
  if (found?.fault === "NODE_LENGTH") {
    throw new CallciumError(
      "NODE_LENGTH_MISMATCH",
      "Composite node length differs from the span of its children",
      found.offset,
    );
  }
  if (found?.fault === "STATIC_WORDS") {
    throw new CallciumError(
      "STATIC_WORDS_MISMATCH",
      "Composite node static word count differs from its type's head size",
      found.offset,
    );
  }
}

/** Inspect and navigate raw descriptor bytes. */
export const Descriptor = {
  paramCount,
  inspect,
  tupleFieldCount,
  staticArrayLength,
  nodeLength,
  arrayElementOffset,
  validateMeta,
  tryValidateMeta,
};

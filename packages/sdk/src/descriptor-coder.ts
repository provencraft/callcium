import { readU16, readU24 } from "./bytes";
import { DescriptorFormat as DF, TypeCode, lookupTypeCode, classifyTypeCode } from "./constants";
import { Descriptor } from "./descriptor";
import { CallciumError } from "./errors";
import { address, array, bool, bytes, bytesN, function_, intN, string_, tuple, uint256, uintN } from "./type-desc";

import type { DecodedParam, DescNode, Hex } from "./types";

///////////////////////////////////////////////////////////////////////////
// Splitting helpers
///////////////////////////////////////////////////////////////////////////

/**
 * Collect the positions of depth-0 commas in input[start..end).
 * Commas inside `()` or `[]` are skipped.
 */
function commaPositions(input: string, start: number, end: number): number[] {
  const positions: number[] = [];
  let depth = 0;
  for (let i = start; i < end; i++) {
    const char = input[i];
    if (char === "(" || char === "[") {
      depth++;
    } else if (char === ")" || char === "]") {
      depth--;
    } else if (char === "," && depth === 0) {
      positions.push(i);
    }
  }
  return positions;
}

///////////////////////////////////////////////////////////////////////////
// Integer parser
///////////////////////////////////////////////////////////////////////////

/**
 * Parse a decimal integer from input[start..end).
 * Returns -1 if the substring is empty or contains non-digit characters.
 */
function parseUint(input: string, start: number, end: number): number {
  if (start >= end) return -1;
  let value = 0;
  for (let i = start; i < end; i++) {
    const code = input.charCodeAt(i);
    if (code < 48 || code > 57) return -1;
    value = value * 10 + (code - 48);
  }
  return value;
}

///////////////////////////////////////////////////////////////////////////
// Tuple parser
///////////////////////////////////////////////////////////////////////////

/**
 * Parse a tuple literal `(field0,field1,...)` where the opening `(` is at
 * `start` and the substring to parse ends before `end`.
 */
function parseTuple(input: string, start: number, end: number): Uint8Array {
  // Expect opening paren at start.
  if (input[start] !== "(") {
    throw new CallciumError("INVALID_TYPE_STRING", `Expected '(' at position ${start}`);
  }
  // Find matching closing paren.
  let depth = 0;
  let closePos = -1;
  for (let i = start; i < end; i++) {
    if (input[i] === "(") depth++;
    else if (input[i] === ")") {
      depth--;
      if (depth === 0) {
        closePos = i;
        break;
      }
    }
  }
  if (closePos === -1) {
    throw new CallciumError("INVALID_TYPE_STRING", `Unmatched '(' at position ${start}`);
  }

  const innerStart = start + 1;
  const innerEnd = closePos;
  const commas = commaPositions(input, innerStart, innerEnd);

  const segments: Array<[number, number]> = [];
  let segStart = innerStart;
  for (const comma of commas) {
    segments.push([segStart, comma]);
    segStart = comma + 1;
  }
  segments.push([segStart, innerEnd]);

  // An empty tuple `()` is not valid.
  if (segments.length === 1 && segments[0]![0] === segments[0]![1]) {
    throw new CallciumError("INVALID_TYPE_STRING", "Empty tuple is not allowed");
  }

  const fieldDescs = segments.map(([fieldStart, fieldEnd]) => parseType(input, fieldStart, fieldEnd));
  return tuple(fieldDescs);
}

///////////////////////////////////////////////////////////////////////////
// Base type parser
///////////////////////////////////////////////////////////////////////////

/** Parse the base type (no array suffixes) from input[start..end). */
function parseBaseType(input: string, start: number, end: number): Uint8Array {
  const segment = input.slice(start, end);

  if (segment === "address") return address();
  if (segment === "bool") return bool();
  if (segment === "function") return function_();
  if (segment === "bytes") return bytes();
  if (segment === "string") return string_();
  if (segment === "uint256") return uint256();
  if (segment === "int256") return intN(256);

  if (segment.startsWith("(")) return parseTuple(input, start, end);

  // uintN
  if (segment.startsWith("uint")) {
    const bits = parseUint(input, start + 4, end);
    if (bits === -1) {
      throw new CallciumError("UNKNOWN_TYPE", `Unrecognised type '${segment}'`);
    }
    return uintN(bits);
  }

  // intN
  if (segment.startsWith("int")) {
    const bits = parseUint(input, start + 3, end);
    if (bits === -1) {
      throw new CallciumError("UNKNOWN_TYPE", `Unrecognised type '${segment}'`);
    }
    return intN(bits);
  }

  // bytesN
  if (segment.startsWith("bytes")) {
    const n = parseUint(input, start + 5, end);
    if (n === -1) {
      throw new CallciumError("UNKNOWN_TYPE", `Unrecognised type '${segment}'`);
    }
    return bytesN(n);
  }

  throw new CallciumError("UNKNOWN_TYPE", `Unrecognised type '${segment}'`);
}

///////////////////////////////////////////////////////////////////////////
// Array suffix collector
///////////////////////////////////////////////////////////////////////////

/**
 * Parse a type segment from input[start..end).
 *
 * Scans backward from end to collect all `[...]` suffixes, identifies the
 * base type extent, parses the base, then applies suffixes left-to-right.
 */
function parseType(input: string, start: number, end: number): Uint8Array {
  if (start >= end) {
    throw new CallciumError("INVALID_TYPE_STRING", "Empty type segment");
  }

  // Collect array suffixes by scanning backward.
  // Each suffix is either `[]` (dynamic) or `[N]` (static with length N).
  const suffixes: Array<number | undefined> = [];
  let baseEnd = end;

  while (baseEnd > start && input[baseEnd - 1] === "]") {
    // Find the matching `[`.
    const closePos = baseEnd - 1;
    let openPos = closePos - 1;
    // Walk back past digits (for static arrays).
    while (openPos > start && input[openPos] !== "[") {
      openPos--;
    }
    if (input[openPos] !== "[") {
      throw new CallciumError("INVALID_TYPE_STRING", `Unmatched ']' at position ${closePos}`);
    }
    const innerStart = openPos + 1;
    const innerEnd = closePos;
    if (innerStart === innerEnd) {
      // Dynamic array `[]`.
      suffixes.unshift(undefined);
    } else {
      const length = parseUint(input, innerStart, innerEnd);
      if (length === -1) {
        throw new CallciumError("INVALID_TYPE_STRING", `Invalid array length at position ${innerStart}`);
      }
      suffixes.unshift(length);
    }
    baseEnd = openPos;
  }

  let desc = parseBaseType(input, start, baseEnd);

  // Apply suffixes left-to-right: the leftmost suffix is the outermost array.
  for (const length of suffixes) {
    desc = array(desc, length);
  }

  return desc;
}

///////////////////////////////////////////////////////////////////////////
// Public interface
///////////////////////////////////////////////////////////////////////////

/**
 * Encode a comma-separated list of ABI type strings into a binary descriptor.
 *
 * @param typesCsv - Comma-separated ABI type strings, e.g. `"address,uint256,(bool,bytes32)[],string"`.
 * @returns Binary descriptor bytes starting with the version+paramCount header.
 * @throws {CallciumError} With code `INVALID_TYPE_STRING` for malformed input.
 * @throws {CallciumError} With code `UNKNOWN_TYPE` for unrecognised type names.
 */
function fromTypes(typesCsv: string): Uint8Array {
  if (typesCsv === "") {
    return new Uint8Array([DF.VERSION, 0x00]);
  }

  const commas = commaPositions(typesCsv, 0, typesCsv.length);

  const segments: Array<[number, number]> = [];
  let segStart = 0;
  for (const comma of commas) {
    segments.push([segStart, comma]);
    segStart = comma + 1;
  }
  segments.push([segStart, typesCsv.length]);

  const paramDescs = segments.map(([start, end]) => parseType(typesCsv, start, end));
  if (paramDescs.length > DF.MAX_PARAMS) {
    throw new CallciumError(
      "DESCRIPTOR_TOO_LARGE",
      `Parameter count ${paramDescs.length} exceeds maximum ${DF.MAX_PARAMS}.`,
    );
  }
  const totalBytes = paramDescs.reduce((sum, d) => sum + d.length, 0);
  const result = new Uint8Array(DF.HEADER_SIZE + totalBytes);
  result[0] = DF.VERSION;
  result[1] = paramDescs.length;
  let offset = DF.HEADER_SIZE;
  for (const desc of paramDescs) {
    result.set(desc, offset);
    offset += desc.length;
  }
  return result;
}

///////////////////////////////////////////////////////////////////////////
// Inverse: descriptor bytes → type string
///////////////////////////////////////////////////////////////////////////

/** Reconstruct a Solidity type string from a descriptor node at the given offset. */
function nodeToTypeString(desc: Uint8Array, offset: number): string {
  const typeCode = desc[offset]!;

  if (typeCode === TypeCode.TUPLE) {
    const fieldCount = Descriptor.tupleFieldCount(desc, offset);
    const fieldTypes: string[] = [];
    let fieldOffset = offset + DF.TUPLE_HEADER_SIZE;
    for (let i = 0; i < fieldCount; i++) {
      fieldTypes.push(nodeToTypeString(desc, fieldOffset));
      fieldOffset += Descriptor.nodeLength(desc, fieldOffset);
    }
    return `(${fieldTypes.join(",")})`;
  }

  if (typeCode === TypeCode.STATIC_ARRAY) {
    const length = Descriptor.staticArrayLength(desc, offset);
    const elemType = nodeToTypeString(desc, Descriptor.arrayElementOffset(desc, offset));
    return `${elemType}[${length}]`;
  }

  if (typeCode === TypeCode.DYNAMIC_ARRAY) {
    const elemType = nodeToTypeString(desc, Descriptor.arrayElementOffset(desc, offset));
    return `${elemType}[]`;
  }

  return lookupTypeCode(typeCode).label;
}

/**
 * Reconstruct a comma-separated list of ABI type strings from a binary descriptor.
 *
 * Inverse of `fromTypes`: `toTypes(fromTypes(s))` returns `s` for any valid input.
 *
 * @param desc - Binary descriptor bytes (with version+paramCount header).
 * @returns Comma-separated ABI type strings, e.g. `"address,uint256,(bool,bytes32)[]"`.
 * @throws {CallciumError} If the descriptor is malformed.
 */
function toTypes(desc: Uint8Array): string {
  const count = Descriptor.paramCount(desc);
  const types: string[] = [];
  let offset = DF.HEADER_SIZE;
  for (let i = 0; i < count; i++) {
    types.push(nodeToTypeString(desc, offset));
    offset += Descriptor.nodeLength(desc, offset);
  }
  return types.join(",");
}

///////////////////////////////////////////////////////////////////////////
// Descriptor binary decoder
///////////////////////////////////////////////////////////////////////////

type ParseResult = { node: DescNode; next: number };

/** Recursively parse a single descriptor node starting at offset. */
function parseNode(data: Uint8Array, offset: number): ParseResult {
  if (offset >= data.length) {
    throw new CallciumError("UNEXPECTED_END", "Unexpected end of descriptor", offset);
  }

  const code = data[offset]!;
  const info = classifyTypeCode(code);
  const metaOffset = offset + DF.TYPECODE_SIZE;

  if (info.typeClass === "elementary") {
    const node: DescNode = {
      type: "elementary",
      typeCode: code,
      isDynamic: info.isDynamic,
      staticSize: info.isDynamic ? 0 : 32,
      span: { start: offset, end: metaOffset },
    };
    return { node, next: metaOffset };
  }

  const metaEnd = metaOffset + DF.COMPOSITE_META_SIZE;
  if (metaEnd > data.length) {
    throw new CallciumError("UNEXPECTED_END", "Incomplete composite metadata", offset);
  }

  const meta = readU24(data, metaOffset);
  const staticWords = meta >> DF.META_STATIC_WORDS_SHIFT;
  const nodeLength = meta & DF.META_NODE_LENGTH_MASK;

  const minHeader = info.typeClass === "tuple" ? DF.TUPLE_HEADER_SIZE : DF.ARRAY_HEADER_SIZE;
  if (nodeLength < minHeader) {
    throw new CallciumError(
      "MALFORMED_HEADER",
      `Composite node length ${nodeLength} is smaller than minimum header ${minHeader}`,
      offset,
    );
  }
  if (offset + nodeLength > data.length) {
    throw new CallciumError("NODE_OVERFLOW", "Composite node extends beyond descriptor", offset);
  }

  const isDynamic = staticWords === 0;
  const staticSize = isDynamic ? 0 : staticWords * 32;
  const nodeEnd = offset + nodeLength;

  if (info.typeClass === "tuple") {
    const fieldCountOffset = metaEnd;
    if (fieldCountOffset + 2 > data.length) {
      throw new CallciumError("UNEXPECTED_END", "Incomplete tuple header", offset);
    }
    const fieldCount = readU16(data, fieldCountOffset);
    if (fieldCount === 0) {
      throw new CallciumError("INVALID_TUPLE_FIELD_COUNT", "Tuple must have at least one field", offset);
    }
    if (fieldCount > DF.MAX_TUPLE_FIELDS) {
      throw new CallciumError(
        "INVALID_TUPLE_FIELD_COUNT",
        `Tuple field count ${fieldCount} exceeds maximum ${DF.MAX_TUPLE_FIELDS}`,
        offset,
      );
    }

    const fields: DescNode[] = [];
    let cursor = offset + DF.TUPLE_HEADER_SIZE;
    for (let i = 0; i < fieldCount; i++) {
      const result = parseNode(data, cursor);
      fields.push(result.node);
      cursor = result.next;
    }

    const node: DescNode = {
      type: "tuple",
      typeCode: code,
      isDynamic,
      staticSize,
      fields,
      span: { start: offset, end: nodeEnd },
    };
    return { node, next: nodeEnd };
  }

  if (info.typeClass === "staticArray") {
    const elemResult = parseNode(data, offset + DF.ARRAY_HEADER_SIZE);
    const lengthOffset = elemResult.next;
    if (lengthOffset + DF.ARRAY_LENGTH_SIZE > data.length) {
      throw new CallciumError("UNEXPECTED_END", "Missing static array length suffix", offset);
    }
    const length = readU16(data, lengthOffset);
    if (length === 0) {
      throw new CallciumError("INVALID_ARRAY_LENGTH", "Static array length must be greater than zero", offset);
    }
    if (length > DF.MAX_STATIC_ARRAY_LENGTH) {
      throw new CallciumError(
        "INVALID_ARRAY_LENGTH",
        `Static array length ${length} exceeds maximum ${DF.MAX_STATIC_ARRAY_LENGTH}`,
        offset,
      );
    }

    const node: DescNode = {
      type: "staticArray",
      typeCode: code,
      isDynamic,
      staticSize,
      element: elemResult.node,
      length,
      span: { start: offset, end: nodeEnd },
    };
    return { node, next: nodeEnd };
  }

  const elemResult = parseNode(data, offset + DF.ARRAY_HEADER_SIZE);
  const node: DescNode = {
    type: "dynamicArray",
    typeCode: code,
    isDynamic: true,
    staticSize: 0,
    element: elemResult.node,
    span: { start: offset, end: nodeEnd },
  };
  return { node, next: nodeEnd };
}

/** Convert a zero-based param index to a BE16 hex path step. */
function indexToPath(index: number): Hex {
  return `0x${index.toString(16).padStart(4, "0")}`;
}

type DecodedDescriptor = {
  version: number;
  params: DecodedParam[];
};

/** Decode a binary descriptor blob, returning the structural representation and AST. */
export function decodeDescriptor(data: Uint8Array): {
  descriptor: DecodedDescriptor;
  tree: DescNode[];
} {
  if (data.length < 1) {
    throw new CallciumError("MALFORMED_HEADER", "Descriptor is empty");
  }

  const version = data[0]!;
  if (version !== DF.VERSION) {
    throw new CallciumError("UNSUPPORTED_VERSION", `Version ${version} is not supported (expected ${DF.VERSION})`);
  }

  if (data.length < DF.HEADER_SIZE) {
    throw new CallciumError("MALFORMED_HEADER", "Descriptor too short for header");
  }

  const declaredCount = data[1]!;
  const params: DecodedParam[] = [];
  const tree: DescNode[] = [];
  let cursor: number = DF.HEADER_SIZE;

  while (cursor < data.length) {
    if (params.length >= DF.MAX_PARAMS) {
      throw new CallciumError(
        "PARAM_COUNT_MISMATCH",
        `Descriptor exceeds the maximum of ${DF.MAX_PARAMS} top-level params`,
      );
    }

    const { node, next } = parseNode(data, cursor);
    tree.push(node);

    params.push({
      index: params.length,
      typeCode: node.typeCode,
      isDynamic: node.isDynamic,
      staticSize: node.staticSize,
      path: indexToPath(params.length),
      span: { start: cursor, end: next },
    });

    cursor = next;
  }

  if (params.length !== declaredCount) {
    throw new CallciumError(
      "PARAM_COUNT_MISMATCH",
      `Header declares ${declaredCount} params but ${params.length} were parsed`,
    );
  }

  return {
    descriptor: { version, params },
    tree,
  };
}

/** Encode and decode descriptors. */
export const DescriptorCoder = { fromTypes, toTypes };

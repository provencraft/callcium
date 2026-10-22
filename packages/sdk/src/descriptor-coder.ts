import { concatBytes } from "@noble/hashes/utils.js";

import { readU16 } from "./bytes";
import { DescriptorFormat as DF } from "./constants";
import { Descriptor, readNode } from "./descriptor";
import { CallciumError } from "./errors";
import { lookupTypeCode } from "./operators";
import { address, array, bool, bytes, bytesN, function_, intN, string_, tuple, uintN } from "./type-desc";

import type { DecodedDescriptor, DecodedNode } from "./types";

///////////////////////////////////////////////////////////////////////////
// Splitting helpers
///////////////////////////////////////////////////////////////////////////

/**
 * Collect the positions of depth-0 commas in input[start..end). Commas inside `()` or `[]` are skipped.
 */
function commaPositions(input: string, start: number, end: number): number[] {
  const positions: number[] = [];
  let depth = 0;
  for (let i = start; i < end; i++) {
    const char = input[i];
    if (char === "(" || char === "[") {
      depth++;
    } else if (char === ")" || char === "]") {
      if (depth === 0) {
        throw new CallciumError("MALFORMED_TYPE_STRING", `Unmatched '${char}' at position ${i}`);
      }
      depth--;
    } else if (char === "," && depth === 0) {
      positions.push(i);
    }
  }
  if (depth !== 0) {
    throw new CallciumError("MALFORMED_TYPE_STRING", `Unclosed '${input.slice(start, end)}'`);
  }
  return positions;
}

///////////////////////////////////////////////////////////////////////////
// Integer parser
///////////////////////////////////////////////////////////////////////////

/** Widest number a type string can spell: the array length field is the widest field one feeds. */
const MAX_TYPE_STRING_NUMBER = 256 ** DF.ARRAY_LENGTH_SIZE - 1;

/**
 * Parse a decimal integer from input[start..end).
 *
 * Rejects an empty span, a non-digit, a leading zero, and a value too wide for the fields a type string feeds. Width
 * and length validity are out of scope here.
 */
function parseUint(input: string, start: number, end: number): number {
  if (start >= end) {
    throw new CallciumError("MALFORMED_TYPE_STRING", `Missing number at position ${start}`);
  }
  // A leading zero is never canonical ABI spelling (uint08, bytes01, [03]).
  if (end - start > 1 && input.charCodeAt(start) === 48) {
    throw new CallciumError("MALFORMED_TYPE_STRING", `Zero-padded number at position ${start}`);
  }
  let value = 0;
  for (let i = start; i < end; i++) {
    const code = input.charCodeAt(i);
    if (code < 48 || code > 57) {
      throw new CallciumError("MALFORMED_TYPE_STRING", `Non-digit character at position ${i}`);
    }
    value = value * 10 + (code - 48);
  }
  if (value > MAX_TYPE_STRING_NUMBER) {
    throw new CallciumError("MALFORMED_TYPE_STRING", `Number at position ${start} is too wide`);
  }
  return value;
}

///////////////////////////////////////////////////////////////////////////
// Tuple parser
///////////////////////////////////////////////////////////////////////////

/**
 * Parse a tuple literal `(field0,field1,...)` whose opening `(` is at `start` and whose content ends before `end`.
 */
function parseTuple(input: string, start: number, end: number): Uint8Array {
  if (input[start] !== "(") {
    throw new CallciumError("MALFORMED_TYPE_STRING", `Expected '(' at position ${start}`);
  }
  let depth = 0;
  let closeIndex = -1;
  for (let i = start; i < end; i++) {
    if (input[i] === "(") depth++;
    else if (input[i] === ")") {
      depth--;
      if (depth === 0) {
        closeIndex = i;
        break;
      }
    }
  }
  if (closeIndex === -1) {
    throw new CallciumError("MALFORMED_TYPE_STRING", `Unmatched '(' at position ${start}`);
  }
  if (closeIndex !== end - 1) {
    throw new CallciumError("MALFORMED_TYPE_STRING", `Unexpected characters after ')' at position ${closeIndex + 1}`);
  }

  const innerStart = start + 1;
  const innerEnd = closeIndex;
  const commas = commaPositions(input, innerStart, innerEnd);

  const segments: Array<[number, number]> = [];
  let segmentStart = innerStart;
  for (const comma of commas) {
    segments.push([segmentStart, comma]);
    segmentStart = comma + 1;
  }
  segments.push([segmentStart, innerEnd]);

  // An empty tuple has no fields to parse; the tuple builder rejects the count.
  if (segments.length === 1 && segments[0]![0] === segments[0]![1]) return tuple([]);

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
  if (segment.startsWith("(")) return parseTuple(input, start, end);

  // A prefix with no width after it spells no type, so it falls through to the unknown-type report rather than being
  // read as a width that is not there. A width outside its type's range names no type either.
  if (segment.length > 4 && segment.startsWith("uint")) {
    const bits = parseUint(input, start + 4, end);
    if (bits >= 8 && bits <= 256 && bits % 8 === 0) return uintN(bits);
  } else if (segment.length > 3 && segment.startsWith("int")) {
    const bits = parseUint(input, start + 3, end);
    if (bits >= 8 && bits <= 256 && bits % 8 === 0) return intN(bits);
  } else if (segment.length > 5 && segment.startsWith("bytes")) {
    const length = parseUint(input, start + 5, end);
    if (length >= 1 && length <= 32) return bytesN(length);
  }

  throw new CallciumError("UNKNOWN_TYPE", `Unknown type '${segment}'`);
}

///////////////////////////////////////////////////////////////////////////
// Array suffix collector
///////////////////////////////////////////////////////////////////////////

/**
 * Parse a type segment from input[start..end).
 *
 * Scans backward from end to collect all `[...]` suffixes, identifies the base type extent, parses the base, then
 * applies suffixes left-to-right.
 */
function parseType(input: string, start: number, end: number): Uint8Array {
  if (start >= end) {
    throw new CallciumError("MALFORMED_TYPE_STRING", "Empty type segment");
  }

  // Locate array suffixes by scanning backward, reading no length yet: the base names the type, so an unrecognised one
  // is reported before a suffix it carries is parsed.
  const spans: Array<[number, number]> = [];
  let baseEnd = end;

  while (baseEnd > start && input[baseEnd - 1] === "]") {
    const closeIndex = baseEnd - 1;
    let openIndex = closeIndex - 1;
    // Walk back past digits (for static arrays).
    while (openIndex > start && input[openIndex] !== "[") {
      openIndex--;
    }
    if (input[openIndex] !== "[") {
      throw new CallciumError("MALFORMED_TYPE_STRING", `Unmatched ']' at position ${closeIndex}`);
    }
    spans.unshift([openIndex + 1, closeIndex]);
    baseEnd = openIndex;
  }

  let desc = parseBaseType(input, start, baseEnd);

  // Apply suffixes left-to-right: the leftmost suffix is the innermost array. A dynamic array spells no length at all.
  for (const [innerStart, innerEnd] of spans) {
    desc = array(desc, innerStart === innerEnd ? undefined : parseUint(input, innerStart, innerEnd));
  }

  return desc;
}

///////////////////////////////////////////////////////////////////////////
// Public interface
///////////////////////////////////////////////////////////////////////////

/**
 * Encode a comma-separated list of ABI type strings into a binary descriptor.
 *
 * @param typesCsv - Comma-separated ABI type strings, for example `"address,uint256,(bool,bytes32)[],string"`.
 * @returns Binary descriptor bytes starting with the version+paramCount header.
 * @throws {CallciumError} With code `MALFORMED_TYPE_STRING` for malformed input.
 * @throws {CallciumError} With code `UNKNOWN_TYPE` for unrecognised type names.
 * @throws {CallciumError} With code `NESTING_TOO_DEEP` when composite nesting exceeds `MAX_NESTING_DEPTH`.
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
    throw new CallciumError("TOO_MANY_PARAMS", `Parameter count ${paramDescs.length} exceeds maximum ${DF.MAX_PARAMS}`);
  }
  const result = concatBytes(Uint8Array.of(DF.VERSION, paramDescs.length), ...paramDescs);
  // Nesting depth is a property of the assembled descriptor, not of any single node.
  decodeDescriptor(result);
  return result;
}

///////////////////////////////////////////////////////////////////////////
// Descriptor binary decoder
///////////////////////////////////////////////////////////////////////////

/** A parsed descriptor node and the offset just past it. */
type ParseResult = { node: DecodedNode; next: number };

/** Recursively parse a single descriptor node starting at offset, its span shifted by `base`. */
function parseNode(data: Uint8Array, offset: number, depth: number, base: number): ParseResult {
  const { typeCode: code, staticWords, nodeLength } = readNode(data, offset);
  const info = lookupTypeCode(code);
  const isDynamic = staticWords === 0;
  const staticSize = isDynamic ? 0 : staticWords * 32;
  const nodeEnd = offset + nodeLength;
  const span = { start: base + offset, end: base + nodeEnd };

  if (info.typeClass === "elementary") {
    return { node: { typeClass: "elementary", typeCode: code, isDynamic, staticSize, span }, next: nodeEnd };
  }

  // Only composites nest; a leaf below the deepest allowed composite is fine.
  if (depth > DF.MAX_NESTING_DEPTH) {
    throw new CallciumError(
      "NESTING_TOO_DEEP",
      `Composite nesting exceeds maximum depth ${DF.MAX_NESTING_DEPTH}`,
      offset,
    );
  }

  if (info.typeClass === "tuple") {
    const fieldCountOffset = offset + DF.TYPECODE_SIZE + DF.COMPOSITE_META_SIZE;
    if (fieldCountOffset + DF.TUPLE_FIELDCOUNT_SIZE > data.length) {
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

    const fields: DecodedNode[] = [];
    let cursor = offset + DF.TUPLE_HEADER_SIZE;
    for (let i = 0; i < fieldCount; i++) {
      const field = parseNode(data, cursor, depth + 1, base);
      fields.push(field.node);
      cursor = field.next;
    }

    return { node: { typeClass: "tuple", typeCode: code, isDynamic, staticSize, span, fields }, next: nodeEnd };
  }

  const element = parseNode(data, Descriptor.arrayElementOffset(offset), depth + 1, base);

  if (info.typeClass === "staticArray") {
    const lengthOffset = element.next;
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

    const node: DecodedNode = {
      typeClass: "staticArray",
      typeCode: code,
      isDynamic,
      staticSize,
      span,
      length,
      element: element.node,
    };
    return { node, next: nodeEnd };
  }

  const node: DecodedNode = {
    typeClass: "dynamicArray",
    typeCode: code,
    isDynamic: true,
    staticSize: 0,
    span,
    element: element.node,
  };
  return { node, next: nodeEnd };
}

/**
 * Decode a binary descriptor blob, returning its structural representation.
 * @param data - The descriptor bytes.
 * @param base - Byte offset of the descriptor in the blob its spans locate.
 * @throws {CallciumError} When the descriptor breaks a well-formedness invariant.
 */
export function decodeDescriptor(data: Uint8Array, base = 0): DecodedDescriptor {
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

  const params: DecodedNode[] = [];
  let cursor: number = DF.HEADER_SIZE;

  while (cursor < data.length) {
    const { node, next } = parseNode(data, cursor, 1, base);

    if (params.length === DF.MAX_PARAMS) {
      throw new CallciumError("TOO_MANY_PARAMS", `Descriptor exceeds the maximum of ${DF.MAX_PARAMS} top-level params`);
    }

    params.push(node);
    cursor = next;
  }

  const declaredCount = data[DF.HEADER_PARAMCOUNT_OFFSET]!;
  if (params.length !== declaredCount) {
    throw new CallciumError(
      "PARAM_COUNT_MISMATCH",
      `Header declares ${declaredCount} params but ${params.length} were parsed`,
    );
  }

  return {
    version: { value: version, span: { start: base, end: base + DF.HEADER_PARAMCOUNT_OFFSET } },
    paramCount: {
      value: declaredCount,
      span: { start: base + DF.HEADER_PARAMCOUNT_OFFSET, end: base + DF.HEADER_SIZE },
    },
    params,
    span: { start: base, end: base + data.length },
  };
}

///////////////////////////////////////////////////////////////////////////
// Descriptor inspection
///////////////////////////////////////////////////////////////////////////

/**
 * Decode a binary descriptor and check every composite node against its children.
 * @param desc - The descriptor bytes.
 * @param base - Byte offset of the descriptor in the blob its spans locate.
 * @throws {CallciumError} If the descriptor is malformed, or a composite node disagrees with its children.
 */
export function inspectDescriptor(desc: Uint8Array, base = 0): DecodedDescriptor {
  const decoded = decodeDescriptor(desc, base);
  Descriptor.validateMeta(desc);
  return decoded;
}

/**
 * Inspect a binary descriptor: its header fields and its parameters as a tree of nodes, each with the bytes it spans.
 * @param desc - Binary descriptor bytes (with version+paramCount header).
 * @returns The decoded descriptor.
 * @throws {CallciumError} If the descriptor is malformed, or a composite node disagrees with its children.
 */
function inspect(desc: Uint8Array): DecodedDescriptor {
  return inspectDescriptor(desc);
}

/** Reconstruct the ABI type string of a decoded node. */
function typeString(node: DecodedNode): string {
  switch (node.typeClass) {
    case "elementary":
      return lookupTypeCode(node.typeCode).label;
    case "tuple":
      return `(${node.fields.map(typeString).join(",")})`;
    case "staticArray":
      return `${typeString(node.element)}[${node.length}]`;
    case "dynamicArray":
      return `${typeString(node.element)}[]`;
    default:
      return node satisfies never;
  }
}

/**
 * Reconstruct a comma-separated list of ABI type strings from a binary descriptor. `fromTypes(toTypes(desc))` returns
 * `desc` for every descriptor `inspect` accepts.
 * @param desc - Binary descriptor bytes (with version+paramCount header).
 * @returns Comma-separated ABI type strings, for example `"address,uint256,(bool,bytes32)[]"`.
 * @throws {CallciumError} If the descriptor is malformed, or a composite node disagrees with its children.
 */
function toTypes(desc: Uint8Array): string {
  return inspect(desc).params.map(typeString).join(",");
}

/** Encode descriptors from type strings, inspect them and read their type strings back. */
export const DescriptorCoder = { fromTypes, inspect, toTypes };

import { DescriptorFormat as DF, TypeCode, lookupTypeCode } from "./constants";
import { Descriptor } from "./descriptor";
import { CallciumError } from "./errors";
import { address, array, bool, bytes, bytesN, function_, intN, string_, tuple, uint256, uintN } from "./type-desc";

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

/** Encode and decode descriptors. */
export const DescriptorCoder = { fromTypes, toTypes };

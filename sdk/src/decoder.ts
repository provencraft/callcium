import {
  DescriptorFormat as DF,
  PolicyFormat as PF,
  Scope,
  Limits,
  Op,
  TypeCode,
  isValidOperatorData,
} from "./constants";
import { CallciumError } from "./errors";
import { hexToBytes, toHex, readU16 } from "./hex";

import type { DecodedDescriptor, DecodedGroup, DecodedParam, DecodedPolicy, DecodedRule, DescNode, Hex } from "./types";

///////////////////////////////////////////////////////////////////////////
//                           Binary readers
///////////////////////////////////////////////////////////////////////////

/** Read a big-endian uint24 from a byte array. */
function readU24(data: Uint8Array, offset: number): number {
  return (data[offset]! << 16) | (data[offset + 1]! << 8) | data[offset + 2]!;
}

/** Read a big-endian uint32 from a byte array. */
function readU32(data: Uint8Array, offset: number): number {
  return ((data[offset]! << 24) | (data[offset + 1]! << 16) | (data[offset + 2]! << 8) | data[offset + 3]!) >>> 0;
}

///////////////////////////////////////////////////////////////////////////
//                      Type code classification
///////////////////////////////////////////////////////////////////////////

type TypeClass = "elementary" | "tuple" | "staticArray" | "dynamicArray";

/** Format a byte value as 0x-prefixed 2-digit hex for error messages. */
function formatTypeCode(code: number): string {
  return `0x${code.toString(16).padStart(2, "0")}`;
}

type TypeInfo = { typeClass: TypeClass; isDynamic: boolean };

/** Map a raw type code byte to its structural category and dynamism. */
function classifyTypeCode(code: number): TypeInfo {
  // Unsigned integers.
  if (code >= TypeCode.UINT_MIN && code <= TypeCode.UINT_MAX) return { typeClass: "elementary", isDynamic: false };

  // Signed integers.
  if (code >= TypeCode.INT_MIN && code <= TypeCode.INT_MAX) return { typeClass: "elementary", isDynamic: false };

  // Fixed types.
  if (code === TypeCode.ADDRESS || code === TypeCode.BOOL || code === TypeCode.FUNCTION)
    return { typeClass: "elementary", isDynamic: false };

  // Reserved in fixed type range.
  if (code >= 0x43 && code <= 0x4f)
    throw new CallciumError("UNKNOWN_TYPE_CODE", `Unknown type code ${formatTypeCode(code)}`);

  // Fixed bytes.
  if (code >= TypeCode.FIXED_BYTES_MIN && code <= TypeCode.FIXED_BYTES_MAX)
    return { typeClass: "elementary", isDynamic: false };

  // Dynamic elementary.
  if (code === TypeCode.BYTES || code === TypeCode.STRING) return { typeClass: "elementary", isDynamic: true };

  // Reserved in dynamic elementary range.
  if (code >= 0x72 && code <= 0x7f)
    throw new CallciumError("UNKNOWN_TYPE_CODE", `Unknown type code ${formatTypeCode(code)}`);

  // Arrays.
  if (code === TypeCode.STATIC_ARRAY) return { typeClass: "staticArray", isDynamic: false };
  if (code === TypeCode.DYNAMIC_ARRAY) return { typeClass: "dynamicArray", isDynamic: true };

  // Reserved in array range.
  if (code >= 0x82 && code <= 0x8f)
    throw new CallciumError("UNKNOWN_TYPE_CODE", `Unknown type code ${formatTypeCode(code)}`);

  // Tuple.
  if (code === TypeCode.TUPLE) return { typeClass: "tuple", isDynamic: false };

  // Reserved in tuple range.
  if (code >= 0x91 && code <= 0x9f)
    throw new CallciumError("UNKNOWN_TYPE_CODE", `Unknown type code ${formatTypeCode(code)}`);

  // Reserved range 0xA0-0xFF and anything else.
  throw new CallciumError("UNKNOWN_TYPE_CODE", `Unknown type code ${formatTypeCode(code)}`);
}

///////////////////////////////////////////////////////////////////////////
//                       Recursive node parser
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

  // Elementary types: single byte, no metadata.
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

  // Composite types: read meta.
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

  // Dynamic array.
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

///////////////////////////////////////////////////////////////////////////
//                             Path helper
///////////////////////////////////////////////////////////////////////////

/** Convert a zero-based param index to a BE16 hex path step. */
function indexToPath(index: number): Hex {
  return `0x${index.toString(16).padStart(4, "0")}`;
}

///////////////////////////////////////////////////////////////////////////
//                        Descriptor decoder
///////////////////////////////////////////////////////////////////////////

/** Decode a binary descriptor blob, returning both the public structure and internal AST. */
export function _decodeDescriptorFromBytes(data: Uint8Array): {
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

/**
 * Decode a binary descriptor blob into its public representation.
 * @param blob - Binary descriptor as 0x-prefixed hex string.
 * @returns The decoded descriptor with param metadata and byte spans.
 * @throws {CallciumError} If the blob is structurally malformed.
 */
export function decodeDescriptor(blob: Hex): DecodedDescriptor {
  return _decodeDescriptorFromBytes(hexToBytes(blob)).descriptor;
}

///////////////////////////////////////////////////////////////////////////
//                         Policy field helper
///////////////////////////////////////////////////////////////////////////

/** Wrap a value with its byte span for positional tracking. */
function field<T>(value: T, start: number, end: number): { value: T; span: { start: number; end: number } } {
  return { value, span: { start, end } };
}

///////////////////////////////////////////////////////////////////////////
//                           POLICY DECODER
///////////////////////////////////////////////////////////////////////////

/** Decode a binary policy blob, returning both the public structure and internal AST. */
export function _decodePolicyFromBytes(data: Uint8Array): {
  policy: DecodedPolicy;
  tree: DescNode[];
} {
  // Minimum header: header(1) + selector(4) + descLength(2) = 7 bytes, plus groupCount(1).
  if (data.length < PF.DESC_OFFSET + 1) {
    throw new CallciumError("MALFORMED_HEADER", "Policy blob is too short");
  }

  const headerByte = data[0]!;
  const version = headerByte & PF.VERSION_MASK;
  if (version !== PF.VERSION) {
    throw new CallciumError("UNSUPPORTED_VERSION", `Version ${version} is not supported (expected ${PF.VERSION})`);
  }
  if ((headerByte & PF.RESERVED_MASK) !== 0) {
    throw new CallciumError("MALFORMED_HEADER", "Reserved header bits must be zero");
  }

  const isSelectorless = (headerByte & PF.FLAG_NO_SELECTOR) !== 0;

  const selectorStart = PF.SELECTOR_OFFSET;
  const selectorEnd = selectorStart + PF.SELECTOR_SIZE;
  const selectorHex = toHex(data, selectorStart, selectorEnd);

  if (isSelectorless && selectorHex !== "0x00000000") {
    throw new CallciumError("MALFORMED_HEADER", "Selectorless policy must have a zeroed selector slot");
  }

  const descLengthStart = PF.DESC_LENGTH_OFFSET;
  const descLengthValue = readU16(data, descLengthStart);
  if (descLengthValue < 2) {
    throw new CallciumError("MALFORMED_HEADER", "Descriptor length must be at least 2");
  }

  const descStart = PF.DESC_OFFSET;
  const descEnd = descStart + descLengthValue;
  const groupCountOffset = descEnd;

  if (data.length < groupCountOffset + PF.GROUP_COUNT_SIZE) {
    throw new CallciumError("MALFORMED_HEADER", "Policy blob is too short for descriptor and group count");
  }

  // Decode the embedded descriptor, offsetting spans to be relative to the policy blob.
  const descSlice = data.subarray(descStart, descEnd);
  const { descriptor: desc, tree } = _decodeDescriptorFromBytes(descSlice);
  const params: DecodedParam[] = desc.params.map((param) => ({
    ...param,
    span: {
      start: descStart + param.span.start,
      end: descStart + param.span.end,
    },
  }));
  const descriptorRaw = toHex(data, descStart, descEnd);

  const groupCountStart = groupCountOffset;
  const groupCountEnd = groupCountStart + PF.GROUP_COUNT_SIZE;
  const groupCountValue = data[groupCountOffset]!;
  if (groupCountValue === 0) {
    throw new CallciumError("EMPTY_POLICY", "Policy must contain at least one group");
  }

  let offset = groupCountEnd;
  const groups: DecodedGroup[] = [];

  for (let groupIndex = 0; groupIndex < groupCountValue; groupIndex++) {
    if (offset + PF.GROUP_HEADER_SIZE > data.length) {
      throw new CallciumError("UNEXPECTED_END", "Unexpected end while reading group header", offset);
    }

    const ruleCountStart = offset;
    const ruleCountValue = readU16(data, ruleCountStart);
    const groupSizeStart = offset + PF.GROUP_RULECOUNT_SIZE;
    const groupSizeValue = readU32(data, groupSizeStart);
    const groupBodyStart = offset + PF.GROUP_HEADER_SIZE;
    const groupEnd = groupBodyStart + groupSizeValue;

    if (ruleCountValue === 0) {
      throw new CallciumError("EMPTY_GROUP", "Group must contain at least one rule", offset);
    }
    if (groupSizeValue < ruleCountValue * PF.RULE_MIN_SIZE) {
      throw new CallciumError("GROUP_SIZE_MISMATCH", "Declared group size is too small for its rule count", offset);
    }
    if (groupEnd > data.length) {
      throw new CallciumError("GROUP_OVERFLOW", "Group extends beyond policy blob", offset);
    }

    const rules: DecodedRule[] = [];
    let ruleOffset = groupBodyStart;

    for (let ruleIndex = 0; ruleIndex < ruleCountValue; ruleIndex++) {
      if (ruleOffset + PF.RULE_SIZE_SIZE > data.length) {
        throw new CallciumError("UNEXPECTED_END", "Unexpected end while reading rule size", ruleOffset);
      }

      const ruleSizeValue = readU16(data, ruleOffset);
      if (ruleSizeValue < PF.RULE_MIN_SIZE) {
        throw new CallciumError(
          "RULE_SIZE_MISMATCH",
          `Rule size ${ruleSizeValue} is below minimum ${PF.RULE_MIN_SIZE}`,
          ruleOffset,
        );
      }
      if (ruleOffset + ruleSizeValue > groupEnd) {
        throw new CallciumError("RULE_OVERFLOW", "Rule extends beyond group boundary", ruleOffset);
      }

      const scopeOffset = ruleOffset + PF.RULE_SCOPE_OFFSET;
      const scopeValue = data[scopeOffset]!;
      if (scopeValue !== Scope.CONTEXT && scopeValue !== Scope.CALLDATA) {
        throw new CallciumError("INVALID_SCOPE", `Unknown scope value ${scopeValue}`, ruleOffset);
      }

      const depthOffset = ruleOffset + PF.RULE_DEPTH_OFFSET;
      const depthValue = data[depthOffset]!;
      if (depthValue === 0) {
        throw new CallciumError("EMPTY_PATH", "Rule path must have at least one step", ruleOffset);
      }
      if (depthValue > Limits.MAX_PATH_DEPTH) {
        throw new CallciumError(
          "MALFORMED_HEADER",
          `Path depth ${depthValue} exceeds maximum ${Limits.MAX_PATH_DEPTH}`,
          ruleOffset,
        );
      }
      if (scopeValue === Scope.CONTEXT && depthValue !== 1) {
        throw new CallciumError(
          "INVALID_CONTEXT_PATH",
          "Context-scope rules must have exactly one path step",
          ruleOffset,
        );
      }

      const pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
      const pathLength = depthValue * PF.PATH_STEP_SIZE;
      const pathHex = toHex(data, pathStart, pathStart + pathLength);

      const opCodeOffset = pathStart + pathLength;
      const opCodeValue = data[opCodeOffset]!;

      const dataLengthOffset = opCodeOffset + PF.RULE_OPCODE_SIZE;
      const dataLengthValue = readU16(data, dataLengthOffset);

      const dataStart = dataLengthOffset + PF.RULE_DATALENGTH_SIZE;

      // Validate ruleSize matches the computed layout.
      const expectedRuleSize = PF.RULE_FIXED_OVERHEAD + pathLength + dataLengthValue;
      if (ruleSizeValue !== expectedRuleSize) {
        throw new CallciumError(
          "RULE_SIZE_MISMATCH",
          `Declared rule size ${ruleSizeValue} does not match computed size ${expectedRuleSize}`,
          ruleOffset,
        );
      }

      // Validate operator and data length.
      const opBase = opCodeValue & ~Op.NOT;
      if (opBase === 0 || !isValidOperatorData(opBase, dataLengthValue)) {
        throw new CallciumError("INVALID_OPERATOR", "Unrecognized or malformed operator", ruleOffset);
      }

      rules.push({
        scope: field(scopeValue, scopeOffset, scopeOffset + 1),
        path: field(pathHex, pathStart, pathStart + pathLength),
        opCode: field(opCodeValue, opCodeOffset, opCodeOffset + PF.RULE_OPCODE_SIZE),
        data: field(toHex(data, dataStart, dataStart + dataLengthValue), dataStart, dataStart + dataLengthValue),
        span: { start: ruleOffset, end: ruleOffset + ruleSizeValue },
      });

      ruleOffset += ruleSizeValue;
    }

    if (ruleOffset !== groupEnd) {
      throw new CallciumError("GROUP_SIZE_MISMATCH", "Rules do not exactly fill the declared group size", offset);
    }

    groups.push({
      rules,
      span: { start: offset, end: groupEnd },
    });
    offset = groupEnd;
  }

  // Reject trailing bytes after the last group.
  if (offset !== data.length) {
    throw new CallciumError("TRAILING_BYTES", "Trailing bytes after last group", offset);
  }

  const policy: DecodedPolicy = {
    header: field(headerByte, 0, PF.HEADER_SIZE),
    selector: field(selectorHex, selectorStart, selectorEnd),
    descriptor: {
      raw: descriptorRaw,
      params,
      span: { start: descStart, end: descEnd },
    },
    groups,
    span: { start: 0, end: data.length },
    version,
    isSelectorless,
  };

  return { policy, tree };
}

/**
 * Decode a binary policy blob into its public representation.
 * @param blob - Binary policy as 0x-prefixed hex string.
 * @returns The decoded policy with groups, rules, and byte spans.
 * @throws {CallciumError} If the blob is structurally malformed.
 */
export function decodePolicy(blob: Hex): DecodedPolicy {
  return _decodePolicyFromBytes(hexToBytes(blob)).policy;
}

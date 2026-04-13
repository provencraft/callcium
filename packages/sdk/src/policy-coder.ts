import { keccak_256 } from "@noble/hashes/sha3";

import { bytesToHex, hexToBytes, toHex, readU16, readU24, readU32, writeBE16 } from "./bytes";
import {
  DescriptorFormat as DF,
  PolicyFormat as PF,
  Scope,
  Limits,
  Op,
  isValidOperatorData,
  classifyTypeCode,
} from "./constants";
import { CallciumError } from "./errors";

import type {
  Constraint,
  DescNode,
  Field,
  Hex,
  DecodedGroup,
  DecodedParam,
  DecodedPolicy,
  DecodedRule,
  PolicyData,
} from "./types";

///////////////////////////////////////////////////////////////////////////
// Internal types
///////////////////////////////////////////////////////////////////////////

type DecodedDescriptor = {
  version: number;
  params: DecodedParam[];
};

///////////////////////////////////////////////////////////////////////////
// Recursive node parser
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
// Path helper
///////////////////////////////////////////////////////////////////////////

/** Convert a zero-based param index to a BE16 hex path step. */
function indexToPath(index: number): Hex {
  return `0x${index.toString(16).padStart(4, "0")}`;
}

/**
 * Parse a BE16-encoded hex path into an array of step values.
 * @param path - 0x-prefixed hex string containing BE16-encoded path steps.
 * @returns Array of numeric step values.
 */
export function parsePathSteps(path: Hex): number[] {
  const body = path.slice(2);
  const steps: number[] = [];
  for (let i = 0; i < body.length; i += 4) {
    steps.push(parseInt(body.slice(i, i + 4), 16));
  }
  return steps;
}

///////////////////////////////////////////////////////////////////////////
// Descriptor decoder
///////////////////////////////////////////////////////////////////////////

/** Decode a binary descriptor blob, returning both the public structure and internal AST. */
export function decodeDescriptorFromBytes(data: Uint8Array): {
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

///////////////////////////////////////////////////////////////////////////
// Policy field helper
///////////////////////////////////////////////////////////////////////////

/** Wrap a value with its byte span for positional tracking. */
function field<T>(value: T, start: number, end: number): Field<T> {
  return { value, span: { start, end } };
}

///////////////////////////////////////////////////////////////////////////
// Policy Decoder
///////////////////////////////////////////////////////////////////////////

/** Decode a policy blob, returning the structural representation and descriptor AST. */
export function decodePolicy(blob: Hex): {
  policy: DecodedPolicy;
  tree: DescNode[];
} {
  const data = hexToBytes(blob);
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
  const { descriptor: desc, tree } = decodeDescriptorFromBytes(descSlice);
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
        ruleSize: field(ruleSizeValue, ruleOffset, ruleOffset + PF.RULE_SIZE_SIZE),
        scope: field(scopeValue, scopeOffset, scopeOffset + 1),
        pathDepth: field(depthValue, depthOffset, depthOffset + 1),
        path: field(pathHex, pathStart, pathStart + pathLength),
        opCode: field(opCodeValue, opCodeOffset, opCodeOffset + PF.RULE_OPCODE_SIZE),
        dataLength: field(dataLengthValue, dataLengthOffset, dataLengthOffset + PF.RULE_DATALENGTH_SIZE),
        data: field(toHex(data, dataStart, dataStart + dataLengthValue), dataStart, dataStart + dataLengthValue),
        span: { start: ruleOffset, end: ruleOffset + ruleSizeValue },
      });

      ruleOffset += ruleSizeValue;
    }

    if (ruleOffset !== groupEnd) {
      throw new CallciumError("GROUP_SIZE_MISMATCH", "Rules do not exactly fill the declared group size", offset);
    }

    groups.push({
      ruleCount: field(ruleCountValue, ruleCountStart, ruleCountStart + PF.GROUP_RULECOUNT_SIZE),
      groupSize: field(groupSizeValue, groupSizeStart, groupSizeStart + PF.GROUP_SIZE_SIZE),
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
    descLength: field(descLengthValue, descLengthStart, descLengthStart + PF.DESC_LENGTH_SIZE),
    descriptor: {
      raw: descriptorRaw,
      params,
      span: { start: descStart, end: descEnd },
    },
    groupCount: field(groupCountValue, groupCountStart, groupCountEnd),
    groups,
    span: { start: 0, end: data.length },
    version,
    isSelectorless,
  };

  return { policy, tree };
}

///////////////////////////////////////////////////////////////////////////
// Encoder Internals
///////////////////////////////////////////////////////////////////////////

type Rule = { scope: number; path: Uint8Array; operator: Uint8Array };

/** Flatten a Constraint into one Rule per operator. */
function flattenConstraint(constraint: Constraint): Rule[] {
  const path = hexToBytes(constraint.path);
  return constraint.operators.map((op) => ({
    scope: constraint.scope,
    path,
    operator: hexToBytes(op),
  }));
}

/** Compare two byte arrays lexicographically. */
function compareBytes(a: Uint8Array, b: Uint8Array): number {
  const len = Math.min(a.length, b.length);
  for (let i = 0; i < len; i++) {
    if (a[i]! !== b[i]!) return a[i]! - b[i]!;
  }
  return a.length - b.length;
}

/** Sort rules by (scope, pathDepth, pathBytes, operatorBytes). */
function sortRules(rules: Rule[]): void {
  rules.sort((a, b) => {
    if (a.scope !== b.scope) return a.scope - b.scope;
    const depthA = a.path.length / 2;
    const depthB = b.path.length / 2;
    if (depthA !== depthB) return depthA - depthB;
    const pathCmp = compareBytes(a.path, b.path);
    if (pathCmp !== 0) return pathCmp;
    return compareBytes(a.operator, b.operator);
  });
}

/** Serialize a single rule to its wire format bytes. */
function encodeRule(rule: Rule): Uint8Array {
  if (rule.path.length === 0) {
    throw new CallciumError("EMPTY_PATH", "Rule path must have at least one step.");
  }
  if ((rule.path.length & 1) !== 0) {
    throw new CallciumError("INVALID_PATH", "Path byte length must be even.");
  }
  if (rule.operator.length < 1) {
    throw new CallciumError("INVALID_OPERATOR", "Operator must have at least one byte (opcode).");
  }
  const depth = rule.path.length / 2;
  if (depth > Limits.MAX_PATH_DEPTH) {
    throw new CallciumError("INVALID_PATH", `Path depth ${depth} exceeds maximum ${Limits.MAX_PATH_DEPTH}.`);
  }
  if (rule.scope === Scope.CONTEXT && depth !== 1) {
    throw new CallciumError("INVALID_CONTEXT_PATH", "Context-scope rules must have exactly one path step.");
  }
  const opCode = rule.operator[0]!;
  const data = rule.operator.subarray(1);
  const ruleSize = PF.RULE_FIXED_OVERHEAD + rule.path.length + data.length;
  if (ruleSize > 0xffff) {
    throw new CallciumError("RULE_SIZE_OVERFLOW", `Rule size ${ruleSize} exceeds maximum 65535`);
  }

  const buf = new Uint8Array(ruleSize);
  writeBE16(buf, 0, ruleSize);
  buf[2] = rule.scope;
  buf[3] = depth;
  buf.set(rule.path, 4);
  const opOffset = 4 + rule.path.length;
  buf[opOffset] = opCode;
  writeBE16(buf, opOffset + 1, data.length);
  buf.set(data, opOffset + 3);

  return buf;
}

/** Serialize all rules in a group to a single byte array. */
function encodeGroupRules(rules: Rule[]): Uint8Array {
  const parts = rules.map(encodeRule);
  const totalSize = parts.reduce((sum, p) => sum + p.length, 0);
  const buf = new Uint8Array(totalSize);
  let offset = 0;
  for (const part of parts) {
    buf.set(part, offset);
    offset += part.length;
  }
  return buf;
}

///////////////////////////////////////////////////////////////////////////
// PolicyCoder
///////////////////////////////////////////////////////////////////////////

/** Build a single operator hex string from a decoded rule's opCode and data. */
function buildOperatorHex(rule: DecodedRule): Hex {
  const opCodeHex = rule.opCode.value.toString(16).padStart(2, "0");
  const dataBody = rule.data.value.slice(2);
  return `0x${opCodeHex}${dataBody}`;
}

/**
 * Encode a PolicyData structure into the canonical binary format.
 * @param data - The policy data to encode.
 * @returns The encoded policy as a 0x-prefixed hex string.
 */
function encode(data: PolicyData): Hex {
  // Flatten constraints into rules and sort within each group.
  const sortedGroups: Rule[][] = data.groups.map((group) => {
    const rules = group.flatMap(flattenConstraint);
    sortRules(rules);
    return rules;
  });

  if (sortedGroups.length === 0) {
    throw new CallciumError("EMPTY_POLICY", "Policy must contain at least one group");
  }
  if (sortedGroups.length > 0xff) {
    throw new CallciumError("GROUP_COUNT_OVERFLOW", `Group count ${sortedGroups.length} exceeds maximum 255`);
  }

  // Sort groups by keccak256 hash of their serialized rule bytes.
  const groupsWithHash: { wireBytes: Uint8Array; hash: Uint8Array; ruleCount: number }[] = sortedGroups.map(
    (rules, groupIndex) => {
      if (rules.length === 0) {
        throw new CallciumError("EMPTY_GROUP", `Group ${groupIndex} is empty`);
      }
      if (rules.length > 0xffff) {
        throw new CallciumError(
          "RULE_COUNT_OVERFLOW",
          `Group ${groupIndex} rule count ${rules.length} exceeds maximum 65535`,
        );
      }
      const wireBytes = encodeGroupRules(rules);
      return { wireBytes, hash: keccak_256(wireBytes), ruleCount: rules.length };
    },
  );
  groupsWithHash.sort((a, b) => compareBytes(a.hash, b.hash));

  // Build the binary output.
  const descBytes = hexToBytes(data.descriptor);
  if (descBytes.length > 0xffff) {
    throw new CallciumError("DESC_LENGTH_OVERFLOW", `Descriptor length ${descBytes.length} exceeds maximum 65535`);
  }
  const selectorBytes = data.isSelectorless ? new Uint8Array(4) : hexToBytes(data.selector);

  const headerByte = PF.VERSION | (data.isSelectorless ? PF.FLAG_NO_SELECTOR : 0);

  // Pre-compute total size.
  let totalSize = PF.HEADER_SIZE + PF.SELECTOR_SIZE + PF.DESC_LENGTH_SIZE + descBytes.length + PF.GROUP_COUNT_SIZE;
  for (const g of groupsWithHash) {
    totalSize += PF.GROUP_HEADER_SIZE + g.wireBytes.length;
  }

  const out = new Uint8Array(totalSize);
  let offset = 0;

  // Header.
  out[offset++] = headerByte;

  // Selector.
  out.set(selectorBytes, offset);
  offset += PF.SELECTOR_SIZE;

  // Descriptor length (BE16).
  writeBE16(out, offset, descBytes.length);
  offset += PF.DESC_LENGTH_SIZE;

  // Descriptor.
  out.set(descBytes, offset);
  offset += descBytes.length;

  // Group count.
  out[offset++] = groupsWithHash.length;

  // Groups.
  for (const g of groupsWithHash) {
    // Rule count (BE16).
    writeBE16(out, offset, g.ruleCount);
    offset += PF.GROUP_RULECOUNT_SIZE;

    // Group size (BE32).
    out[offset++] = (g.wireBytes.length >>> 24) & 0xff;
    out[offset++] = (g.wireBytes.length >>> 16) & 0xff;
    out[offset++] = (g.wireBytes.length >>> 8) & 0xff;
    out[offset++] = g.wireBytes.length & 0xff;

    // Rule bytes.
    out.set(g.wireBytes, offset);
    offset += g.wireBytes.length;
  }

  return bytesToHex(out);
}

/**
 * Decode a binary policy blob into a PolicyData structure.
 * @param blob - Binary policy as 0x-prefixed hex string.
 * @returns The decoded policy data with constraints grouped by scope and path.
 * @throws {CallciumError} If the blob is structurally malformed.
 */
function decode(blob: Hex): PolicyData {
  const { policy } = decodePolicy(blob);

  const groups: Constraint[][] = policy.groups.map((group) => {
    const constraintMap = new Map<string, Constraint>();
    const constraintOrder: string[] = [];

    for (const rule of group.rules) {
      const key = `${rule.scope.value}:${rule.path.value}`;
      const opHex = buildOperatorHex(rule);

      const existing = constraintMap.get(key);
      if (existing !== undefined) {
        existing.operators.push(opHex);
      } else {
        const constraint: Constraint = {
          scope: rule.scope.value,
          path: rule.path.value,
          operators: [opHex],
          span: rule.span,
        };
        constraintMap.set(key, constraint);
        constraintOrder.push(key);
      }
    }

    return constraintOrder.map((k) => constraintMap.get(k)!);
  });

  return {
    isSelectorless: policy.isSelectorless,
    selector: policy.selector.value,
    descriptor: policy.descriptor.raw,
    groups,
    span: policy.span,
  };
}

/**
 * Inspect a binary policy blob, returning the structural representation with full byte-level spans.
 * @param blob - Binary policy as 0x-prefixed hex string.
 * @returns The inspected policy with per-field spans for every structural element.
 * @throws {CallciumError} If the blob is structurally malformed.
 */
function inspect(blob: Hex): DecodedPolicy {
  return decodePolicy(blob).policy;
}

/** Encode, decode, and inspect policies in the canonical binary format. */
export const PolicyCoder = { encode, decode, inspect };

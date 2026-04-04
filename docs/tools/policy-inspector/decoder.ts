import { DecodeError, DescriptorFormat as DF, lookupTypeCode, OpCodes, PolicyFormat as PF, Scopes } from "./constants";
import type { TypeClass } from "./constants";

export { DecodeError };

export type Hex = `0x${string}`;

export { hexToBytes, readU24 };

export type Span = { start: number; end: number };

export type Field<T> = { value: T; span: Span };

function field<T>(value: T, start: number, end: number): Field<T> {
  return { value, span: { start, end } };
}

export type DecodedParam = {
  index: number;
  typeCode: number;
  isDynamic: boolean;
  staticSize: number;
  path: Hex;
  span: Span;
};

export type DecodedRule = {
  ruleSize: Field<number>;
  scope: Field<number>;
  pathDepth: Field<number>;
  path: Field<Hex>;
  opCode: Field<number>;
  dataLength: Field<number>;
  data: Field<Hex>;
  span: Span;
};

export type DecodedGroup = {
  ruleCount: Field<number>;
  groupSize: Field<number>;
  rules: DecodedRule[];
  span: Span;
};

export type DecodedPolicy = {
  header: Field<number>;
  selector: Field<Hex>;
  descLength: Field<number>;
  descriptor: { raw: Hex; params: DecodedParam[]; span: Span };
  groupCount: Field<number>;
  groups: DecodedGroup[];
  span: Span;
  version: number;
  isSelectorless: boolean;
};

// Convert hex string to Uint8Array.
function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) throw new DecodeError("InvalidHex", "Odd-length hex string");
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
  }
  return bytes;
}

// Read big-endian uint16 at offset.
function readU16(data: Uint8Array, offset: number): number {
  return (data[offset] << 8) | data[offset + 1];
}

// Read big-endian uint32 at offset.
function readU32(data: Uint8Array, offset: number): number {
  return ((data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]) >>> 0;
}

// Read big-endian uint24 at offset.
function readU24(data: Uint8Array, offset: number): number {
  return (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];
}

// Convert bytes to 0x-prefixed hex.
function toHex(data: Uint8Array, start: number, end: number): Hex {
  let hex = "0x";
  for (let i = start; i < end; i++) {
    hex += data[i].toString(16).padStart(2, "0");
  }
  return hex as Hex;
}

// Format a param index as a BE16 path hex.
function indexToPath(index: number): Hex {
  return `0x${index.toString(16).padStart(4, "0")}`;
}

// Remap domain objects to plain numeric constants for internal use.
const Op = Object.fromEntries(Object.entries(OpCodes).map(([k, v]) => [k, v.code])) as {
  [K in keyof typeof OpCodes]: (typeof OpCodes)[K]["code"];
};

const Scope = Object.fromEntries(Object.entries(Scopes).map(([k, v]) => [k, v.code])) as {
  [K in keyof typeof Scopes]: (typeof Scopes)[K]["code"];
};

// Mirrors OpRule.isValidPayloadSize from OpRule.sol.
const SINGLE_OPERAND = new Set<number>([
  Op.EQ,
  Op.GT,
  Op.LT,
  Op.GTE,
  Op.LTE,
  Op.BITMASK_ALL,
  Op.BITMASK_ANY,
  Op.BITMASK_NONE,
  Op.LENGTH_EQ,
  Op.LENGTH_GT,
  Op.LENGTH_LT,
  Op.LENGTH_GTE,
  Op.LENGTH_LTE,
]);
const RANGE_OPS = new Set<number>([Op.BETWEEN, Op.LENGTH_BETWEEN]);

function isValidPayloadSize(opBase: number, dataLength: number): boolean {
  if (SINGLE_OPERAND.has(opBase)) return dataLength === 32;
  if (RANGE_OPS.has(opBase)) return dataLength === 64;
  if (opBase === Op.IN) return dataLength > 0 && dataLength % 32 === 0;
  return false;
}

type NodeInfo = {
  code: number;
  typeClass: TypeClass;
  isDynamic: boolean;
  staticSize: number;
  next: number;
};

// Inspect and validate a node recursively.
// Returns type info and next offset. Throws on structural errors.
function readNode(data: Uint8Array, offset: number): NodeInfo {
  if (offset >= data.length) throw new DecodeError("UnexpectedEnd", "Unexpected end of descriptor", offset);
  const code = data[offset];

  // lookupTypeCode throws DecodeError("UnknownTypeCode") for invalid codes.
  const info = lookupTypeCode(code);
  const metaOffset = offset + DF.TYPECODE_SIZE;

  if (info.typeClass === "elementary") {
    return {
      code,
      typeClass: "elementary",
      isDynamic: info.isDynamic,
      staticSize: info.isDynamic ? 0 : 32,
      next: metaOffset,
    };
  }

  // Composite type — read and validate metadata.
  const metaEnd = metaOffset + DF.COMPOSITE_META_SIZE;
  if (metaEnd > data.length) {
    throw new DecodeError("UnexpectedEnd", "Incomplete composite metadata", offset);
  }

  const meta = readU24(data, metaOffset);
  const staticWords = meta >> DF.META_STATIC_WORDS_SHIFT;
  const nodeLength = meta & DF.META_NODE_LENGTH_MASK;

  const minHeader = info.typeClass === "tuple" ? DF.TUPLE_HEADER_SIZE : DF.ARRAY_HEADER_SIZE;
  if (nodeLength < minHeader)
    throw new DecodeError("NodeLengthTooSmall", "Composite node length is smaller than its header", offset);
  if (offset + nodeLength > data.length)
    throw new DecodeError("NodeOverflow", "Composite node extends beyond descriptor", offset);

  const isDynamic = staticWords === 0;
  const staticSize = isDynamic ? 0 : staticWords * 32;
  const next = offset + nodeLength;

  // Validate children.
  if (info.typeClass === "tuple") {
    if (offset + DF.TUPLE_HEADER_SIZE > data.length)
      throw new DecodeError("UnexpectedEnd", "Incomplete tuple header", offset);
    const fieldCount = readU16(data, metaEnd);
    if (fieldCount === 0) throw new DecodeError("InvalidTupleFieldCount", "Tuple must have at least one field", offset);
    if (fieldCount > DF.MAX_TUPLE_FIELDS)
      throw new DecodeError(
        "TupleFieldCountTooLarge",
        `Tuple field count ${fieldCount} exceeds maximum ${DF.MAX_TUPLE_FIELDS}`,
        offset,
      );
    let child = offset + DF.TUPLE_HEADER_SIZE;
    for (let i = 0; i < fieldCount; i++) {
      child = readNode(data, child).next;
    }
  } else if (info.typeClass === "staticArray") {
    const elemEnd = readNode(data, offset + DF.ARRAY_HEADER_SIZE).next;
    if (elemEnd + DF.ARRAY_LENGTH_SIZE > data.length)
      throw new DecodeError("UnexpectedEnd", "Missing static array length suffix", offset);
    const length = readU16(data, elemEnd);
    if (length === 0)
      throw new DecodeError("InvalidArrayLength", "Static array length must be greater than zero", offset);
    if (length > DF.MAX_STATIC_ARRAY_LENGTH)
      throw new DecodeError(
        "ArrayLengthTooLarge",
        `Static array length ${length} exceeds maximum ${DF.MAX_STATIC_ARRAY_LENGTH}`,
        offset,
      );
  } else if (info.typeClass === "dynamicArray") {
    readNode(data, offset + DF.ARRAY_HEADER_SIZE);
  }

  return { code, typeClass: info.typeClass, isDynamic, staticSize, next };
}

type Descriptor = {
  version: number;
  params: DecodedParam[];
};

export function decodeDescriptor(blob: string): Descriptor {
  const data = hexToBytes(blob);

  if (data.length < 1) throw new DecodeError("MalformedHeader", "Descriptor is empty");
  const version = data[0];
  if (version !== DF.VERSION)
    throw new DecodeError("UnsupportedVersion", `Version ${version} is not supported (expected ${DF.VERSION})`);

  if (data.length < DF.HEADER_SIZE) throw new DecodeError("MalformedHeader", "Descriptor too short for header");
  const declaredCount = data[1];

  const params: DecodedParam[] = [];
  let cursor: number = DF.HEADER_SIZE;

  while (cursor < data.length) {
    if (params.length >= DF.MAX_PARAMS)
      throw new DecodeError("TooManyParams", `Descriptor exceeds the maximum of ${DF.MAX_PARAMS} top-level params`);
    const { code, isDynamic, staticSize, next } = readNode(data, cursor);
    params.push({
      index: params.length,
      typeCode: code,
      isDynamic,
      staticSize,
      path: indexToPath(params.length),
      span: { start: cursor, end: next },
    });
    cursor = next;
  }

  if (params.length !== declaredCount) {
    throw new DecodeError(
      "ParamCountMismatch",
      `Header declares ${declaredCount} params but ${params.length} were parsed`,
    );
  }

  return { version, params };
}

export function decodePolicy(blob: string): DecodedPolicy {
  const data = hexToBytes(blob);

  // Validate header: need at least 7 bytes (header + selector + descLength).
  if (data.length < PF.DESC_OFFSET)
    throw new DecodeError("MalformedHeader", "Policy blob is too short to contain a valid header");

  const headerByte = data[0];
  const version = headerByte & PF.VERSION_MASK;
  if (version !== PF.VERSION)
    throw new DecodeError("UnsupportedVersion", `Version ${version} is not supported (expected ${PF.VERSION})`);
  if ((headerByte & PF.RESERVED_MASK) !== 0)
    throw new DecodeError("MalformedHeader", "Reserved header bits must be zero");

  const isSelectorless = (headerByte & PF.FLAG_NO_SELECTOR) !== 0;

  // Read selector (bytes 1-4).
  const selectorValue = toHex(data, PF.SELECTOR_OFFSET, PF.SELECTOR_OFFSET + PF.SELECTOR_SIZE);

  if (isSelectorless && selectorValue !== "0x00000000") {
    throw new DecodeError("MalformedHeader", "Selectorless policy must have a zeroed selector slot");
  }

  // Read descriptor length (bytes 5-6, BE16).
  const descLengthValue = readU16(data, PF.DESC_LENGTH_OFFSET);
  if (descLengthValue < 2) throw new DecodeError("MalformedHeader", "Descriptor length must be at least 2");

  const descEnd = PF.DESC_OFFSET + descLengthValue;
  const groupCountOffset = descEnd;

  if (data.length < groupCountOffset + PF.GROUP_COUNT_SIZE) {
    throw new DecodeError("MalformedHeader", "Policy blob is too short for descriptor and group count");
  }

  // Extract and decode descriptor, offsetting param spans to policy-level.
  const descriptorHex = toHex(data, PF.DESC_OFFSET, descEnd);
  const desc = decodeDescriptor(descriptorHex);
  const params: DecodedParam[] = desc.params.map((p) => ({
    ...p,
    span: {
      start: PF.DESC_OFFSET + p.span.start,
      end: PF.DESC_OFFSET + p.span.end,
    },
  }));

  const groupCountValue = data[groupCountOffset];
  if (groupCountValue === 0) throw new DecodeError("EmptyPolicy", "Policy must contain at least one group");

  let offset = groupCountOffset + PF.GROUP_COUNT_SIZE;
  const groups: DecodedGroup[] = [];

  for (let groupIndex = 0; groupIndex < groupCountValue; groupIndex++) {
    if (offset + PF.GROUP_HEADER_SIZE > data.length)
      throw new DecodeError("UnexpectedEnd", "Unexpected end while reading group header", offset);

    const ruleCountValue = readU16(data, offset);
    const groupSizeValue = readU32(data, offset + PF.GROUP_RULECOUNT_SIZE);

    if (ruleCountValue === 0) throw new DecodeError("EmptyGroup", "Group must contain at least one rule", offset);
    if (groupSizeValue < ruleCountValue * PF.RULE_MIN_SIZE)
      throw new DecodeError("GroupTooSmall", "Declared group size is too small for its rule count", offset);

    const groupEnd = offset + PF.GROUP_HEADER_SIZE + groupSizeValue;
    if (groupEnd > data.length) throw new DecodeError("GroupOverflow", "Group extends beyond policy blob", offset);

    // Read all rules in this group.
    const rules: DecodedRule[] = [];
    let ruleOffset = offset + PF.GROUP_HEADER_SIZE;

    for (let ruleIndex = 0; ruleIndex < ruleCountValue; ruleIndex++) {
      if (ruleOffset + PF.RULE_SIZE_SIZE > data.length)
        throw new DecodeError("UnexpectedEnd", "Unexpected end while reading rule size", ruleOffset);

      const ruleSizeValue = readU16(data, ruleOffset);
      if (ruleSizeValue < PF.RULE_MIN_SIZE)
        throw new DecodeError(
          "RuleTooSmall",
          `Rule size ${ruleSizeValue} is below minimum ${PF.RULE_MIN_SIZE}`,
          ruleOffset,
        );
      if (ruleOffset + ruleSizeValue > groupEnd)
        throw new DecodeError("RuleOverflow", "Rule extends beyond group boundary", ruleOffset);

      const scopeValue = data[ruleOffset + PF.RULE_SCOPE_OFFSET];
      if (scopeValue !== Scope.CONTEXT && scopeValue !== Scope.CALLDATA) {
        throw new DecodeError("InvalidScope", `Unknown scope value ${scopeValue}`, ruleOffset);
      }

      const depthValue = data[ruleOffset + PF.RULE_DEPTH_OFFSET];
      if (depthValue === 0) throw new DecodeError("EmptyPath", "Rule path must have at least one step", ruleOffset);
      if (scopeValue === Scope.CONTEXT && depthValue !== 1) {
        throw new DecodeError("InvalidContextPath", "Context-scope rules must have exactly one path step", ruleOffset);
      }

      const pathLength = depthValue * PF.PATH_STEP_SIZE;
      const pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
      const pathValue = toHex(data, pathStart, pathStart + pathLength);

      const opCodeStart = pathStart + pathLength;
      const opCodeValue = data[opCodeStart];
      const dataLengthStart = opCodeStart + PF.RULE_OPCODE_SIZE;
      const dataLengthValue = readU16(data, dataLengthStart);
      const dataStart = dataLengthStart + PF.RULE_DATALENGTH_SIZE;

      // Validate ruleSize matches field layout.
      const expectedSize = PF.RULE_FIXED_OVERHEAD + pathLength + dataLengthValue;
      if (ruleSizeValue !== expectedSize)
        throw new DecodeError(
          "RuleSizeMismatch",
          `Declared rule size ${ruleSizeValue} does not match computed size ${expectedSize}`,
          ruleOffset,
        );

      // Validate opCode is known and payload size is correct.
      const opBase = opCodeValue & ~Op.NOT;
      if (opBase === 0 || !isValidPayloadSize(opBase, dataLengthValue)) {
        throw new DecodeError("UnknownOperator", `Unrecognized or malformed operator at rule`, ruleOffset);
      }

      rules.push({
        ruleSize: field(ruleSizeValue, ruleOffset, ruleOffset + PF.RULE_SIZE_SIZE),
        scope: field(scopeValue, ruleOffset + PF.RULE_SCOPE_OFFSET, ruleOffset + PF.RULE_SCOPE_OFFSET + 1),
        pathDepth: field(depthValue, ruleOffset + PF.RULE_DEPTH_OFFSET, ruleOffset + PF.RULE_DEPTH_OFFSET + 1),
        path: field(pathValue, pathStart, pathStart + pathLength),
        opCode: field(opCodeValue, opCodeStart, opCodeStart + PF.RULE_OPCODE_SIZE),
        dataLength: field(dataLengthValue, dataLengthStart, dataLengthStart + PF.RULE_DATALENGTH_SIZE),
        data: field(toHex(data, dataStart, dataStart + dataLengthValue), dataStart, dataStart + dataLengthValue),
        span: { start: ruleOffset, end: ruleOffset + ruleSizeValue },
      });
      ruleOffset += ruleSizeValue;
    }

    if (ruleOffset !== groupEnd)
      throw new DecodeError("GroupSizeMismatch", "Rules do not exactly fill the declared group size", offset);

    groups.push({
      ruleCount: field(ruleCountValue, offset, offset + PF.GROUP_RULECOUNT_SIZE),
      groupSize: field(groupSizeValue, offset + PF.GROUP_RULECOUNT_SIZE, offset + PF.GROUP_HEADER_SIZE),
      rules,
      span: { start: offset, end: groupEnd },
    });
    offset = groupEnd;
  }

  // Ensure no trailing bytes.
  if (offset !== data.length) throw new DecodeError("UnexpectedEnd", "Trailing bytes after last group", offset);

  return {
    header: field(headerByte, 0, PF.HEADER_SIZE),
    selector: field(selectorValue, PF.SELECTOR_OFFSET, PF.SELECTOR_OFFSET + PF.SELECTOR_SIZE),
    descLength: field(descLengthValue, PF.DESC_LENGTH_OFFSET, PF.DESC_LENGTH_OFFSET + PF.DESC_LENGTH_SIZE),
    descriptor: {
      raw: descriptorHex,
      params,
      span: { start: PF.DESC_OFFSET, end: descEnd },
    },
    groupCount: field(groupCountValue, groupCountOffset, groupCountOffset + PF.GROUP_COUNT_SIZE),
    groups,
    span: { start: 0, end: data.length },
    version,
    isSelectorless,
  };
}

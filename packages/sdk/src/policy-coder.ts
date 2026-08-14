import { keccak_256 } from "@noble/hashes/sha3";

import { bytesToHex, hexToBytes, toHex, readU16, readU32, writeBE16, writeBE32 } from "./bytes";
import {
  DescriptorFormat as DF,
  PolicyFormat as PF,
  Scope,
  Limits,
  Op,
  TypeCode,
  isValidOperatorData,
  isAddressableTarget,
  MAX_CONTEXT_PROPERTY_ID,
} from "./constants";
import { Descriptor } from "./descriptor";
import { decodeDescriptor } from "./descriptor-coder";
import { CallciumError } from "./errors";
import { isLengthOp, isLengthValidType } from "./operators";

import type {
  Constraint,
  Field,
  Hex,
  DecodedGroup,
  DecodedParam,
  DecodedPolicy,
  DecodedRule,
  PolicyData,
} from "./types";

///////////////////////////////////////////////////////////////////////////
// Path helper
///////////////////////////////////////////////////////////////////////////

/**
 * Parse a BE16-encoded hex path into an array of step values.
 * @param path - 0x-prefixed hex string containing BE16-encoded path steps.
 * @returns Array of numeric step values.
 */
export function parsePathSteps(path: Hex): number[] {
  const bytes = hexToBytes(path);
  if (bytes.length % PF.PATH_STEP_SIZE !== 0) {
    throw new CallciumError("MALFORMED_PATH", `Path byte length ${bytes.length} is not a whole number of steps`);
  }
  const steps: number[] = [];
  for (let offset = 0; offset < bytes.length; offset += PF.PATH_STEP_SIZE) {
    steps.push(readU16(bytes, offset));
  }
  return steps;
}

///////////////////////////////////////////////////////////////////////////
// Policy field helper
///////////////////////////////////////////////////////////////////////////

/** Wrap a value with its byte span for positional tracking. */
function field<T>(value: T, start: number, end: number): Field<T> {
  return { value, span: { start, end } };
}

///////////////////////////////////////////////////////////////////////////
// Hint block
///////////////////////////////////////////////////////////////////////////

/** Resolve the hint block size at `hintStart` from its header and suffix header bytes. */
function resolveHintSize(data: Uint8Array, hintStart: number, ruleEnd: number, ruleOffset: number): number {
  const overrun = (): never => {
    throw new CallciumError("RULE_FIELD_OUT_OF_BOUNDS", "Rule is too small to hold a hint block", ruleOffset);
  };

  if (hintStart + PF.HINT_HEADER_SIZE > ruleEnd) overrun();
  const header = data[hintStart]!;
  const hopsEnd = hintStart + PF.HINT_HEADER_SIZE + (header & PF.HINT_HOP_COUNT_MASK) * PF.HINT_HOP_SIZE;
  let hintSize = hopsEnd - hintStart + PF.HINT_TARGET_SIZE;

  // A quantifier frame sits between the main chain and the target, sized by its own header byte.
  if (header >> PF.HINT_KIND_SHIFT !== PF.HINT_KIND_NONE) {
    const suffixHeaderOffset = hopsEnd + PF.HINT_FRAME_PREFIX_SIZE;
    if (suffixHeaderOffset >= ruleEnd) overrun();
    const suffixHeader = data[suffixHeaderOffset]!;
    hintSize +=
      PF.HINT_FRAME_PREFIX_SIZE + PF.HINT_HEADER_SIZE + (suffixHeader & PF.HINT_HOP_COUNT_MASK) * PF.HINT_HOP_SIZE;
  }

  if (hintStart + hintSize > ruleEnd) overrun();
  return hintSize;
}

/** Throw a MALFORMED_HINT error with the given detail. */
function malformedHint(detail: string, ruleOffset: number): never {
  throw new CallciumError("MALFORMED_HINT", detail, ruleOffset);
}

/** Require every hop entry in `[start, end)` to carry no reserved or unused state. */
function validateHops(data: Uint8Array, start: number, end: number, ruleOffset: number): void {
  for (let offset = start; offset < end; offset += PF.HINT_HOP_SIZE) {
    const index = readU16(data, offset + PF.HINT_HOP_INDEX_OFFSET);
    if (index === PF.HINT_INDEX_RESERVED) malformedHint("Hop index is a reserved value", ruleOffset);

    const meta = readU16(data, offset + PF.HINT_HOP_META_OFFSET);
    // A plain hop carries no element meta; an element hop addresses no offset of its own.
    if (index === PF.HINT_NO_INDEX) {
      if (meta !== 0) malformedHint("Plain hop carries a meta word", ruleOffset);
    } else {
      if (readU32(data, offset) !== 0) malformedHint("Element hop carries a delta", ruleOffset);
      if ((meta & PF.HINT_META_RESERVED_MASK) !== 0) malformedHint("Hop meta carries reserved bits", ruleOffset);
    }
  }
}

/** Require the hint block at `hintStart` to carry no reserved or unused state. */
function validateHint(data: Uint8Array, hintStart: number, hintSize: number, ruleOffset: number): void {
  const header = data[hintStart]!;
  const kind = header >> PF.HINT_KIND_SHIFT;
  if (kind > PF.HINT_KIND_MAX) malformedHint("Header kind is a reserved value", ruleOffset);

  const hopsStart = hintStart + PF.HINT_HEADER_SIZE;
  const hopsEnd = hopsStart + (header & PF.HINT_HOP_COUNT_MASK) * PF.HINT_HOP_SIZE;
  validateHops(data, hopsStart, hopsEnd, ruleOffset);

  const targetOffset = hintStart + hintSize - PF.HINT_TARGET_SIZE;
  if (kind !== PF.HINT_KIND_NONE) {
    const frameMeta = readU16(data, hopsEnd + PF.HINT_FRAME_META_OFFSET);
    if ((frameMeta & PF.HINT_META_RESERVED_MASK) !== 0) malformedHint("Frame meta carries reserved bits", ruleOffset);
    const suffixHeader = data[hopsEnd + PF.HINT_FRAME_PREFIX_SIZE]!;
    if ((suffixHeader & PF.HINT_SUFFIX_RESERVED_MASK) !== 0) {
      malformedHint("Suffix header carries reserved bits", ruleOffset);
    }
    validateHops(data, hopsEnd + PF.HINT_FRAME_PREFIX_SIZE + PF.HINT_HEADER_SIZE, targetOffset, ruleOffset);
  }

  // A target meta word describes a dynamic array and is absent for every other type.
  const targetMeta = readU16(data, targetOffset + PF.HINT_TARGET_META_OFFSET);
  const targetTypeCode = data[targetOffset + PF.HINT_TARGET_TYPECODE_OFFSET]!;
  const targetMetaOk =
    targetTypeCode === TypeCode.DYNAMIC_ARRAY ? (targetMeta & PF.HINT_META_RESERVED_MASK) === 0 : targetMeta === 0;
  if (!targetMetaOk) malformedHint("Target meta carries reserved or unused state", ruleOffset);

  // An operator reads either a scalar word or a declared length, so a target carrying neither —
  // a tuple, a static array, or an undefined code — addresses nothing.
  if (!isAddressableTarget(targetTypeCode)) malformedHint("Target type code addresses no value", ruleOffset);
}

/** Read the type code the hint block at `hintStart` declares for its target. */
function hintTargetTypeCode(data: Uint8Array, hintStart: number, hintSize: number): number {
  return data[hintStart + hintSize - PF.HINT_TARGET_SIZE + PF.HINT_TARGET_TYPECODE_OFFSET]!;
}

///////////////////////////////////////////////////////////////////////////
// Policy decoder
///////////////////////////////////////////////////////////////////////////

/** Decode a policy blob, returning the structural representation and the blob bytes it spans. */
export function decodePolicy(blob: Hex): { policy: DecodedPolicy; data: Uint8Array } {
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

  const selectorStart = PF.SELECTOR_OFFSET;
  const selectorEnd = selectorStart + PF.SELECTOR_SIZE;
  const selectorHex = toHex(data, selectorStart, selectorEnd);

  const isSelectorless = (headerByte & PF.FLAG_NO_SELECTOR) !== 0;
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
  const { descriptor: desc } = decodeDescriptor(descSlice);
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

    const groupSizeStart = offset + PF.GROUP_RULECOUNT_SIZE;
    const groupSizeValue = readU32(data, groupSizeStart);
    const groupBodyStart = offset + PF.GROUP_HEADER_SIZE;
    const groupEnd = groupBodyStart + groupSizeValue;

    const ruleCountStart = offset;
    const ruleCountValue = readU16(data, ruleCountStart);
    if (ruleCountValue === 0) {
      throw new CallciumError("EMPTY_GROUP", "Group must contain at least one rule", offset);
    }
    if (groupSizeValue < ruleCountValue * PF.RULE_MIN_SIZE) {
      throw new CallciumError("GROUP_TOO_SMALL", "Declared group size is too small for its rule count", offset);
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
          "RULE_TOO_SMALL",
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
      const pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
      const pathLength = depthValue * PF.PATH_STEP_SIZE;

      // Resolve the hint block; context rules carry none.
      const ruleEnd = ruleOffset + ruleSizeValue;
      const hintStart = pathStart + pathLength;
      let hintSize = 0;
      if (scopeValue === Scope.CALLDATA) {
        hintSize = resolveHintSize(data, hintStart, ruleEnd, ruleOffset);
        validateHint(data, hintStart, hintSize, ruleOffset);
      }

      const opCodeOffset = hintStart + hintSize;
      const dataLengthOffset = opCodeOffset + PF.RULE_OPCODE_SIZE;
      const dataLengthValue = readU16(data, dataLengthOffset);

      // Validate ruleSize matches the computed layout.
      const expectedRuleSize = PF.RULE_FIXED_OVERHEAD + pathLength + hintSize + dataLengthValue;
      if (ruleSizeValue !== expectedRuleSize) {
        throw new CallciumError(
          "RULE_SIZE_MISMATCH",
          `Declared rule size ${ruleSizeValue} does not match computed size ${expectedRuleSize}`,
          ruleOffset,
        );
      }

      // Validate operator and data length.
      const opCodeValue = data[opCodeOffset]!;
      const opBase = opCodeValue & ~Op.NOT;
      if (opBase === 0 || !isValidOperatorData(opBase, dataLengthValue)) {
        throw new CallciumError("UNKNOWN_OPERATOR", "Unrecognized or malformed operator", ruleOffset);
      }

      // A length operator reads the declared length a dynamic target resolves to, and a value
      // operator reads a scalar word, so the target type fixes which family the rule may carry.
      if (hintSize !== 0) {
        const targetTypeCode = hintTargetTypeCode(data, hintStart, hintSize);
        if (isLengthValidType(targetTypeCode) !== isLengthOp(opBase)) {
          throw new CallciumError(
            "OPERATOR_TARGET_MISMATCH",
            "Operator family does not match the type the target declares",
            ruleOffset,
          );
        }
      }

      const dataStart = dataLengthOffset + PF.RULE_DATALENGTH_SIZE;

      // IN operands must be strictly ascending (unsigned); strictness also rejects duplicates.
      if (opBase === Op.IN) {
        const wordCount = dataLengthValue / 32;
        for (let word = 1; word < wordCount; word++) {
          const prev = data.subarray(dataStart + (word - 1) * 32, dataStart + word * 32);
          const cur = data.subarray(dataStart + word * 32, dataStart + (word + 1) * 32);
          if (compareBytes(prev, cur) >= 0) {
            throw new CallciumError("UNSORTED_IN_SET", "IN operands must be strictly ascending", ruleOffset);
          }
        }
      }

      // The path must be non-empty and within the depth cap.
      if (depthValue === 0) {
        throw new CallciumError("EMPTY_PATH", "Rule path must have at least one step", ruleOffset);
      }
      if (depthValue > Limits.MAX_PATH_DEPTH) {
        throw new CallciumError(
          "PATH_TOO_DEEP",
          `Path depth ${depthValue} exceeds maximum ${Limits.MAX_PATH_DEPTH}`,
          ruleOffset,
        );
      }

      // Context-scope rules must have exactly one path step naming a defined property.
      if (scopeValue === Scope.CONTEXT) {
        if (depthValue !== 1) {
          throw new CallciumError(
            "INVALID_CONTEXT_PATH",
            "Context-scope rules must have exactly one path step",
            ruleOffset,
          );
        }
        const contextPropertyId = readU16(data, pathStart);
        if (contextPropertyId > MAX_CONTEXT_PROPERTY_ID) {
          throw new CallciumError(
            "UNKNOWN_CONTEXT_PROPERTY",
            `Context rule references undefined context property 0x${contextPropertyId.toString(16).padStart(4, "0")}`,
            ruleOffset,
          );
        }
      }

      const pathHex = toHex(data, pathStart, pathStart + pathLength);
      rules.push({
        ruleSize: field(ruleSizeValue, ruleOffset, ruleOffset + PF.RULE_SIZE_SIZE),
        scope: field(scopeValue, scopeOffset, scopeOffset + 1),
        pathDepth: field(depthValue, depthOffset, depthOffset + 1),
        path: field(pathHex, pathStart, pathStart + pathLength),
        ...(hintSize > 0 && {
          hint: field(toHex(data, hintStart, hintStart + hintSize), hintStart, hintStart + hintSize),
        }),
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
      header: field({ version: desc.version, paramCount: desc.params.length }, descStart, descStart + DF.HEADER_SIZE),
      params,
      span: { start: descStart, end: descEnd },
    },
    groupCount: field(groupCountValue, groupCountStart, groupCountEnd),
    groups,
    span: { start: 0, end: data.length },
    version,
    isSelectorless,
  };

  return { policy, data };
}

///////////////////////////////////////////////////////////////////////////
// Encoder internals
///////////////////////////////////////////////////////////////////////////

type Rule = { scope: number; path: Uint8Array; operator: Uint8Array; hint: Uint8Array };

/** Flatten a Constraint into one Rule per operator, compiling its hint against the descriptor. */
function flattenConstraint(constraint: Constraint, desc: Uint8Array): Rule[] {
  const operators = constraint.operators.map(hexToBytes);
  for (const operator of operators) {
    if (operator.length < 1) {
      throw new CallciumError("INVALID_OPERATOR_BYTES", "Operator must have at least one byte (opcode).");
    }
  }

  const path = hexToBytes(constraint.path);

  // Path shape checks precede compilation: the compiler assumes a framed, depth-bounded path.
  if (path.length === 0) {
    throw new CallciumError("EMPTY_PATH", "Rule path must have at least one step.");
  }
  if ((path.length & 1) !== 0) {
    throw new CallciumError("MALFORMED_PATH", "Path byte length must be even.");
  }
  const depth = path.length / 2;
  if (depth > Limits.MAX_PATH_DEPTH) {
    throw new CallciumError("PATH_TOO_DEEP", `Path depth ${depth} exceeds maximum ${Limits.MAX_PATH_DEPTH}.`);
  }

  const hint =
    constraint.scope === Scope.CALLDATA
      ? Descriptor.compileHint(desc, parsePathSteps(constraint.path))
      : new Uint8Array(0);
  return operators.map((operator) => ({ scope: constraint.scope, path, operator, hint }));
}

/** Compare two byte arrays lexicographically. */
function compareBytes(a: Uint8Array, b: Uint8Array): number {
  const length = Math.min(a.length, b.length);
  for (let i = 0; i < length; i++) {
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

/**
 * Serialize a single rule to its wire format bytes.
 * Path shape and operator framing are established by `flattenConstraint`.
 */
function encodeRule(rule: Rule): Uint8Array {
  const depth = rule.path.length / 2;
  if (rule.scope === Scope.CONTEXT && depth !== 1) {
    throw new CallciumError("INVALID_CONTEXT_PATH", "Context-scope rules must have exactly one path step.");
  }
  const data = rule.operator.subarray(1);
  const ruleSize = PF.RULE_FIXED_OVERHEAD + rule.path.length + rule.hint.length + data.length;
  if (ruleSize > 0xffff) {
    throw new CallciumError("RULE_SIZE_OVERFLOW", `Rule size ${ruleSize} exceeds maximum 65535`);
  }

  const buf = new Uint8Array(ruleSize);
  writeBE16(buf, 0, ruleSize);
  buf[2] = rule.scope;
  buf[3] = depth;
  buf.set(rule.path, 4);
  buf.set(rule.hint, 4 + rule.path.length);
  const opOffset = 4 + rule.path.length + rule.hint.length;
  buf[opOffset] = rule.operator[0]!;
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
  const descBytes = hexToBytes(data.descriptor);

  if (data.groups.length === 0) {
    throw new CallciumError("EMPTY_POLICY", "Policy must contain at least one group");
  }
  if (data.groups.length > 0xff) {
    throw new CallciumError("GROUP_COUNT_OVERFLOW", `Group count ${data.groups.length} exceeds maximum 255`);
  }

  // Flatten constraints into rules and sort within each group. Hints are compiled first because
  // they are part of the rule bytes the group hash covers.
  const sortedGroups: Rule[][] = data.groups.map((group) => {
    const rules = group.flatMap((constraint) => flattenConstraint(constraint, descBytes));
    sortRules(rules);
    return rules;
  });

  if (descBytes.length > 0xffff) {
    throw new CallciumError("DESC_LENGTH_OVERFLOW", `Descriptor length ${descBytes.length} exceeds maximum 65535`);
  }

  const encodedGroups = sortedGroups.map((rules, groupIndex) => {
    if (rules.length === 0) {
      throw new CallciumError("EMPTY_GROUP", `Group ${groupIndex} is empty`);
    }
    if (rules.length > 0xffff) {
      throw new CallciumError(
        "RULE_COUNT_OVERFLOW",
        `Group ${groupIndex} rule count ${rules.length} exceeds maximum 65535`,
      );
    }
    return { wireBytes: encodeGroupRules(rules), ruleCount: rules.length };
  });

  // Several groups are ordered by ascending keccak256 over their rule bytes; a lone group is
  // already in canonical position, so it needs no hash.
  if (encodedGroups.length > 1) {
    const hashes = new Map(encodedGroups.map((group) => [group, keccak_256(group.wireBytes)]));
    encodedGroups.sort((a, b) => compareBytes(hashes.get(a)!, hashes.get(b)!));
  }

  const selectorBytes = data.isSelectorless ? new Uint8Array(4) : hexToBytes(data.selector);

  const headerByte = PF.VERSION | (data.isSelectorless ? PF.FLAG_NO_SELECTOR : 0);

  // Pre-compute total size.
  let totalSize = PF.HEADER_SIZE + PF.SELECTOR_SIZE + PF.DESC_LENGTH_SIZE + descBytes.length + PF.GROUP_COUNT_SIZE;
  for (const g of encodedGroups) {
    totalSize += PF.GROUP_HEADER_SIZE + g.wireBytes.length;
  }

  const out = new Uint8Array(totalSize);
  let offset = 0;

  // Policy header: header(1) | selector(4) | descLength(2) | desc(N) | groupCount(1).
  out[offset++] = headerByte;

  out.set(selectorBytes, offset);
  offset += PF.SELECTOR_SIZE;

  writeBE16(out, offset, descBytes.length);
  offset += PF.DESC_LENGTH_SIZE;

  out.set(descBytes, offset);
  offset += descBytes.length;

  out[offset++] = encodedGroups.length;

  for (const g of encodedGroups) {
    // Group header: ruleCount(2) | groupSize(4).
    writeBE16(out, offset, g.ruleCount);
    offset += PF.GROUP_RULECOUNT_SIZE;

    writeBE32(out, offset, g.wireBytes.length);
    offset += PF.GROUP_SIZE_SIZE;

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
      const hintHex = rule.hint?.value;
      const key = `${rule.scope.value}:${rule.path.value}:${hintHex ?? ""}`;
      const opHex = buildOperatorHex(rule);

      const existing = constraintMap.get(key);
      if (existing !== undefined) {
        existing.operators.push(opHex);
      } else {
        const constraint: Constraint = {
          scope: rule.scope.value,
          path: rule.path.value,
          operators: [opHex],
          ...(hintHex !== undefined && { hint: hintHex }),
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

import { concatBytes } from "@noble/hashes/utils.js";

import { bigintToHex, bytesToHex, hexToBytes, readU16, readU32, toHex, writeBE16, writeBE32 } from "./bytes";
import {
  comparisonOf,
  fieldMax,
  formatCode,
  isComparisonCode,
  isQuantifierCode,
  isScopeCode,
  isSourceCode,
  LoopQuantifier,
  MAX_CONTEXT_PROPERTY_ID,
  Op,
  PolicyFormat as PF,
  Scope,
  Source,
  sourceOf,
  TypeCode,
  type QuantifierCode,
  type ScopeCode,
} from "./constants";
import { Descriptor } from "./descriptor";
import { decodeDescriptor, inspectDescriptor } from "./descriptor-coder";
import { CallciumError } from "./errors";
import { Hint } from "./hint";
import {
  acceptsContextSource,
  canonicalize,
  contextPropertyType,
  hasCalldataLength,
  isLeftAligned,
  isLengthOp,
  isValidPayloadSize,
  LENGTH_TYPE,
  operandTypeOf,
  operandWidth,
  readMember,
  readOperator,
  toBigInt,
} from "./operators";
import { encodePath, parsePathSteps } from "./path";

import type { CallciumErrorCode } from "./errors";
import type { Hex } from "./types";
import type {
  ArrayMeta,
  BodyRule,
  DecodedFrameHint,
  DecodedGroup,
  DecodedHint,
  DecodedHop,
  DecodedOperator,
  DecodedPolicy,
  DecodedRule,
  DecodedTest,
  Field,
  LoopRule,
  PolicyData,
  Rule,
} from "./types";

///////////////////////////////////////////////////////////////////////////
// Policy validation
///////////////////////////////////////////////////////////////////////////

/**
 * Validate a policy blob against every storage-time invariant.
 * @param blob - The policy blob.
 * @throws {CallciumError} On the first invariant the blob breaks, at the offset of the group or rule containing it.
 */
export function validatePolicy(blob: Hex): void {
  const data = hexToBytes(blob);
  if (data.length < PF.DESC_OFFSET) {
    throw new CallciumError("MALFORMED_HEADER", "Policy blob is too short");
  }

  const headerByte = data[0]!;
  const major = headerByte >> PF.MAJOR_SHIFT;
  if (major !== PF.MAJOR) {
    throw new CallciumError("UNSUPPORTED_VERSION", `Major version ${major} is not supported (expected ${PF.MAJOR})`);
  }
  // A blob that uses no extension declares MINOR, the lowest minor covering its features.
  const minor = (headerByte >> PF.MINOR_SHIFT) & PF.MINOR_MASK;
  if (minor !== PF.MINOR) {
    throw new CallciumError(
      "MINOR_MISMATCH",
      `Minor version ${minor} is not the lowest covering the policy's features (expected ${PF.MINOR})`,
    );
  }

  const isSelectorless = (headerByte & PF.FLAG_NO_SELECTOR) !== 0;
  if (isSelectorless && readU32(data, PF.SELECTOR_OFFSET) !== 0) {
    throw new CallciumError("MALFORMED_HEADER", "Selectorless policy must have a zeroed selector slot");
  }

  const descLengthValue = readU16(data, PF.DESC_LENGTH_OFFSET);
  const groupCountOffset = PF.DESC_OFFSET + descLengthValue;
  if (data.length < groupCountOffset + PF.GROUP_COUNT_SIZE) {
    throw new CallciumError("MALFORMED_HEADER", "Policy blob is too short for descriptor and group count");
  }
  decodeDescriptor(data.subarray(PF.DESC_OFFSET, groupCountOffset));

  const groupCountValue = data[groupCountOffset]!;
  if (groupCountValue === 0) {
    throw new CallciumError("EMPTY_POLICY", "Policy must contain at least one group");
  }

  let offset = groupCountOffset + PF.GROUP_COUNT_SIZE;
  for (let groupIndex = 0; groupIndex < groupCountValue; groupIndex++) {
    if (offset + PF.GROUP_HEADER_SIZE > data.length) {
      throw new CallciumError("UNEXPECTED_END", "Unexpected end while reading group header", offset);
    }

    const groupSizeValue = readU32(data, offset + PF.GROUP_RULECOUNT_SIZE);
    const groupEnd = offset + PF.GROUP_HEADER_SIZE + groupSizeValue;
    if (groupEnd > data.length) {
      throw new CallciumError("GROUP_OVERFLOW", "Group extends beyond policy blob", offset);
    }

    const ruleCountValue = readU16(data, offset);
    if (ruleCountValue === 0) {
      throw new CallciumError("EMPTY_GROUP", "Group must contain at least one rule", offset);
    }

    let ruleOffset = offset + PF.GROUP_HEADER_SIZE;
    for (let ruleIndex = 0; ruleIndex < ruleCountValue; ruleIndex++) {
      if (ruleOffset + PF.RULE_SIZE_SIZE > groupEnd) groupSizeMismatch(offset);
      ruleOffset = validateRule(data, ruleOffset, groupEnd);
    }

    if (ruleOffset !== groupEnd) groupSizeMismatch(offset);
    offset = groupEnd;
  }

  // Reject trailing bytes after the last group.
  if (offset !== data.length) {
    throw new CallciumError("TRAILING_BYTES", "Trailing bytes after last group", offset);
  }
}

/** Validate a single rule and return the offset of the next rule. */
function validateRule(data: Uint8Array, ruleOffset: number, groupEnd: number): number {
  const ruleEnd = ruleOffset + ruleSize(data, ruleOffset, groupEnd);
  const scopeValue = scope(data, ruleOffset, ruleEnd);
  switch (scopeValue) {
    case Scope.LOOP:
      validateLoop(data, ruleOffset, ruleEnd);
      break;
    case Scope.CONTEXT:
    case Scope.CALLDATA:
      validateTest(data, ruleOffset, ruleEnd, scopeValue, 0);
      break;
    default:
      return scopeValue satisfies never;
  }
  return ruleEnd;
}

/** Return the size of the rule at `ruleOffset`, which must lie within `end`. */
function ruleSize(data: Uint8Array, ruleOffset: number, end: number): number {
  const ruleSizeValue = readU16(data, ruleOffset);
  if (ruleSizeValue < PF.RULE_SIZE_SIZE) {
    throw new CallciumError(
      "RULE_TOO_SMALL",
      `Rule size ${ruleSizeValue} is below minimum ${PF.RULE_SIZE_SIZE}`,
      ruleOffset,
    );
  }
  if (ruleOffset + ruleSizeValue > end) {
    throw new CallciumError("RULE_OVERFLOW", "Rule extends beyond group boundary", ruleOffset);
  }
  return ruleSizeValue;
}

/** Return the scope of the rule at `ruleOffset`, which must be a defined value. */
function scope(data: Uint8Array, ruleOffset: number, ruleEnd: number): ScopeCode {
  if (ruleOffset + PF.RULE_SCOPE_OFFSET + PF.RULE_SCOPE_SIZE > ruleEnd) ruleSizeMismatch(ruleOffset);
  const scopeValue = data[ruleOffset + PF.RULE_SCOPE_OFFSET]!;
  if (!isScopeCode(scopeValue)) {
    throw new CallciumError("UNKNOWN_SCOPE", `Unknown scope value ${scopeValue}`, ruleOffset);
  }
  return scopeValue;
}

/** Validate the loop rule at `ruleOffset` and the tests of its body. */
function validateLoop(data: Uint8Array, ruleOffset: number, ruleEnd: number): void {
  if (ruleOffset + PF.RULE_QUANTIFIER_OFFSET + PF.RULE_QUANTIFIER_SIZE > ruleEnd) ruleSizeMismatch(ruleOffset);
  const quantifier = data[ruleOffset + PF.RULE_QUANTIFIER_OFFSET]!;
  if (!isQuantifierCode(quantifier)) {
    throw new CallciumError("UNKNOWN_QUANTIFIER", `Unknown quantifier value ${quantifier}`, ruleOffset);
  }

  const { pathEnd: hintOffset, depth } = validatePath(data, ruleOffset, ruleOffset + PF.LOOP_DEPTH_OFFSET, ruleEnd);
  if (depth === 0) {
    throw new CallciumError("EMPTY_PATH", "Rule path must have at least one step", ruleOffset);
  }
  if (depth > PF.MAX_PATH_DEPTH) pathTooDeep(depth, ruleOffset);

  const frameOffset = validateHint(data, ruleOffset, hintOffset, ruleEnd);
  if (frameOffset + PF.HINT_FRAME_PREFIX_SIZE + PF.GROUP_RULECOUNT_SIZE > ruleEnd) ruleSizeMismatch(ruleOffset);
  const frameMeta = readU16(data, frameOffset + PF.HINT_FRAME_META_OFFSET);
  if ((frameMeta & PF.HINT_META_RESERVED_MASK) !== 0) malformedHint("Frame meta carries reserved bits", ruleOffset);

  const bodyOffset = frameOffset + PF.HINT_FRAME_PREFIX_SIZE;
  const ruleCountValue = readU16(data, bodyOffset);
  if (ruleCountValue === 0) {
    throw new CallciumError("EMPTY_GROUP", "Loop body must contain at least one rule", ruleOffset);
  }

  let testOffset = bodyOffset + PF.GROUP_RULECOUNT_SIZE;
  for (let ruleIndex = 0; ruleIndex < ruleCountValue; ruleIndex++) {
    if (testOffset + PF.RULE_SIZE_SIZE > ruleEnd) ruleSizeMismatch(ruleOffset);
    const testEnd = testOffset + ruleSize(data, testOffset, ruleEnd);
    const scopeValue = scope(data, testOffset, testEnd);
    switch (scopeValue) {
      case Scope.LOOP:
        throw new CallciumError("INVALID_NESTED_LOOP", "Loop body holds a loop", testOffset);
      case Scope.CONTEXT:
      case Scope.CALLDATA:
        validateTest(data, testOffset, testEnd, scopeValue, depth);
        break;
      default:
        return scopeValue satisfies never;
    }
    testOffset = testEnd;
  }

  if (testOffset !== ruleEnd) ruleSizeMismatch(ruleOffset);
}

/** Validate the context or calldata test at `ruleOffset`, `outerDepth` path steps below the arguments. */
function validateTest(
  data: Uint8Array,
  ruleOffset: number,
  ruleEnd: number,
  scopeValue: typeof Scope.CONTEXT | typeof Scope.CALLDATA,
  outerDepth: number,
): void {
  let operatorOffset: number;
  let typeCode: number;
  switch (scopeValue) {
    case Scope.CONTEXT: {
      // Context-scope rules must have exactly one path step naming a defined property.
      if (ruleOffset + PF.RULE_PATH_OFFSET > ruleEnd) ruleSizeMismatch(ruleOffset);
      if (data[ruleOffset + PF.RULE_DEPTH_OFFSET] !== 1) {
        throw new CallciumError(
          "INVALID_CONTEXT_PATH",
          "Context-scope rules must have exactly one path step",
          ruleOffset,
        );
      }
      operatorOffset = ruleOffset + PF.RULE_PATH_OFFSET + PF.PROPERTY_ID_SIZE;
      if (operatorOffset > ruleEnd) ruleSizeMismatch(ruleOffset);
      const contextPropertyId = readU16(data, ruleOffset + PF.RULE_PATH_OFFSET);
      if (contextPropertyId > MAX_CONTEXT_PROPERTY_ID) {
        throw new CallciumError(
          "UNKNOWN_CONTEXT_PROPERTY",
          `Unknown context property ID ${formatCode(contextPropertyId, PF.PROPERTY_ID_SIZE)}`,
          ruleOffset,
        );
      }
      typeCode = contextPropertyType(contextPropertyId);
      break;
    }
    case Scope.CALLDATA: {
      const { pathEnd: hintOffset, depth } = validatePath(data, ruleOffset, ruleOffset + PF.RULE_DEPTH_OFFSET, ruleEnd);
      // A root test lies outside every loop, and only a root path must be non-empty.
      if (outerDepth === 0 && depth === 0) {
        throw new CallciumError("EMPTY_PATH", "Rule path must have at least one step", ruleOffset);
      }
      if (outerDepth + depth > PF.MAX_PATH_DEPTH) pathTooDeep(outerDepth + depth, ruleOffset);

      const targetOffset = validateHint(data, ruleOffset, hintOffset, ruleEnd);
      operatorOffset = targetOffset + PF.HINT_TARGET_SIZE;
      if (operatorOffset > ruleEnd) ruleSizeMismatch(ruleOffset);
      const targetMeta = readU16(data, targetOffset + PF.HINT_TARGET_META_OFFSET);
      typeCode = data[targetOffset + PF.HINT_TARGET_TYPECODE_OFFSET]!;
      // A target meta word describes a dynamic array and is absent for every other type.
      const targetMetaOk =
        typeCode === TypeCode.DYNAMIC_ARRAY ? (targetMeta & PF.HINT_META_RESERVED_MASK) === 0 : targetMeta === 0;
      if (!targetMetaOk) malformedHint("Target meta carries reserved or unused state", ruleOffset);

      // An operator reads either a scalar word or a declared length, so a target carrying neither — a tuple, a static
      // array, or an undefined code — addresses nothing.
      if (operandWidth(typeCode) === undefined && !hasCalldataLength(typeCode)) {
        malformedHint("Target type code addresses no value", ruleOffset);
      }
      break;
    }
    default:
      return scopeValue satisfies never;
  }

  const operatorEnd = validateOperator(data, ruleOffset, operatorOffset, ruleEnd, typeCode);
  if (operatorEnd !== ruleEnd) ruleSizeMismatch(ruleOffset);
}

/**
 * Require the path whose depth field sits at `depthOffset` to step below the reserved marker range. Return the
 * offset past the path and its depth.
 */
function validatePath(
  data: Uint8Array,
  ruleOffset: number,
  depthOffset: number,
  ruleEnd: number,
): { pathEnd: number; depth: number } {
  if (depthOffset + PF.RULE_DEPTH_SIZE > ruleEnd) ruleSizeMismatch(ruleOffset);
  const depth = data[depthOffset]!;
  const pathStart = depthOffset + PF.RULE_DEPTH_SIZE;
  const pathEnd = pathStart + depth * PF.PATH_STEP_SIZE;
  if (pathEnd > ruleEnd) ruleSizeMismatch(ruleOffset);

  for (let offset = pathStart; offset < pathEnd; offset += PF.PATH_STEP_SIZE) {
    const step = readU16(data, offset);
    if (step >= PF.PATH_MARKER_BASE) {
      throw new CallciumError(
        "UNKNOWN_PATH_STEP",
        `Path step ${formatCode(step, PF.PATH_STEP_SIZE)} is in the reserved marker range`,
        ruleOffset,
      );
    }
  }
  return { pathEnd, depth };
}

/**
 * Require the hint header and hops at `hintOffset` to carry no reserved or unused state, and return the offset past
 * the hops.
 */
function validateHint(data: Uint8Array, ruleOffset: number, hintOffset: number, ruleEnd: number): number {
  if (hintOffset + PF.HINT_HEADER_SIZE > ruleEnd) ruleSizeMismatch(ruleOffset);
  const header = data[hintOffset]!;
  if ((header & PF.HINT_HEADER_RESERVED_MASK) !== 0) malformedHint("Header carries reserved bits", ruleOffset);

  const hopsStart = hintOffset + PF.HINT_HEADER_SIZE;
  const hopsEnd = hopsStart + (header & PF.HINT_HOP_COUNT_MASK) * PF.HINT_HOP_SIZE;
  if (hopsEnd > ruleEnd) ruleSizeMismatch(ruleOffset);
  validateHops(data, hopsStart, hopsEnd, ruleOffset);
  return hopsEnd;
}

/** Require every hop entry in `[start, end)` to carry no reserved or unused state. */
function validateHops(data: Uint8Array, start: number, end: number, ruleOffset: number): void {
  for (let offset = start; offset < end; offset += PF.HINT_HOP_SIZE) {
    const index = readU16(data, offset + PF.HINT_HOP_INDEX_OFFSET);
    if (index !== PF.HINT_NO_INDEX && index >= PF.PATH_MARKER_BASE) {
      malformedHint("Hop index is a reserved value", ruleOffset);
    }

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

/** Validate the operator at `offset` against a target of `typeCode` and return the offset past it. */
function validateOperator(
  data: Uint8Array,
  ruleOffset: number,
  offset: number,
  ruleEnd: number,
  typeCode: number,
): number {
  if (offset + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE > ruleEnd) ruleSizeMismatch(ruleOffset);
  const opCodeValue = data[offset]!;
  const opBase = comparisonOf(opCodeValue);
  const source = sourceOf(opCodeValue);
  if (!isComparisonCode(opBase) || !isSourceCode(source)) {
    throw new CallciumError(
      "UNKNOWN_OPERATOR",
      `Unknown operator code ${formatCode(opCodeValue & ~Op.NOT, PF.RULE_OPCODE_SIZE)}`,
      ruleOffset,
    );
  }

  // A length operator reads the declared length a dynamic target resolves to, and a value operator reads a scalar
  // word, so the target type fixes which family the rule may carry.
  const isLength = isLengthOp(opBase);
  if (hasCalldataLength(typeCode) !== isLength) {
    throw new CallciumError(
      "OPERATOR_TARGET_MISMATCH",
      "Operator family does not match the type the target declares",
      ruleOffset,
    );
  }

  const dataLengthValue = readU16(data, offset + PF.RULE_OPCODE_SIZE);
  const dataStart = offset + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;
  const operatorEnd = dataStart + dataLengthValue;

  switch (source) {
    case Source.CONTEXT: {
      if (!acceptsContextSource(opBase)) {
        throw new CallciumError(
          "INVALID_CONTEXT_OPERAND",
          "Context operand applies only to EQ, GT, LT, GTE and LTE",
          ruleOffset,
        );
      }
      if (dataLengthValue !== PF.PROPERTY_ID_SIZE) dataLengthMismatch(dataLengthValue, PF.PROPERTY_ID_SIZE, ruleOffset);
      if (operatorEnd > ruleEnd) ruleSizeMismatch(ruleOffset);
      // A context operand must name a defined context property.
      const contextPropertyId = readU16(data, dataStart);
      if (contextPropertyId > MAX_CONTEXT_PROPERTY_ID) {
        throw new CallciumError(
          "UNKNOWN_CONTEXT_PROPERTY",
          `Unknown context property ID ${formatCode(contextPropertyId, PF.PROPERTY_ID_SIZE)}`,
          ruleOffset,
        );
      }
      break;
    }
    case Source.CONSTANT: {
      // The target is a static elementary type or carries a calldata length, so the operand has a width.
      const width = operandWidth(isLength ? LENGTH_TYPE : typeCode)!;
      if (!isValidPayloadSize(opBase, dataLengthValue, width)) dataLengthMismatch(dataLengthValue, width, ruleOffset);
      if (operatorEnd > ruleEnd) ruleSizeMismatch(ruleOffset);
      // IN operands must be strictly ascending (unsigned); strictness also rejects duplicates.
      if (opBase === Op.IN) validateInAscending(data, dataStart, dataLengthValue, width, ruleOffset);
      break;
    }
    default:
      return source satisfies never;
  }
  return operatorEnd;
}

/**
 * Require the IN operand members to be strictly ascending by unsigned value. Sign extension and left alignment keep the
 * unsigned order of a member's bytes, so the bytes order the members as their loaded words.
 */
function validateInAscending(
  data: Uint8Array,
  dataStart: number,
  dataLength: number,
  width: number,
  ruleOffset: number,
): void {
  const memberCount = dataLength / width;
  let prev = readMember(data, dataStart, width);
  for (let member = 1; member < memberCount; member++) {
    const cur = readMember(data, dataStart + member * width, width);
    if (cur <= prev) {
      throw new CallciumError("UNSORTED_IN_SET", "IN operands must be strictly ascending", ruleOffset);
    }
    prev = cur;
  }
}

/** Throw a GROUP_SIZE_MISMATCH error for the group at `groupOffset`. */
function groupSizeMismatch(groupOffset: number): never {
  throw new CallciumError("GROUP_SIZE_MISMATCH", "Rules do not exactly fill the declared group size", groupOffset);
}

/** Throw a RULE_SIZE_MISMATCH error for the rule at `ruleOffset`. */
function ruleSizeMismatch(ruleOffset: number): never {
  throw new CallciumError(
    "RULE_SIZE_MISMATCH",
    "Rule content does not exactly fill the declared rule size",
    ruleOffset,
  );
}

/** Throw a MALFORMED_HINT error with the given detail. */
function malformedHint(detail: string, ruleOffset: number): never {
  throw new CallciumError("MALFORMED_HINT", detail, ruleOffset);
}

/** Throw a PATH_TOO_DEEP error for a path of `depth` steps counted across the enclosing loop. */
function pathTooDeep(depth: number, ruleOffset: number): never {
  throw new CallciumError("PATH_TOO_DEEP", `Path depth ${depth} exceeds maximum ${PF.MAX_PATH_DEPTH}`, ruleOffset);
}

/** Throw a DATA_LENGTH_MISMATCH error for `dataLength` against operands of `width` bytes. */
function dataLengthMismatch(dataLength: number, width: number, ruleOffset: number): never {
  throw new CallciumError(
    "DATA_LENGTH_MISMATCH",
    `Operator data length ${dataLength} does not hold ${width}-byte operands`,
    ruleOffset,
  );
}

///////////////////////////////////////////////////////////////////////////
// Encoding
///////////////////////////////////////////////////////////////////////////

/**
 * A rule with its size-free bytes, its key in the canonical order, and its bytes after its `ruleSize`, each body rule
 * framed.
 */
type Keyed = { rule: Rule; key: Uint8Array; content: Uint8Array };

/**
 * Encode the canonical form of a policy: each group normalized, its rules and the groups sorted by their
 * size-free bytes, repeats dropped.
 * @param data - The policy.
 * @returns The policy blob as a 0x-prefixed hex string.
 * @throws {CallciumError} When a field does not have the shape the encoder reads, or a path does not compile.
 * When an operator does not apply to its target, or a constant is not a value of its operand type.
 * When a count or size overflows its field.
 */
function encode(data: PolicyData): Hex {
  if (data.groups.length === 0) {
    throw new CallciumError("EMPTY_POLICY", "Policy must contain at least one group");
  }
  const desc = hexToBytes(data.descriptor);
  requireFieldFits(desc.length, PF.DESC_LENGTH_SIZE, "DESC_LENGTH_OVERFLOW", "Descriptor length");

  const groups = sortDedupe(
    data.groups.map((rules, groupIndex) => encodeGroup(desc, rules, groupIndex)),
    (group) => group.key,
  );
  requireFieldFits(groups.length, PF.GROUP_COUNT_SIZE, "GROUP_COUNT_OVERFLOW", "Group count");

  // Selector slot is defined as zero for selectorless policies regardless of what the caller provides.
  const selector = data.isSelectorless ? new Uint8Array(PF.SELECTOR_SIZE) : hexToBytes(data.selector);
  if (selector.length !== PF.SELECTOR_SIZE) {
    throw new CallciumError("MALFORMED_SELECTOR", `Selector must be ${PF.SELECTOR_SIZE} bytes, got ${selector.length}`);
  }
  const header = (PF.MAJOR << PF.MAJOR_SHIFT) | (PF.MINOR << PF.MINOR_SHIFT);
  return bytesToHex(
    concatBytes(
      Uint8Array.of(data.isSelectorless ? header | PF.FLAG_NO_SELECTOR : header),
      selector,
      be16(desc.length),
      desc,
      Uint8Array.of(groups.length),
      ...groups.map((group) => group.encoded),
    ),
  );
}

/** Encode a group in canonical form: its size-free bytes, and its bytes with the group header. */
function encodeGroup(desc: Uint8Array, rules: Rule[], groupIndex: number): { key: Uint8Array; encoded: Uint8Array } {
  if (rules.length === 0) {
    throw new CallciumError("EMPTY_GROUP", `Group ${groupIndex} is empty`);
  }

  // Every rule in canonical form, bodies first; then loops joined, context tests hoisted, and the rules sorted.
  const normalized = rules.map((rule, ruleIndex) => {
    checkRule(rule, groupIndex, ruleIndex);
    return normalizeRule(desc, rule);
  });
  const finished = finish(desc, hoistContext(joinLoops(desc, normalized)));

  requireFieldFits(finished.length, PF.GROUP_RULECOUNT_SIZE, "RULE_COUNT_OVERFLOW", `Group ${groupIndex} rule count`);
  const ruleBytes = concatBytes(
    ...finished.map(({ content }) => {
      const size = content.length + PF.RULE_SIZE_SIZE;
      requireFieldFits(size, PF.RULE_SIZE_SIZE, "RULE_SIZE_OVERFLOW", "Rule size");
      return concatBytes(be16(size), content);
    }),
  );
  return {
    key: concatBytes(...finished.map(({ key }) => key)),
    encoded: concatBytes(be16(finished.length), be32(ruleBytes.length), ruleBytes),
  };
}

/** Require the rule's fields to have the shapes the encoder reads. */
function checkRule(rule: Rule, groupIndex: number, ruleIndex: number): void {
  if (rule.scope !== Scope.LOOP) {
    checkTest(rule.scope, rule.path, rule.operator, 0, groupIndex, ruleIndex);
    return;
  }
  const quantifier: number = rule.quantifier;
  if (!isQuantifierCode(quantifier)) {
    throw new CallciumError("UNKNOWN_QUANTIFIER", `Unknown quantifier value ${quantifier}`);
  }
  const arrayDepth = checkPath(hexToBytes(rule.path), true, 0);
  for (const test of rule.body) checkTest(test.scope, test.path, test.operator, arrayDepth, groupIndex, ruleIndex);
}

/**
 * Require a test's operator to be an opcode and one or more 32-byte words, and its path to have the shape its scope
 * reads. For a calldata test, the path comes after `depthBefore` steps of an enclosing loop.
 */
function checkTest(
  testScope: number,
  path: Hex,
  operator: Hex,
  depthBefore: number,
  groupIndex: number,
  ruleIndex: number,
): void {
  const operatorBytes = hexToBytes(operator);
  const isWords = operatorBytes.length > 1 && (operatorBytes.length - 1) % 32 === 0;
  // A context property operand is one ID within its field.
  const isContextId =
    sourceOf(operatorBytes[0] ?? 0) !== Source.CONTEXT ||
    (operatorBytes.length === 33 && toBigInt(operatorBytes, 1) <= BigInt(fieldMax(PF.PROPERTY_ID_SIZE)));
  if (!isWords || !isContextId) {
    throw new CallciumError(
      "INVALID_OPERATOR_BYTES",
      `Group ${groupIndex} rule ${ruleIndex} operator must be an opcode followed by 32-byte operand words`,
    );
  }
  const pathBytes = hexToBytes(path);
  if (testScope === Scope.CONTEXT) {
    if (pathBytes.length !== PF.PROPERTY_ID_SIZE) {
      throw new CallciumError("INVALID_CONTEXT_PATH", "Context-scope rules must have exactly one path step");
    }
  } else if (testScope === Scope.CALLDATA) {
    checkPath(pathBytes, depthBefore === 0, depthBefore);
  } else {
    throw new CallciumError("UNKNOWN_SCOPE", `Unknown scope value ${testScope}`);
  }
}

/**
 * Require a calldata path to be whole steps, nonempty where `required`, and within `MAX_PATH_DEPTH` with the
 * `depthBefore` steps of an enclosing loop. Return the depth reached.
 */
function checkPath(path: Uint8Array, required: boolean, depthBefore: number): number {
  if (required && path.length === 0) {
    throw new CallciumError("EMPTY_PATH", "Rule path must have at least one step");
  }
  if (path.length % PF.PATH_STEP_SIZE !== 0) {
    throw new CallciumError("MALFORMED_PATH", "Path byte length must be even");
  }
  const depth = depthBefore + path.length / PF.PATH_STEP_SIZE;
  if (depth > PF.MAX_PATH_DEPTH) {
    throw new CallciumError("PATH_TOO_DEEP", `Path depth ${depth} exceeds maximum ${PF.MAX_PATH_DEPTH}`);
  }
  return depth;
}

///////////////////////////////////////////////////////////////////////////
// Normalization
///////////////////////////////////////////////////////////////////////////

/**
 * Return the rule in canonical form. Its operator is positive and no one-member set, a context pair has the lower ID
 * as subject, and a loop's body is finished.
 */
function normalizeRule(desc: Uint8Array, rule: Rule): Rule {
  if (rule.scope !== Scope.LOOP) return normalizeTest(rule);
  return loop(desc, rule.quantifier, rule.path, rule.body.map(normalizeTest));
}

/**
 * Return the test with its operator in canonical form and, for a context test against another context property, the
 * lower ID as subject.
 */
function normalizeTest(test: BodyRule): BodyRule {
  const operator = normalizeOperator(hexToBytes(test.operator));
  const opCode = operator[0]!;
  const normalized: BodyRule = { scope: test.scope, path: test.path, operator: bytesToHex(operator) };
  if (test.scope !== Scope.CONTEXT || sourceOf(opCode) !== Source.CONTEXT) return normalized;

  const swapped = swapOf(comparisonOf(opCode));
  const other = toBigInt(operator, 1);
  const property = readU16(hexToBytes(test.path), 0);
  if (swapped === undefined || other >= BigInt(property)) return normalized;

  const word = new Uint8Array(32);
  writeBE16(word, 30, property);
  return {
    scope: test.scope,
    path: encodePath([Number(other)]),
    operator: bytesToHex(concatBytes(Uint8Array.of((opCode & ~Op.COMPARISON_MASK) | swapped), word)),
  };
}

/**
 * Return the operator without NOT where a positive comparison expresses the negation, and a one-member constant set as
 * an equality.
 */
function normalizeOperator(operator: Uint8Array): Uint8Array {
  let opCode = operator[0]!;
  const comparison = comparisonOf(opCode);
  if ((opCode & Op.NOT) !== 0) {
    const positive = negationOf(comparison);
    if (positive !== undefined) opCode = (opCode & ~(Op.NOT | Op.COMPARISON_MASK)) | positive;
  }
  if (comparison === Op.IN && sourceOf(opCode) === Source.CONSTANT && operator.length === 33) {
    opCode = (opCode & ~Op.COMPARISON_MASK) | Op.EQ;
  }
  const normalized = operator.slice();
  normalized[0] = opCode;
  return normalized;
}

/** Return the loop over the array at `arrayPath` with its body finished. */
function loop(desc: Uint8Array, quantifier: QuantifierCode, arrayPath: Hex, tests: BodyRule[]): LoopRule {
  const steps = parsePathSteps(arrayPath);
  const compiled = Hint.requireCompiled(Hint.compileLoop(desc, steps), steps, 0);
  const body = finish(desc, tests, compiled.node)
    .map(({ rule }) => rule)
    .filter((rule): rule is BodyRule => rule.scope !== Scope.LOOP);
  return { scope: Scope.LOOP, quantifier, path: arrayPath, body };
}

/**
 * Join every `ALL` loop into the first `ALL` loop over the same array. `ANY` loops stay apart: they are independent
 * existentials.
 */
function joinLoops(desc: Uint8Array, rules: Rule[]): Rule[] {
  const consumed = new Set<number>();
  const joined: Rule[] = [];
  rules.forEach((rule, ruleIndex) => {
    if (consumed.has(ruleIndex)) return;
    if (!isAllLoop(rule)) {
      joined.push(rule);
      return;
    }
    const tests = [...rule.body];
    for (let laterIndex = ruleIndex + 1; laterIndex < rules.length; laterIndex++) {
      const later = rules[laterIndex]!;
      if (!isAllLoop(later) || later.path.toLowerCase() !== rule.path.toLowerCase()) continue;
      tests.push(...later.body);
      consumed.add(laterIndex);
    }
    joined.push(loop(desc, LoopQuantifier.ALL, rule.path, tests));
  });
  return joined;
}

/**
 * Move the context tests of every `ANY` loop whose body contains a calldata test into the group:
 * `∃i.(P ∧ Q(i)) ≡ P ∧ ∃i.Q(i)`.
 */
function hoistContext(rules: Rule[]): Rule[] {
  const hoisted: Rule[] = [];
  const kept = rules.map((rule) => {
    if (!hoists(rule)) return rule;
    hoisted.push(...rule.body.filter((test) => test.scope === Scope.CONTEXT));
    return { ...rule, body: rule.body.filter((test) => test.scope !== Scope.CONTEXT) };
  });
  return [...kept, ...hoisted];
}

/**
 * Return the rules sorted by their size-free bytes, repeats dropped and lone range pairs fused. Fusing counts distinct
 * rules, so fusing follows dropping repeats. A range can repeat a rule already present, so sorting follows fusing.
 */
function finish(desc: Uint8Array, rules: Rule[], start?: number): Keyed[] {
  const keyed = sortDedupe(
    rules.map((rule) => keyedRule(desc, rule, start)),
    ({ key }) => key,
  );
  return sortDedupe(fuseRanges(desc, keyed, start), ({ key }) => key);
}

/**
 * Fuse each lone pair of bounds on one subject into a range: the lower bound becomes the range, the upper bound leaves.
 * The range is defined as the pair, so no bound needs comparing.
 */
function fuseRanges(desc: Uint8Array, keyed: Keyed[], start?: number): Keyed[] {
  return keyed.flatMap((entry) => {
    const rule = entry.rule;
    const bound = boundOf(rule);
    const partner = bound === undefined ? undefined : lonePartner(keyed, rule, bound);
    if (bound === undefined || partner === undefined || rule.scope === Scope.LOOP) return [entry];
    if (!bound.isLower) return [];

    const operator = hexToBytes(rule.operator);
    const upper = hexToBytes(partner.operator);
    const range: BodyRule = {
      scope: rule.scope,
      path: rule.path,
      operator: bytesToHex(
        concatBytes(
          Uint8Array.of(bound.isLength ? Op.LENGTH_BETWEEN : Op.BETWEEN),
          operator.subarray(1),
          upper.subarray(1),
        ),
      ),
    };
    return [keyedRule(desc, range, start)];
  });
}

/** The bound a rule places: whether it bounds a length, and whether from below. */
type Bound = { isLength: boolean; isLower: boolean };

/**
 * Return the other bound of the lone pair `rule` belongs to, or undefined unless one rule bounds each side of its
 * subject.
 */
function lonePartner(keyed: Keyed[], rule: Rule, bound: Bound): BodyRule | undefined {
  let sameSide = 0;
  let partner: BodyRule | undefined;
  let otherSide = 0;
  for (const { rule: candidate } of keyed) {
    const candidateBound = boundOf(candidate);
    if (candidateBound === undefined || candidate.scope === Scope.LOOP || candidate.scope !== rule.scope) continue;
    if (candidateBound.isLength !== bound.isLength || candidate.path.toLowerCase() !== rule.path.toLowerCase())
      continue;
    if (candidateBound.isLower === bound.isLower) {
      sameSide++;
    } else {
      otherSide++;
      partner = candidate;
    }
  }
  return sameSide === 1 && otherSide === 1 ? partner : undefined;
}

/**
 * Return the bound the rule places, an unnegated constant `GTE`, `LTE`, `LENGTH_GTE` or `LENGTH_LTE`, or undefined.
 */
function boundOf(rule: Rule): Bound | undefined {
  if (rule.scope === Scope.LOOP) return undefined;
  const operator = hexToBytes(rule.operator);
  if (operator.length !== 33) return undefined;
  switch (operator[0]!) {
    case Op.GTE:
      return { isLength: false, isLower: true };
    case Op.LTE:
      return { isLength: false, isLower: false };
    case Op.LENGTH_GTE:
      return { isLength: true, isLower: true };
    case Op.LENGTH_LTE:
      return { isLength: true, isLower: false };
    default:
      return undefined;
  }
}

///////////////////////////////////////////////////////////////////////////
// Rule bytes
///////////////////////////////////////////////////////////////////////////

/**
 * Return the rule with its size-free bytes and its content. Its paths compile from the starting point: the arguments,
 * or the loop element whose node lies at `start`.
 */
function keyedRule(desc: Uint8Array, rule: Rule, start?: number): Keyed {
  if (rule.scope !== Scope.LOOP) {
    const key = testBytes(desc, rule, start);
    return { rule, key, content: key };
  }

  const steps = parsePathSteps(rule.path);
  const compiled = Hint.requireCompiled(Hint.compileLoop(desc, steps), steps, 0);
  const path = hexToBytes(rule.path);
  const head = concatBytes(
    Uint8Array.of(Scope.LOOP, rule.quantifier, steps.length),
    path,
    compiled.hint,
    be16(rule.body.length),
  );
  const tests = rule.body.map((test) => testBytes(desc, test, compiled.node));
  return {
    rule,
    key: concatBytes(head, ...tests),
    content: concatBytes(head, ...tests.map((test) => concatBytes(be16(test.length + PF.RULE_SIZE_SIZE), test))),
  };
}

/** Return a test's size-free bytes, its path compiled from the starting point at `start`. */
function testBytes(desc: Uint8Array, test: BodyRule, start?: number): Uint8Array {
  const path = hexToBytes(test.path);
  if (test.scope === Scope.CONTEXT) {
    const contextPropertyId = readU16(path, 0);
    const operator = writeOperator(hexToBytes(test.operator), contextPropertyType(contextPropertyId));
    return concatBytes(Uint8Array.of(Scope.CONTEXT, CONTEXT_PATH_DEPTH), path, operator);
  }

  const steps = parsePathSteps(test.path);
  const compiled = Hint.requireCompiled(Hint.compileTest(desc, steps, start), steps, 0);
  const operator = writeOperator(hexToBytes(test.operator), desc[compiled.node]!);
  return concatBytes(Uint8Array.of(Scope.CALLDATA, steps.length), path, compiled.hint, operator);
}

/**
 * Return the operator as the wire carries it against a target of `typeCode`: `opCode | dataLength | data`. Each
 * constant narrows to its operand type's width. A context property is written as its ID.
 */
function writeOperator(operator: Uint8Array, typeCode: number): Uint8Array {
  const opCode = operator[0]!;
  const operandType = operandTypeOf(comparisonOf(opCode), typeCode);
  if (operandType === undefined) {
    throw new CallciumError("OPERATOR_TARGET_MISMATCH", "Comparison does not apply to the target type");
  }

  const data: Uint8Array[] = [];
  if (sourceOf(opCode) === Source.CONTEXT) {
    data.push(operator.subarray(31, 33));
  } else {
    const width = operandWidth(operandType)!;
    for (let offset = 1; offset < operator.length; offset += 32) {
      const word = toBigInt(operator, offset);
      if (canonicalize(word, operandType) !== word) {
        throw new CallciumError(
          "OUT_OF_PHYSICAL_BOUNDS",
          `Operand ${bigintToHex(word)} is outside the range of its operand type`,
        );
      }
      // A narrow value fills the low bytes of its word, a left-aligned one the high bytes.
      const start = isLeftAligned(operandType) ? offset : offset + 32 - width;
      data.push(operator.subarray(start, start + width));
    }
  }
  const dataBytes = concatBytes(...data);
  return concatBytes(Uint8Array.of(opCode), be16(dataBytes.length), dataBytes);
}

///////////////////////////////////////////////////////////////////////////
// Decoding
///////////////////////////////////////////////////////////////////////////

/**
 * Decode a policy blob into the policy it states.
 * @param blob - The policy blob.
 * @returns The decoded policy, each operand loaded to its 32-byte word.
 * @throws {CallciumError} When the blob fails storage validation or its descriptor fails DV-1 or DV-2.
 */
function decode(blob: Hex): PolicyData {
  validatePolicy(blob);
  const data = hexToBytes(blob);

  const isSelectorless = (data[0]! & PF.FLAG_NO_SELECTOR) !== 0;
  const groupCountOffset = PF.DESC_OFFSET + readU16(data, PF.DESC_LENGTH_OFFSET);
  Descriptor.validateMeta(data.subarray(PF.DESC_OFFSET, groupCountOffset));
  const groups: Rule[][] = [];
  let offset = groupCountOffset + PF.GROUP_COUNT_SIZE;
  const groupCount = data[groupCountOffset]!;
  for (let groupIndex = 0; groupIndex < groupCount; groupIndex++) {
    const rules: Rule[] = [];
    const ruleCount = readU16(data, offset);
    offset += PF.GROUP_HEADER_SIZE;
    for (let ruleIndex = 0; ruleIndex < ruleCount; ruleIndex++) {
      rules.push(readRule(data, offset));
      offset += readU16(data, offset);
    }
    groups.push(rules);
  }
  return {
    isSelectorless,
    selector: isSelectorless ? "0x00000000" : toHex(data, PF.SELECTOR_OFFSET, PF.SELECTOR_OFFSET + PF.SELECTOR_SIZE),
    descriptor: toHex(data, PF.DESC_OFFSET, groupCountOffset),
    groups,
  };
}

/** Read the root rule at `ruleOffset`. */
function readRule(data: Uint8Array, ruleOffset: number): Rule {
  if (data[ruleOffset + PF.RULE_SCOPE_OFFSET] !== Scope.LOOP) return readTest(data, ruleOffset);

  const quantifier = data[ruleOffset + PF.RULE_QUANTIFIER_OFFSET]!;
  if (!isQuantifierCode(quantifier)) {
    throw new CallciumError("UNKNOWN_QUANTIFIER", `Unknown quantifier value ${quantifier}`, ruleOffset);
  }
  const pathStart = ruleOffset + PF.LOOP_DEPTH_OFFSET + PF.RULE_DEPTH_SIZE;
  const hintOffset = pathStart + data[ruleOffset + PF.LOOP_DEPTH_OFFSET]! * PF.PATH_STEP_SIZE;

  // The body follows the frame hint: its hops, the frame prefix, then `ruleCount`.
  const bodyOffset =
    hintOffset + PF.HINT_HEADER_SIZE + data[hintOffset]! * PF.HINT_HOP_SIZE + PF.HINT_FRAME_PREFIX_SIZE;
  const body: BodyRule[] = [];
  let testOffset = bodyOffset + PF.GROUP_RULECOUNT_SIZE;
  const bodyCount = readU16(data, bodyOffset);
  for (let bodyIndex = 0; bodyIndex < bodyCount; bodyIndex++) {
    body.push(readTest(data, testOffset));
    testOffset += readU16(data, testOffset);
  }
  return {
    scope: Scope.LOOP,
    quantifier,
    path: toHex(data, pathStart, hintOffset),
    hint: toHex(data, hintOffset, bodyOffset),
    body,
  };
}

/** Read the test or context test at `ruleOffset`, each constant loaded to its 32-byte word. */
function readTest(data: Uint8Array, ruleOffset: number): BodyRule {
  const testScope = data[ruleOffset + PF.RULE_SCOPE_OFFSET]!;
  if (testScope !== Scope.CONTEXT && testScope !== Scope.CALLDATA) {
    throw new CallciumError("UNKNOWN_SCOPE", `Unknown scope value ${testScope}`, ruleOffset);
  }
  const pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
  let pathEnd: number;
  let opOffset: number;
  let typeCode: number;
  if (testScope === Scope.CONTEXT) {
    pathEnd = pathStart + PF.PROPERTY_ID_SIZE;
    opOffset = pathEnd;
    typeCode = contextPropertyType(readU16(data, pathStart));
  } else {
    // The hint addresses the target: its hops, then the target block ending in the type code.
    pathEnd = pathStart + data[ruleOffset + PF.RULE_DEPTH_OFFSET]! * PF.PATH_STEP_SIZE;
    const targetOffset = pathEnd + PF.HINT_HEADER_SIZE + data[pathEnd]! * PF.HINT_HOP_SIZE;
    typeCode = data[targetOffset + PF.HINT_TARGET_TYPECODE_OFFSET]!;
    opOffset = targetOffset + PF.HINT_TARGET_SIZE;
  }

  const operator = operatorHex(readOperator(data, opOffset, typeCode));
  const path = toHex(data, pathStart, pathEnd);
  if (testScope === Scope.CONTEXT) return { scope: testScope, path, operator };
  return { scope: testScope, path, hint: toHex(data, pathEnd, opOffset), operator };
}

/**
 * Spell a decoded operator as policy data does. The result is the operator's code, then one 32-byte word per constant
 * operand, or the context property's ID as a 32-byte word.
 */
export function operatorHex(operator: DecodedOperator): Hex {
  const words =
    operator.source === Source.CONTEXT ? [bigintToHex(BigInt(operator.contextPropertyId))] : operator.values;
  return `0x${operator.opCode.toString(16).padStart(2, "0")}${words.map((word) => word.slice(2)).join("")}`;
}

///////////////////////////////////////////////////////////////////////////
// Inspection
///////////////////////////////////////////////////////////////////////////

/**
 * Inspect a policy blob: every field it stores with the bytes that contain it. The descriptor is a node tree, the hints
 * are split into their fields and the operators are parsed.
 * @param blob - The policy blob.
 * @returns The inspected policy, each operand loaded to its 32-byte word.
 * @throws {CallciumError} When the blob fails storage validation or its descriptor fails DV-1 or DV-2.
 */
function inspect(blob: Hex): DecodedPolicy {
  validatePolicy(blob);
  const data = hexToBytes(blob);

  const headerByte = data[0]!;
  const header = fieldOf(
    {
      major: headerByte >> PF.MAJOR_SHIFT,
      minor: (headerByte >> PF.MINOR_SHIFT) & PF.MINOR_MASK,
      isSelectorless: (headerByte & PF.FLAG_NO_SELECTOR) !== 0,
    },
    0,
    PF.SELECTOR_OFFSET,
  );
  const descLength = uintField(data, PF.DESC_LENGTH_OFFSET, PF.DESC_LENGTH_OFFSET + PF.DESC_LENGTH_SIZE);
  const groupCountOffset = PF.DESC_OFFSET + descLength.value;
  const descriptor = inspectDescriptor(data.subarray(PF.DESC_OFFSET, groupCountOffset), PF.DESC_OFFSET);
  const groupCount = uintField(data, groupCountOffset, groupCountOffset + PF.GROUP_COUNT_SIZE);

  const groups: DecodedGroup[] = [];
  let offset = groupCount.span.end;
  for (let groupIndex = 0; groupIndex < groupCount.value; groupIndex++) {
    const ruleCount = uintField(data, offset, offset + PF.GROUP_RULECOUNT_SIZE);
    const groupSize = uintField(data, ruleCount.span.end, offset + PF.GROUP_HEADER_SIZE);
    const groupEnd = groupSize.span.end + groupSize.value;
    const rules: DecodedRule[] = [];
    let ruleOffset = groupSize.span.end;
    for (let ruleIndex = 0; ruleIndex < ruleCount.value; ruleIndex++) {
      const rule = inspectRule(data, ruleOffset);
      rules.push(rule);
      ruleOffset = rule.span.end;
    }
    groups.push({ ruleCount, groupSize, rules, span: { start: offset, end: groupEnd } });
    offset = groupEnd;
  }

  return {
    header,
    selector: hexField(data, PF.SELECTOR_OFFSET, PF.SELECTOR_OFFSET + PF.SELECTOR_SIZE),
    descLength,
    descriptor,
    groupCount,
    groups,
    span: { start: 0, end: data.length },
  };
}

/** Inspect the root rule at `ruleOffset`. */
function inspectRule(data: Uint8Array, ruleOffset: number): DecodedRule {
  if (data[ruleOffset + PF.RULE_SCOPE_OFFSET] !== Scope.LOOP) return inspectTest(data, ruleOffset);

  const size = uintField(data, ruleOffset, ruleOffset + PF.RULE_SIZE_SIZE);
  const quantifierOffset = ruleOffset + PF.RULE_QUANTIFIER_OFFSET;
  const quantifier = data[quantifierOffset]!;
  if (!isQuantifierCode(quantifier)) {
    throw new CallciumError("UNKNOWN_QUANTIFIER", `Unknown quantifier value ${quantifier}`, ruleOffset);
  }
  const depthOffset = ruleOffset + PF.LOOP_DEPTH_OFFSET;
  const pathDepth = uintField(data, depthOffset, depthOffset + PF.RULE_DEPTH_SIZE);
  const path = hexField(data, pathDepth.span.end, pathDepth.span.end + pathDepth.value * PF.PATH_STEP_SIZE);
  const hint = inspectFrameHint(data, path.span.end);
  const ruleCount = uintField(data, hint.span.end, hint.span.end + PF.GROUP_RULECOUNT_SIZE);
  const body: DecodedTest[] = [];
  let testOffset = ruleCount.span.end;
  for (let bodyIndex = 0; bodyIndex < ruleCount.value; bodyIndex++) {
    const test = inspectTest(data, testOffset);
    body.push(test);
    testOffset = test.span.end;
  }
  const scopeOffset = ruleOffset + PF.RULE_SCOPE_OFFSET;
  return {
    ruleSize: size,
    scope: fieldOf(Scope.LOOP, scopeOffset, scopeOffset + PF.RULE_SCOPE_SIZE),
    quantifier: fieldOf(quantifier, quantifierOffset, quantifierOffset + PF.RULE_QUANTIFIER_SIZE),
    pathDepth,
    path,
    hint,
    ruleCount,
    body,
    span: { start: ruleOffset, end: ruleOffset + size.value },
  };
}

/** Inspect the test or context test at `ruleOffset`. */
function inspectTest(data: Uint8Array, ruleOffset: number): DecodedTest {
  const size = uintField(data, ruleOffset, ruleOffset + PF.RULE_SIZE_SIZE);
  const scopeOffset = ruleOffset + PF.RULE_SCOPE_OFFSET;
  const testScope = data[scopeOffset]!;
  if (testScope !== Scope.CONTEXT && testScope !== Scope.CALLDATA) {
    throw new CallciumError("UNKNOWN_SCOPE", `Unknown scope value ${testScope}`, ruleOffset);
  }
  const pathDepth = uintField(data, ruleOffset + PF.RULE_DEPTH_OFFSET, ruleOffset + PF.RULE_PATH_OFFSET);
  const pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
  let path: Field<Hex>;
  let hint: DecodedHint | undefined;
  let targetType: number;
  if (testScope === Scope.CONTEXT) {
    path = hexField(data, pathStart, pathStart + PF.PROPERTY_ID_SIZE);
    targetType = contextPropertyType(readU16(data, pathStart));
  } else {
    path = hexField(data, pathStart, pathStart + pathDepth.value * PF.PATH_STEP_SIZE);
    hint = inspectTestHint(data, path.span.end);
    targetType = hint.typeCode.value;
  }
  const opOffset = hint === undefined ? path.span.end : hint.span.end;
  const opCode = uintField(data, opOffset, opOffset + PF.RULE_OPCODE_SIZE);
  const dataLength = uintField(data, opCode.span.end, opCode.span.end + PF.RULE_DATALENGTH_SIZE);
  return {
    ruleSize: size,
    scope: fieldOf(testScope, scopeOffset, scopeOffset + PF.RULE_SCOPE_SIZE),
    pathDepth,
    path,
    ...(hint !== undefined && { hint }),
    targetType,
    opCode,
    dataLength,
    data: hexField(data, dataLength.span.end, dataLength.span.end + dataLength.value),
    operator: readOperator(data, opOffset, targetType),
    span: { start: ruleOffset, end: ruleOffset + size.value },
  };
}

/** Inspect the header and hops of the hint at `hintOffset`, with the offset past its last hop. */
function inspectHops(
  data: Uint8Array,
  hintOffset: number,
): { hopCount: Field<number>; hops: DecodedHop[]; end: number } {
  const hopCount = uintField(data, hintOffset, hintOffset + PF.HINT_HEADER_SIZE);
  const hops: DecodedHop[] = [];
  let offset = hopCount.span.end;
  for (let hopIndex = 0; hopIndex < hopCount.value; hopIndex++) {
    const index = uintField(data, offset + PF.HINT_HOP_INDEX_OFFSET, offset + PF.HINT_HOP_META_OFFSET);
    hops.push({
      kind: index.value === PF.HINT_NO_INDEX ? "plain" : "element",
      delta: uintField(data, offset, offset + PF.HINT_HOP_INDEX_OFFSET),
      index,
      meta: metaField(data, offset + PF.HINT_HOP_META_OFFSET, offset + PF.HINT_HOP_SIZE),
      span: { start: offset, end: offset + PF.HINT_HOP_SIZE },
    });
    offset += PF.HINT_HOP_SIZE;
  }
  return { hopCount, hops, end: offset };
}

/** Inspect the test hint at `hintOffset`. */
function inspectTestHint(data: Uint8Array, hintOffset: number): DecodedHint {
  const { hopCount, hops, end: target } = inspectHops(data, hintOffset);
  return {
    hopCount,
    hops,
    targetDelta: uintField(data, target, target + PF.HINT_TARGET_META_OFFSET),
    targetMeta: metaField(data, target + PF.HINT_TARGET_META_OFFSET, target + PF.HINT_TARGET_TYPECODE_OFFSET),
    typeCode: uintField(data, target + PF.HINT_TARGET_TYPECODE_OFFSET, target + PF.HINT_TARGET_SIZE),
    span: { start: hintOffset, end: target + PF.HINT_TARGET_SIZE },
  };
}

/** Inspect the frame hint at `hintOffset`. */
function inspectFrameHint(data: Uint8Array, hintOffset: number): DecodedFrameHint {
  const { hopCount, hops, end: frame } = inspectHops(data, hintOffset);
  return {
    hopCount,
    hops,
    arrayDelta: uintField(data, frame, frame + PF.HINT_FRAME_COUNT_OFFSET),
    count: uintField(data, frame + PF.HINT_FRAME_COUNT_OFFSET, frame + PF.HINT_FRAME_META_OFFSET),
    meta: metaField(data, frame + PF.HINT_FRAME_META_OFFSET, frame + PF.HINT_FRAME_PREFIX_SIZE),
    span: { start: hintOffset, end: frame + PF.HINT_FRAME_PREFIX_SIZE },
  };
}

/** A value with the bytes from `start` to `end` that contain it. */
function fieldOf<T>(value: T, start: number, end: number): Field<T> {
  return { value, span: { start, end } };
}

/** The bytes from `start` to `end` as a hex field. */
function hexField(data: Uint8Array, start: number, end: number): Field<Hex> {
  return fieldOf(toHex(data, start, end), start, end);
}

/** The big-endian unsigned integer the bytes from `start` to `end` represent. */
function uintField(data: Uint8Array, start: number, end: number): Field<number> {
  let value = 0;
  for (let offset = start; offset < end; offset++) value = value * 256 + data[offset]!;
  return fieldOf(value, start, end);
}

/** The meta word the bytes from `start` to `end` represent. */
function metaField(data: Uint8Array, start: number, end: number): Field<ArrayMeta> {
  const meta = readU16(data, start);
  const value = {
    isElementDynamic: (meta & PF.HINT_META_ELEM_DYNAMIC) !== 0,
    isDynamicArray: (meta & PF.HINT_META_DYNAMIC_ARRAY) !== 0,
    strideWords: meta & PF.HINT_META_STRIDE_MASK,
  };
  return fieldOf(value, start, end);
}

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** The `pathDepth` of a context test, whose path is its property ID. */
const CONTEXT_PATH_DEPTH = 1;

/** Sort items ascending by their key bytes and drop repeats. */
function sortDedupe<T>(items: T[], key: (item: T) => Uint8Array): T[] {
  const sorted = items.toSorted((first, second) => compareBytes(key(first), key(second)));
  return sorted.filter((item, index) => index === 0 || compareBytes(key(item), key(sorted[index - 1]!)) !== 0);
}

/** Compare two byte arrays lexicographically. A prefix sorts first. */
function compareBytes(first: Uint8Array, second: Uint8Array): number {
  const length = Math.min(first.length, second.length);
  for (let i = 0; i < length; i++) {
    if (first[i] !== second[i]) return first[i]! - second[i]!;
  }
  return first.length - second.length;
}

/** Whether the rule is an `ALL` loop. */
function isAllLoop(rule: Rule): rule is LoopRule {
  return rule.scope === Scope.LOOP && rule.quantifier === LoopQuantifier.ALL;
}

/** Whether the rule is an `ANY` loop whose body contains a calldata test, which gives up its context tests. */
function hoists(rule: Rule): rule is LoopRule {
  return (
    rule.scope === Scope.LOOP &&
    rule.quantifier === LoopQuantifier.ANY &&
    rule.body.some((test) => test.scope === Scope.CALLDATA)
  );
}

/** Return the comparison equal to `NOT comparison`, or undefined where none is. */
function negationOf(comparison: number): number | undefined {
  switch (comparison) {
    case Op.GT:
      return Op.LTE;
    case Op.LT:
      return Op.GTE;
    case Op.GTE:
      return Op.LT;
    case Op.LTE:
      return Op.GT;
    case Op.BITMASK_ANY:
      return Op.BITMASK_NONE;
    case Op.BITMASK_NONE:
      return Op.BITMASK_ANY;
    case Op.LENGTH_GT:
      return Op.LENGTH_LTE;
    case Op.LENGTH_LT:
      return Op.LENGTH_GTE;
    case Op.LENGTH_GTE:
      return Op.LENGTH_LT;
    case Op.LENGTH_LTE:
      return Op.LENGTH_GT;
    default:
      return undefined;
  }
}

/**
 * Return the comparison that holds with subject and operand exchanged, or undefined where a context operand takes
 * none.
 */
function swapOf(comparison: number): number | undefined {
  switch (comparison) {
    case Op.EQ:
      return Op.EQ;
    case Op.GT:
      return Op.LT;
    case Op.LT:
      return Op.GT;
    case Op.GTE:
      return Op.LTE;
    case Op.LTE:
      return Op.GTE;
    default:
      return undefined;
  }
}

/** Require a value to fit the big-endian field of `byteWidth` bytes. */
function requireFieldFits(value: number, byteWidth: number, code: CallciumErrorCode, subject: string): void {
  const max = fieldMax(byteWidth);
  if (value > max) throw new CallciumError(code, `${subject} ${value} exceeds maximum ${max}`);
}

/** Return `value` as a 2-byte big-endian field. */
function be16(value: number): Uint8Array {
  const field = new Uint8Array(2);
  writeBE16(field, 0, value);
  return field;
}

/** Return `value` as a 4-byte big-endian field. */
function be32(value: number): Uint8Array {
  const field = new Uint8Array(4);
  writeBE32(field, 0, value);
  return field;
}

/** Encode policies in canonical form, and decode and inspect policy blobs. */
export const PolicyCoder = { encode, decode, inspect };

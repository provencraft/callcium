import { hexToBytes, bytesToHex, readU16, readU32, bigintToHex } from "./bytes";
import { loadWord, readPointer } from "./calldata-reader";
import {
  PolicyFormat as PF,
  Scope,
  MAX_CONTEXT_PROPERTY_ID,
  Limits,
  Op,
  TypeCode,
  classifyTypeCode,
  lookupContextProperty,
} from "./constants";
import { CallciumError, PolicyViolationError } from "./errors";
import { applyOperator, toBigInt, isLengthOp, isLengthValidType, canonicalize } from "./operators";
import { decodePolicy } from "./policy-coder";

import type { ReadResult } from "./calldata-reader";
import type {
  Context,
  DecodedRule,
  EnforceResult,
  Hex,
  NavigationViolationCode,
  Span,
  Violation,
  ViolationCode,
} from "./types";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** Violations that abort evaluation instead of failing only their group (spec §9.3). */
const ABORT_VIOLATION_CODES: ReadonlySet<ViolationCode> = new Set<ViolationCode>([
  "CALLDATA_OUT_OF_BOUNDS",
  "ARRAY_INDEX_OUT_OF_BOUNDS",
  "NON_CANONICAL_VALUE",
  "QUANTIFIER_LIMIT_EXCEEDED",
]);

/** Convert a hex address to a 256-bit bigint (zero-padded to 32 bytes). */
function addressToBigInt(hex: string): bigint {
  const bytes = hexToBytes(hex);
  const padded = new Uint8Array(32);
  padded.set(bytes, 32 - bytes.length);
  return toBigInt(padded, 0);
}

///////////////////////////////////////////////////////////////////////////
// Public API
///////////////////////////////////////////////////////////////////////////

/**
 * Check a policy against ABI-encoded call data without throwing on violations.
 * @param policy - Binary policy blob as 0x-prefixed hex string.
 * @param callData - ABI-encoded call data as 0x-prefixed hex string.
 * @param context - Optional execution context for context-scoped rules.
 * @returns Pass with matched group index, or fail with one violation per evaluated failing group.
 * @throws {CallciumError} If the policy blob is structurally malformed.
 */
function check(policy: Hex, callData: Hex, context?: Context): EnforceResult {
  const { policy: decoded, data: policyBytes } = decodePolicy(policy);
  const callDataBytes = hexToBytes(callData);

  // Selector check.
  if (!decoded.isSelectorless) {
    if (callDataBytes.length < 4) {
      return {
        ok: false,
        violations: [{ code: "MISSING_SELECTOR" }],
      };
    }
    const expectedSelector = decoded.selector.value;
    const actualSelector = bytesToHex(callDataBytes.subarray(0, 4));
    if (actualSelector !== expectedSelector) {
      return {
        ok: false,
        violations: [
          {
            code: "SELECTOR_MISMATCH",
            resolvedValue: actualSelector,
            expectedValue: expectedSelector,
          },
        ],
      };
    }
  }

  const baseOffset = decoded.isSelectorless ? 0 : PF.SELECTOR_SIZE;

  // Evaluate groups with OR semantics.
  const allViolations: Violation[] = [];

  for (let groupIndex = 0; groupIndex < decoded.groups.length; groupIndex++) {
    const group = decoded.groups[groupIndex]!;
    let groupFailed = false;

    for (let ruleIndex = 0; ruleIndex < group.rules.length; ruleIndex++) {
      const rule = group.rules[ruleIndex]!;
      const violation = evaluateRule(rule, policyBytes, callDataBytes, baseOffset, groupIndex, ruleIndex, context);
      if (violation !== null) {
        allViolations.push(violation);
        if (ABORT_VIOLATION_CODES.has(violation.code)) {
          // Abort violations reject the policy outright; later groups are not consulted (spec §9.3).
          return { ok: false, violations: allViolations };
        }
        groupFailed = true;
        break;
      }
    }

    if (!groupFailed) {
      return { ok: true, matchedGroup: groupIndex };
    }
  }

  return { ok: false, violations: allViolations };
}

/**
 * Enforce a policy against ABI-encoded call data, throwing on violation.
 * @param policy - Binary policy blob as 0x-prefixed hex string.
 * @param callData - ABI-encoded call data as 0x-prefixed hex string.
 * @param context - Optional execution context for context-scoped rules.
 * @throws {PolicyViolationError} If the policy rejects the call data.
 * @throws {CallciumError} If the policy blob is structurally malformed.
 */
function enforce(policy: Hex, callData: Hex, context?: Context): void {
  const result = check(policy, callData, context);
  if (!result.ok) {
    throw new PolicyViolationError(result.violations);
  }
}

///////////////////////////////////////////////////////////////////////////
// Rule evaluation
///////////////////////////////////////////////////////////////////////////

/** Read the blob bytes a decoded field spans. */
function fieldBytes(policyBytes: Uint8Array, field: { span: Span }): Uint8Array {
  return policyBytes.subarray(field.span.start, field.span.end);
}

/** Evaluate a single rule against calldata or context, returning a violation or null on pass. */
function evaluateRule(
  rule: DecodedRule,
  policyBytes: Uint8Array,
  callDataBytes: Uint8Array,
  baseOffset: number,
  groupIndex: number,
  ruleIndex: number,
  context?: Context,
): Violation | null {
  const opCode = rule.opCode.value;
  const operandData = fieldBytes(policyBytes, rule.data);

  const scope = rule.scope.value;
  if (scope === Scope.CONTEXT) {
    const pathBytes = fieldBytes(policyBytes, rule.path);
    return evaluateContextRule(pathBytes, opCode, operandData, groupIndex, ruleIndex, rule.path.value, context);
  }

  // The hint addresses the target on its own; path bytes carry no evaluation role.
  if (rule.hint === undefined) {
    throw new CallciumError("MALFORMED_HINT", "Calldata rule carries no hint block");
  }
  return evaluateCalldataRule(
    fieldBytes(policyBytes, rule.hint),
    callDataBytes,
    baseOffset,
    opCode,
    operandData,
    groupIndex,
    ruleIndex,
    rule.path.value,
    context,
  );
}

/**
 * Resolve an EQ_CTX operand word to the referenced context property's value as a raw word.
 * Returns the missing property's type code when the context does not supply it.
 */
function resolveContextOperand(operandData: Uint8Array, context?: Context): bigint | { ctxTypeCode: number } {
  const propInfo = lookupContextProperty(Number(toBigInt(operandData, 0)));
  const value = context?.[propInfo.contextKey];
  if (value === undefined) return { ctxTypeCode: propInfo.typeCode };
  return typeof value === "string" ? addressToBigInt(value) : value;
}

///////////////////////////////////////////////////////////////////////////
// Hint chain resolution
///////////////////////////////////////////////////////////////////////////

/** Fields of a hint's target block. */
type TargetBlock = {
  targetDelta: number;
  targetMeta: number;
  typeCode: number;
};

/** Read the target block at `targetOffset` in the hint. */
function readTargetBlock(hint: Uint8Array, targetOffset: number): TargetBlock {
  return {
    targetDelta: readU32(hint, targetOffset),
    targetMeta: readU16(hint, targetOffset + PF.HINT_TARGET_META_OFFSET),
    typeCode: hint[targetOffset + PF.HINT_TARGET_TYPECODE_OFFSET]!,
  };
}

/** Advance `from` by the offset word at `at`. */
function follow(callData: Uint8Array, from: number, at: number): ReadResult<number> {
  const word = readPointer(callData, at);
  if (typeof word !== "number") return word;
  return from + word;
}

/** Follow `hopCount` hop entries from `base` and return the calldata offset they reach. */
function chainResolve(
  hint: Uint8Array,
  callData: Uint8Array,
  base: number,
  hopsOffset: number,
  hopCount: number,
): ReadResult<number> {
  for (let i = 0; i < hopCount; i++) {
    const hop = hopsOffset + i * PF.HINT_HOP_SIZE;
    const index = readU16(hint, hop + PF.HINT_HOP_INDEX_OFFSET);

    if (index === PF.HINT_NO_INDEX) {
      const next = follow(callData, base, base + readU32(hint, hop));
      if (typeof next !== "number") return next;
      base = next;
      continue;
    }

    const meta = readU16(hint, hop + PF.HINT_HOP_META_OFFSET);
    let elems = base;
    if ((meta & PF.HINT_META_DYNAMIC_ARRAY) !== 0) {
      const length = readPointer(callData, elems);
      if (typeof length !== "number") return length;
      if (index >= length) return { code: "ARRAY_INDEX_OUT_OF_BOUNDS" };
      elems += 32;
    }

    const slot = elems + index * (meta & PF.HINT_META_STRIDE_MASK) * 32;
    if ((meta & PF.HINT_META_ELEM_DYNAMIC) !== 0) {
      const next = follow(callData, elems, slot);
      if (typeof next !== "number") return next;
      base = next;
    } else {
      base = slot;
    }
  }
  return base;
}

///////////////////////////////////////////////////////////////////////////
// Target evaluation
///////////////////////////////////////////////////////////////////////////

type TargetResult =
  | { passed: boolean; value: bigint }
  | { error: NavigationViolationCode }
  | { error: "NON_CANONICAL_VALUE"; value: bigint }
  | { error: "MISSING_CONTEXT"; ctxTypeCode: number };

/**
 * Load the value at a resolved target offset and apply the operator.
 *
 * `value` is normalised at the decision point: length operators yield the byte/element
 * count; scalar operators preserve the full 32-byte ABI word, keeping left-aligned `bytesN`
 * decodable. A passing target allocates no string.
 */
function evalTarget(
  callData: Uint8Array,
  target: number,
  block: TargetBlock,
  opCode: number,
  operandData: Uint8Array,
  context?: Context,
): TargetResult {
  const typeCode = block.typeCode;

  // A dynamic target's chain ends at its payload, so the word there is the declared length.
  if (isLengthValidType(typeCode)) {
    if (!isLengthOp(opCode)) {
      throw new CallciumError("OPERATOR_TARGET_MISMATCH", "Value operator on a target without a scalar word.");
    }
    const length = readPointer(callData, target);
    if (typeof length !== "number") return { error: length.code };

    // The declared payload of `length` items must lie within calldata past the length word.
    const stride = typeCode === TypeCode.DYNAMIC_ARRAY ? (block.targetMeta & PF.HINT_META_STRIDE_MASK) * 32 : 1;
    const room = callData.length - (target + 32);
    if (stride !== 0 && length > Math.floor(room / stride)) return { error: "CALLDATA_OUT_OF_BOUNDS" };

    const passed = applyOperator(opCode, 0n, length, operandData, typeCode);
    return { passed, value: BigInt(length) };
  }

  if (classifyTypeCode(typeCode).typeClass !== "elementary") {
    throw new CallciumError("OPERATOR_TARGET_MISMATCH", "Operator target does not carry a scalar word.");
  }
  const word = loadWord(callData, target);
  if (!(word instanceof Uint8Array)) return { error: word.code };

  const value = toBigInt(word, 0);
  if (canonicalize(value, typeCode) !== value) {
    return { error: "NON_CANONICAL_VALUE", value };
  }

  if ((opCode & ~Op.NOT) === Op.EQ_CTX) {
    const operand = resolveContextOperand(operandData, context);
    if (typeof operand !== "bigint") return { error: "MISSING_CONTEXT", ctxTypeCode: operand.ctxTypeCode };
    const passed = (value === operand) !== ((opCode & Op.NOT) !== 0);
    return { passed, value };
  }

  const passed = applyOperator(opCode, value, 32, operandData, typeCode);
  return { passed, value };
}

///////////////////////////////////////////////////////////////////////////
// Calldata rule evaluation
///////////////////////////////////////////////////////////////////////////

/** Coordinates and rule metadata shared by every violation a calldata rule can produce. */
type RuleFrame = {
  group: number;
  rule: number;
  path: Hex;
  opCode: number;
  operandData: Uint8Array;
  typeCode: number;
};

/** Build a navigation violation for a read the enforcer cannot perform. */
function navigationViolation(frame: RuleFrame, code: NavigationViolationCode, elementIndex?: number): Violation {
  return {
    group: frame.group,
    rule: frame.rule,
    code,
    scope: Scope.CALLDATA,
    path: frame.path,
    opCode: frame.opCode,
    operandData: bytesToHex(frame.operandData),
    typeCode: frame.typeCode,
    ...(elementIndex !== undefined && { elementIndex }),
  };
}

/** Convert a failed or erroring target result into its violation. Passing results map to null. */
function targetViolation(frame: RuleFrame, result: TargetResult, elementIndex?: number): Violation | null {
  if ("error" in result) {
    if (result.error === "MISSING_CONTEXT") {
      return {
        group: frame.group,
        rule: frame.rule,
        code: result.error,
        scope: Scope.CALLDATA,
        path: frame.path,
        opCode: frame.opCode,
        operandData: bytesToHex(frame.operandData),
        typeCode: result.ctxTypeCode,
      };
    }
    if (result.error === "NON_CANONICAL_VALUE") {
      return {
        group: frame.group,
        rule: frame.rule,
        code: result.error,
        scope: Scope.CALLDATA,
        path: frame.path,
        opCode: frame.opCode,
        operandData: bytesToHex(frame.operandData),
        typeCode: frame.typeCode,
        resolvedValue: bigintToHex(result.value),
        ...(elementIndex !== undefined && { elementIndex }),
      };
    }
    return navigationViolation(frame, result.error, elementIndex);
  }

  if (result.passed) return null;
  return {
    group: frame.group,
    rule: frame.rule,
    code: "VALUE_MISMATCH",
    scope: Scope.CALLDATA,
    path: frame.path,
    opCode: frame.opCode,
    operandData: bytesToHex(frame.operandData),
    typeCode: frame.typeCode,
    resolvedValue: bigintToHex(result.value),
    ...(elementIndex !== undefined && { elementIndex }),
  };
}

/** Evaluate a calldata rule by resolving its target through the hint block. */
function evaluateCalldataRule(
  hint: Uint8Array,
  callDataBytes: Uint8Array,
  baseOffset: number,
  opCode: number,
  operandData: Uint8Array,
  groupIndex: number,
  ruleIndex: number,
  pathHex: Hex,
  context?: Context,
): Violation | null {
  const header = hint[0]!;
  const hopCount = header & PF.HINT_HOP_COUNT_MASK;
  const kind = header >> PF.HINT_KIND_SHIFT;
  const hopsOffset = PF.HINT_HEADER_SIZE;

  if (kind !== PF.HINT_KIND_NONE) {
    return evaluateQuantified(
      hint,
      callDataBytes,
      baseOffset,
      kind,
      hopsOffset,
      hopCount,
      opCode,
      operandData,
      groupIndex,
      ruleIndex,
      pathHex,
      context,
    );
  }

  const block = readTargetBlock(hint, hopsOffset + hopCount * PF.HINT_HOP_SIZE);
  const frame: RuleFrame = {
    group: groupIndex,
    rule: ruleIndex,
    path: pathHex,
    opCode,
    operandData,
    typeCode: block.typeCode,
  };

  const base = chainResolve(hint, callDataBytes, baseOffset, hopsOffset, hopCount);
  if (typeof base !== "number") return navigationViolation(frame, base.code);

  return targetViolation(
    frame,
    evalTarget(callDataBytes, base + block.targetDelta, block, opCode, operandData, context),
  );
}

///////////////////////////////////////////////////////////////////////////
// Quantifier evaluation
///////////////////////////////////////////////////////////////////////////

/** Evaluate a quantified rule by iterating over array elements with ALL/ANY semantics. */
function evaluateQuantified(
  hint: Uint8Array,
  callDataBytes: Uint8Array,
  baseOffset: number,
  kind: number,
  hopsOffset: number,
  hopCount: number,
  opCode: number,
  operandData: Uint8Array,
  groupIndex: number,
  ruleIndex: number,
  pathHex: Hex,
  context?: Context,
): Violation | null {
  const frameOffset = hopsOffset + hopCount * PF.HINT_HOP_SIZE;
  const suffixHeaderOffset = frameOffset + PF.HINT_FRAME_PREFIX_SIZE;
  const suffixHopCount = hint[suffixHeaderOffset]! & PF.HINT_HOP_COUNT_MASK;
  const suffixHopsOffset = suffixHeaderOffset + PF.HINT_HEADER_SIZE;

  const block = readTargetBlock(hint, suffixHopsOffset + suffixHopCount * PF.HINT_HOP_SIZE);
  const frame: RuleFrame = {
    group: groupIndex,
    rule: ruleIndex,
    path: pathHex,
    opCode,
    operandData,
    typeCode: block.typeCode,
  };

  const chained = chainResolve(hint, callDataBytes, baseOffset, hopsOffset, hopCount);
  if (typeof chained !== "number") return navigationViolation(frame, chained.code);

  const arrayDelta = readU32(hint, frameOffset);
  let elems = chained + arrayDelta;

  // A frame declaring no count spans a dynamic array, whose length word precedes its elements.
  let count = readU16(hint, frameOffset + PF.HINT_FRAME_COUNT_OFFSET);
  if (count === 0) {
    const length = readPointer(callDataBytes, elems);
    if (typeof length !== "number") return navigationViolation(frame, length.code);
    count = length;
    elems += 32;
  }

  if (count > Limits.MAX_QUANTIFIED_ARRAY_LENGTH) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "QUANTIFIER_LIMIT_EXCEEDED",
      scope: Scope.CALLDATA,
      path: pathHex,
      resolvedValue: bigintToHex(BigInt(count)),
    };
  }

  const isUniversal = kind === PF.HINT_KIND_ALL;
  if (count === 0) {
    if (isUniversal) return null;
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "QUANTIFIER_EMPTY_ARRAY",
      scope: Scope.CALLDATA,
      path: pathHex,
    };
  }

  const meta = readU16(hint, frameOffset + PF.HINT_FRAME_META_OFFSET);
  const elemStride = (meta & PF.HINT_META_STRIDE_MASK) * 32;
  const elemIsDynamic = (meta & PF.HINT_META_ELEM_DYNAMIC) !== 0;

  for (let elemIndex = 0; elemIndex < count; elemIndex++) {
    const slot = elems + elemIndex * elemStride;
    let elem: number = slot;
    if (elemIsDynamic) {
      const followed = follow(callDataBytes, elems, slot);
      // Navigation failures abort under every quantifier: calldata the enforcer cannot read is
      // not an element that merely fails the operator (spec §9.3).
      if (typeof followed !== "number") return navigationViolation(frame, followed.code, elemIndex);
      elem = followed;
    }

    let base: number = elem;
    if (suffixHopCount > 0) {
      const chainedElem = chainResolve(hint, callDataBytes, elem, suffixHopsOffset, suffixHopCount);
      if (typeof chainedElem !== "number") return navigationViolation(frame, chainedElem.code, elemIndex);
      base = chainedElem;
    }

    const applied = evalTarget(callDataBytes, base + block.targetDelta, block, opCode, operandData, context);
    if ("error" in applied) {
      // Error results end the rule whatever the quantifier: a later element cannot rescue
      // calldata the enforcer cannot read (abort effects, spec §9.3), and a missing context
      // property is missing for every element alike (group-local).
      return targetViolation(frame, applied, elemIndex);
    }

    if (applied.passed) {
      // Existential quantification passes on the first passing element.
      if (!isUniversal) return null;
    } else if (isUniversal) {
      return targetViolation(frame, applied, elemIndex);
    }
  }

  if (isUniversal) return null;
  // Existential (ANY) failure: every element rejected the constraint.
  return {
    group: groupIndex,
    rule: ruleIndex,
    code: "VALUE_MISMATCH",
    scope: Scope.CALLDATA,
    path: pathHex,
    opCode,
    operandData: bytesToHex(operandData),
    typeCode: block.typeCode,
  };
}

///////////////////////////////////////////////////////////////////////////
// Context rule evaluation
///////////////////////////////////////////////////////////////////////////

/** Evaluate a context-scoped rule by resolving the property from the execution context. */
function evaluateContextRule(
  pathBytes: Uint8Array,
  opCode: number,
  operandData: Uint8Array,
  groupIndex: number,
  ruleIndex: number,
  pathHex: Hex,
  context?: Context,
): Violation | null {
  const propertyId = readU16(pathBytes, 0);

  if (propertyId > MAX_CONTEXT_PROPERTY_ID) {
    throw new CallciumError(
      "UNKNOWN_CONTEXT_PROPERTY",
      `Unknown context property ID 0x${propertyId.toString(16).padStart(4, "0")}`,
    );
  }

  const propInfo = lookupContextProperty(propertyId);
  const contextValue = context?.[propInfo.contextKey];

  if (contextValue === undefined) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "MISSING_CONTEXT",
      scope: Scope.CONTEXT,
      path: pathHex,
      typeCode: propInfo.typeCode,
    };
  }

  let value: bigint;
  if (typeof contextValue === "string") {
    value = addressToBigInt(contextValue);
  } else {
    value = contextValue;
  }

  let result: boolean;
  if ((opCode & ~Op.NOT) === Op.EQ_CTX) {
    const operand = resolveContextOperand(operandData, context);
    if (typeof operand !== "bigint") {
      return {
        group: groupIndex,
        rule: ruleIndex,
        code: "MISSING_CONTEXT",
        scope: Scope.CONTEXT,
        path: pathHex,
        opCode,
        operandData: bytesToHex(operandData),
        typeCode: operand.ctxTypeCode,
      };
    }
    result = (value === operand) !== ((opCode & Op.NOT) !== 0);
  } else {
    result = applyOperator(opCode, value, 32, operandData, propInfo.typeCode);
  }

  if (!result) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "VALUE_MISMATCH",
      scope: Scope.CONTEXT,
      path: pathHex,
      opCode,
      operandData: bytesToHex(operandData),
      typeCode: propInfo.typeCode,
      resolvedValue: bigintToHex(value),
    };
  }

  return null;
}

/** Check and enforce policies against ABI-encoded call data. */
export const PolicyEnforcer = { check, enforce };

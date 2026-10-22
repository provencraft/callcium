import { bigintToHex, hexToBytes, readU16, readU32, toAddress, toHex } from "./bytes";
import { loadWord, readLength, readPointer } from "./calldata-reader";
import {
  comparisonOf,
  findContextProperty,
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
  type ScopeCode,
} from "./constants";
import { CallciumError, PolicyViolationError } from "./errors";
import {
  canonicalize,
  contextPropertyType,
  hasCalldataLength,
  isSigned,
  LENGTH_TYPE,
  loadOperand,
  operandWidth,
  readOperator,
  toBigInt,
} from "./operators";

import type { ReadResult } from "./calldata-reader";
import type { Context, Hex } from "./types";
import type { DecodedOperator, EnforceResult, Violation, ViolationCode } from "./types";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** Whether a violation ends evaluation or fails only its group (a loop body at the element it read). */
export const VIOLATION_EFFECT = {
  VALUE_MISMATCH: "groupLocal",
  NON_CANONICAL_VALUE: "abort",
  SELECTOR_MISMATCH: "abort",
  MISSING_SELECTOR: "abort",
  CALLDATA_OUT_OF_BOUNDS: "abort",
  ARRAY_INDEX_OUT_OF_BOUNDS: "groupLocal",
  MISSING_CONTEXT: "groupLocal",
  QUANTIFIER_LIMIT_EXCEEDED: "abort",
  QUANTIFIER_NO_MATCH: "groupLocal",
} as const satisfies Record<ViolationCode, "abort" | "groupLocal">;

/** The value of each context property by ID, or undefined where the context does not supply it. */
type ContextWords = readonly (bigint | undefined)[];

/** What every evaluation step reads: the blob, the calldata and the context, and the operators parsed so far. */
type Enforcement = {
  policy: Uint8Array;
  callData: Uint8Array;
  context: ContextWords;
  /** Each operator a violation has named, by the offset of its code. */
  operators: Map<number, DecodedOperator>;
};

/**
 * Read the supplied context as the 32-byte words that carry its properties, by property ID.
 * @throws {CallciumError} When a property is not of its declared type, or an address is not 20 bytes of hex. When an
 * integer does not fit a 32-byte word.
 */
function contextWords(context: Context | undefined): ContextWords {
  const words: (bigint | undefined)[] = [];
  for (let propertyId = 0; propertyId <= MAX_CONTEXT_PROPERTY_ID; propertyId++) {
    const info = findContextProperty(propertyId)!;
    const value: unknown = context?.[info.contextKey];
    words.push(value === undefined ? undefined : contextValueToWord(info.contextKey, info.typeCode, value));
  }
  return words;
}

/** Read a supplied context value as the 32-byte word that carries it. */
function contextValueToWord(contextKey: string, typeCode: number, value: unknown): bigint {
  if (typeCode === TypeCode.ADDRESS) {
    if (typeof value !== "string") {
      throw new CallciumError("MALFORMED_CONTEXT_VALUE", `Context property ${contextKey} is not an address string`);
    }
    return BigInt(toAddress(value));
  }
  if (typeof value !== "bigint") {
    throw new CallciumError("MALFORMED_CONTEXT_VALUE", `Context property ${contextKey} is not a bigint`);
  }
  if (BigInt.asUintN(256, value) !== value) {
    throw new CallciumError(
      "CONTEXT_VALUE_OVERFLOW",
      `Context value ${value} is outside the range a 32-byte word represents`,
    );
  }
  return value;
}

///////////////////////////////////////////////////////////////////////////
// Public API
///////////////////////////////////////////////////////////////////////////

/**
 * Check a policy against ABI-encoded call data without throwing on violations. Requires a policy blob that passes
 * storage validation. The outcome on any other blob past its header is undefined.
 * @param policy - Binary policy blob as 0x-prefixed hex string.
 * @param callData - ABI-encoded call data as 0x-prefixed hex string.
 * @param context - Optional execution context for context-scoped rules.
 * @returns Pass with matched group index, or fail with one violation per evaluated failing group.
 * @throws {CallciumError} If the policy blob is shorter than its fixed prefix or of an unsupported format version.
 * If the policy or call data is not valid hex.
 * If a context value is not of its property's type or does not fit a 32-byte word.
 */
function check(policy: Hex, callData: Hex, context?: Context): EnforceResult {
  const data = hexToBytes(policy);
  if (data.length < PF.DESC_OFFSET) {
    throw new CallciumError("MALFORMED_HEADER", "Policy blob is too short");
  }
  const headerByte = data[0]!;
  const major = headerByte >> PF.MAJOR_SHIFT;
  if (major !== PF.MAJOR) {
    throw new CallciumError("UNSUPPORTED_VERSION", `Major version ${major} is not supported (expected ${PF.MAJOR})`);
  }
  const minor = (headerByte >> PF.MINOR_SHIFT) & PF.MINOR_MASK;
  if (minor > PF.SUPPORTED_MINOR) {
    throw new CallciumError(
      "UNSUPPORTED_MINOR",
      `Minor version ${minor} is above the highest supported (${PF.SUPPORTED_MINOR})`,
    );
  }

  const enforcement: Enforcement = {
    policy: data,
    callData: hexToBytes(callData),
    context: contextWords(context),
    operators: new Map(),
  };

  // Selector check.
  const isSelectorless = (headerByte & PF.FLAG_NO_SELECTOR) !== 0;
  if (!isSelectorless) {
    if (enforcement.callData.length < PF.SELECTOR_SIZE) {
      return { ok: false, violations: [{ code: "MISSING_SELECTOR" }] };
    }
    const expectedSelector = toHex(data, PF.SELECTOR_OFFSET, PF.SELECTOR_OFFSET + PF.SELECTOR_SIZE);
    const actualSelector = toHex(enforcement.callData, 0, PF.SELECTOR_SIZE);
    if (actualSelector !== expectedSelector) {
      return {
        ok: false,
        violations: [{ code: "SELECTOR_MISMATCH", resolvedValue: actualSelector, expectedValue: expectedSelector }],
      };
    }
  }
  const baseOffset = isSelectorless ? 0 : PF.SELECTOR_SIZE;

  // Groups sit past the embedded descriptor, whose bytes evaluation never reads.
  const groupCountOffset = PF.DESC_OFFSET + readU16(data, PF.DESC_LENGTH_OFFSET);
  const groupCount = data[groupCountOffset]!;

  // Evaluate groups with OR semantics.
  const violations: Violation[] = [];
  let groupOffset = groupCountOffset + PF.GROUP_COUNT_SIZE;
  for (let group = 0; group < groupCount; group++) {
    const violation = evaluateGroup(enforcement, baseOffset, groupOffset, group);
    if (violation === null) return { ok: true, matchedGroup: group };
    violations.push(violation);
    // Abort violations reject the policy outright; later groups are not consulted.
    if (VIOLATION_EFFECT[violation.code] === "abort") return { ok: false, violations };
    groupOffset += PF.GROUP_HEADER_SIZE + readU32(data, groupOffset + PF.GROUP_RULECOUNT_SIZE);
  }

  return { ok: false, violations };
}

/**
 * Enforce a policy against ABI-encoded call data, throwing on violation. Requires a policy blob that passes storage
 * validation. The outcome on any other blob past its header is undefined.
 * @param policy - Binary policy blob as 0x-prefixed hex string.
 * @param callData - ABI-encoded call data as 0x-prefixed hex string.
 * @param context - Optional execution context for context-scoped rules.
 * @throws {PolicyViolationError} If the policy rejects the call data.
 * @throws {CallciumError} If the policy blob is shorter than its fixed prefix or of an unsupported format version.
 * If the policy or call data is not valid hex.
 * If a context value is not of its property's type or does not fit a 32-byte word.
 */
function enforce(policy: Hex, callData: Hex, context?: Context): void {
  const result = check(policy, callData, context);
  if (!result.ok) {
    throw new PolicyViolationError(result.violations);
  }
}

///////////////////////////////////////////////////////////////////////////
// Group and rule evaluation
///////////////////////////////////////////////////////////////////////////

/** A violation of a test, before its root location is known. */
type TestViolation =
  Exclude<
    Violation,
    { code: "MISSING_SELECTOR" | "SELECTOR_MISMATCH" | "QUANTIFIER_LIMIT_EXCEEDED" | "QUANTIFIER_NO_MATCH" }
  > extends infer V
    ? V extends Violation
      ? Omit<V, "group" | "rule">
      : never
    : never;

/** A violation of a loop rule, before its root location is known. */
type LoopViolation =
  Exclude<Violation, { code: "MISSING_SELECTOR" | "SELECTOR_MISMATCH" }> extends infer V
    ? V extends Violation
      ? Omit<V, "group" | "rule">
      : never
    : never;

/** Evaluate the root group at `groupOffset`, returning its first violation, or null when every rule passes. */
function evaluateGroup(
  enforcement: Enforcement,
  baseOffset: number,
  groupOffset: number,
  group: number,
): Violation | null {
  const ruleCount = readU16(enforcement.policy, groupOffset);
  let ruleOffset = groupOffset + PF.GROUP_HEADER_SIZE;
  for (let rule = 0; rule < ruleCount; rule++) {
    const violation = evaluateRule(enforcement, baseOffset, ruleOffset);
    if (violation !== null) return { ...violation, group, rule };
    ruleOffset += readU16(enforcement.policy, ruleOffset);
  }
  return null;
}

/** Evaluate a root rule, returning its violation, or null when it passes. */
function evaluateRule(enforcement: Enforcement, baseOffset: number, ruleOffset: number): LoopViolation | null {
  const scope = scopeAt(enforcement.policy, ruleOffset);
  switch (scope) {
    case Scope.CALLDATA:
      return evaluateTest(enforcement, baseOffset, ruleOffset);
    case Scope.CONTEXT:
      return evaluateContextTest(enforcement, ruleOffset);
    case Scope.LOOP:
      return evaluateLoop(enforcement, baseOffset, ruleOffset);
    default:
      return scope satisfies never;
  }
}

/** Read the scope of the rule at `ruleOffset`. */
function scopeAt(policy: Uint8Array, ruleOffset: number): ScopeCode {
  const scope = policy[ruleOffset + PF.RULE_SCOPE_OFFSET]!;
  if (!isScopeCode(scope)) throw new CallciumError("UNKNOWN_SCOPE", `Unknown scope value ${scope}`, ruleOffset);
  return scope;
}

///////////////////////////////////////////////////////////////////////////
// Loop evaluation
///////////////////////////////////////////////////////////////////////////

/** Evaluate the loop rule at `ruleOffset`, its body against each element of the array its frame resolves. */
function evaluateLoop(enforcement: Enforcement, baseOffset: number, ruleOffset: number): LoopViolation | null {
  const { policy, callData } = enforcement;
  const quantifier = policy[ruleOffset + PF.RULE_QUANTIFIER_OFFSET]!;
  if (!isQuantifierCode(quantifier)) {
    throw new CallciumError("UNKNOWN_QUANTIFIER", `Unknown quantifier value ${quantifier}`, ruleOffset);
  }
  const depth = policy[ruleOffset + PF.LOOP_DEPTH_OFFSET]!;
  const pathStart = ruleOffset + PF.LOOP_DEPTH_OFFSET + PF.RULE_DEPTH_SIZE;
  const hintOffset = pathStart + depth * PF.PATH_STEP_SIZE;
  const site = { scope: Scope.LOOP, path: toHex(policy, pathStart, hintOffset) };
  const hopCount = policy[hintOffset]!;
  const hopsOffset = hintOffset + PF.HINT_HEADER_SIZE;
  const frameOffset = hopsOffset + hopCount * PF.HINT_HOP_SIZE;

  const array = chain(policy, callData, baseOffset, hopsOffset, hopCount);
  if (typeof array !== "number") return { code: array.code, ...site };
  let elems = array + readU32(policy, frameOffset);

  // A frame declaring no count spans a dynamic array, whose length word precedes its elements.
  let count = BigInt(readU16(policy, frameOffset + PF.HINT_FRAME_COUNT_OFFSET));
  if (count === 0n) {
    const length = readLength(callData, elems);
    if (typeof length !== "bigint") return { code: length.code, ...site };
    count = length;
    elems += 32;
  }
  if (count > BigInt(PF.MAX_QUANTIFIED_ARRAY_LENGTH)) {
    return { code: "QUANTIFIER_LIMIT_EXCEEDED", ...site, resolvedValue: bigintToHex(count) };
  }

  const bodyOffset = frameOffset + PF.HINT_FRAME_PREFIX_SIZE;
  const meta = readU16(policy, frameOffset + PF.HINT_FRAME_META_OFFSET);
  const elemStride = (meta & PF.HINT_META_STRIDE_MASK) * 32;
  const elemIsDynamic = (meta & PF.HINT_META_ELEM_DYNAMIC) !== 0;

  for (let elementIndex = 0; elementIndex < count; elementIndex++) {
    const slot = elems + elementIndex * elemStride;
    let elem = slot;
    if (elemIsDynamic) {
      const followed = follow(callData, elems, slot);
      if (typeof followed !== "number") return { code: followed.code, ...site, elementIndex };
      elem = followed;
    }

    const violation = evaluateBody(enforcement, bodyOffset, elem);
    switch (quantifier) {
      case LoopQuantifier.ALL:
        // A body violation fails the loop at its element, an abort included.
        if (violation !== null) return { ...violation, elementIndex };
        break;
      case LoopQuantifier.ANY:
        // A group-local body violation moves on to the next element; an abort ends evaluation.
        if (violation === null) return null;
        if (VIOLATION_EFFECT[violation.code] === "abort") return { ...violation, elementIndex };
        break;
      default:
        return quantifier satisfies never;
    }
  }

  if (quantifier === LoopQuantifier.ALL) return null;
  return { code: "QUANTIFIER_NO_MATCH", ...site };
}

/**
 * Evaluate the loop body at `bodyOffset` against the element whose encoding starts at `elem`. Return the first
 * violation, with the failing test's position, or null when every test passes.
 */
function evaluateBody(enforcement: Enforcement, bodyOffset: number, elem: number): TestViolation | null {
  const ruleCount = readU16(enforcement.policy, bodyOffset);
  let ruleOffset = bodyOffset + PF.GROUP_RULECOUNT_SIZE;
  for (let bodyRule = 0; bodyRule < ruleCount; bodyRule++) {
    const scope = scopeAt(enforcement.policy, ruleOffset);
    let violation: TestViolation | null;
    switch (scope) {
      case Scope.CALLDATA:
        violation = evaluateTest(enforcement, elem, ruleOffset);
        break;
      case Scope.CONTEXT:
        violation = evaluateContextTest(enforcement, ruleOffset);
        break;
      case Scope.LOOP:
        throw new CallciumError("INVALID_NESTED_LOOP", "Loop body holds a loop", ruleOffset);
      default:
        return scope satisfies never;
    }
    if (violation !== null) return { ...violation, bodyRule };
    ruleOffset += readU16(enforcement.policy, ruleOffset);
  }
  return null;
}

///////////////////////////////////////////////////////////////////////////
// Test evaluation
///////////////////////////////////////////////////////////////////////////

/** Evaluate the calldata test at `ruleOffset` from the starting point whose encoding starts at `base`. */
function evaluateTest(enforcement: Enforcement, base: number, ruleOffset: number): TestViolation | null {
  const { policy, callData } = enforcement;
  // The hint addresses the target on its own; path bytes carry no evaluation role.
  const depth = policy[ruleOffset + PF.RULE_DEPTH_OFFSET]!;
  const pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
  const hintOffset = pathStart + depth * PF.PATH_STEP_SIZE;
  const hopCount = policy[hintOffset]!;
  const hopsOffset = hintOffset + PF.HINT_HEADER_SIZE;
  const targetOffset = hopsOffset + hopCount * PF.HINT_HOP_SIZE;
  const typeCode = policy[targetOffset + PF.HINT_TARGET_TYPECODE_OFFSET]!;
  const opOffset = targetOffset + PF.HINT_TARGET_SIZE;
  const opCode = policy[opOffset]!;
  const dataLength = readU16(policy, opOffset + PF.RULE_OPCODE_SIZE);
  const dataOffset = opOffset + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;
  // The fields every violation of the test carries, built only once one occurs.
  const site = () => ({
    scope: Scope.CALLDATA,
    path: toHex(policy, pathStart, hintOffset),
    operator: operatorAt(enforcement, opOffset, typeCode),
    typeCode,
  });

  const chained = chain(policy, callData, base, hopsOffset, hopCount);
  if (typeof chained !== "number") return { code: chained.code, ...site() };
  const target = chained + readU32(policy, targetOffset);

  const word = loadWord(callData, target);
  if (!(word instanceof Uint8Array)) return { code: word.code, ...site() };
  const value = toBigInt(word, 0);

  // A dynamic target's chain ends at its payload, so the word there is the declared length.
  let operandType = typeCode;
  if (hasCalldataLength(typeCode)) {
    // The declared payload of `value` items must lie within calldata past the length word.
    const targetMeta = readU16(policy, targetOffset + PF.HINT_TARGET_META_OFFSET);
    const stride = typeCode === TypeCode.DYNAMIC_ARRAY ? (targetMeta & PF.HINT_META_STRIDE_MASK) * 32 : 1;
    const room = callData.length - (target + 32);
    if (stride !== 0 && value > BigInt(Math.floor(room / stride))) return { code: "CALLDATA_OUT_OF_BOUNDS", ...site() };
    operandType = LENGTH_TYPE;
  } else if (canonicalize(value, typeCode) !== value) {
    return { code: "NON_CANONICAL_VALUE", ...site(), resolvedValue: bigintToHex(value) };
  }

  const operand = resolveOperand(enforcement, opCode, dataOffset, ruleOffset);
  if (operand === null) {
    return { code: "MISSING_CONTEXT", ...site(), typeCode: contextPropertyType(readU16(policy, dataOffset)) };
  }
  if (applyOperator(opCode, value, operandType, policy, dataOffset, dataLength, operand, ruleOffset)) return null;
  return {
    code: "VALUE_MISMATCH",
    ...site(),
    resolvedValue: bigintToHex(value),
    ...(operand !== undefined && { resolvedOperand: bigintToHex(operand) }),
  };
}

/**
 * Return the operator at `opOffset` against a target of `typeCode`, parsed once per check. An `ANY` loop discards the
 * violation of every element whose body fails.
 */
function operatorAt(enforcement: Enforcement, opOffset: number, typeCode: number): DecodedOperator {
  let operator = enforcement.operators.get(opOffset);
  if (operator === undefined) {
    operator = readOperator(enforcement.policy, opOffset, typeCode);
    enforcement.operators.set(opOffset, operator);
  }
  return operator;
}

/** Evaluate the context test at `ruleOffset`. */
function evaluateContextTest(enforcement: Enforcement, ruleOffset: number): TestViolation | null {
  const { policy, context } = enforcement;
  const pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
  const contextPropertyId = readU16(policy, pathStart);
  const typeCode = contextPropertyType(contextPropertyId);
  const opOffset = pathStart + PF.PROPERTY_ID_SIZE;
  const site = () => ({ scope: Scope.CONTEXT, path: toHex(policy, pathStart, opOffset) });

  const value = context[contextPropertyId];
  if (value === undefined) return { code: "MISSING_CONTEXT", ...site(), typeCode };

  const opCode = policy[opOffset]!;
  const dataLength = readU16(policy, opOffset + PF.RULE_OPCODE_SIZE);
  const dataOffset = opOffset + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;

  const operand = resolveOperand(enforcement, opCode, dataOffset, ruleOffset);
  if (operand === null) {
    return {
      code: "MISSING_CONTEXT",
      ...site(),
      operator: operatorAt(enforcement, opOffset, typeCode),
      typeCode: contextPropertyType(readU16(policy, dataOffset)),
    };
  }
  if (applyOperator(opCode, value, typeCode, policy, dataOffset, dataLength, operand, ruleOffset)) return null;
  return {
    code: "VALUE_MISMATCH",
    ...site(),
    operator: operatorAt(enforcement, opOffset, typeCode),
    typeCode,
    resolvedValue: bigintToHex(value),
    ...(operand !== undefined && { resolvedOperand: bigintToHex(operand) }),
  };
}

///////////////////////////////////////////////////////////////////////////
// Hint chain resolution
///////////////////////////////////////////////////////////////////////////

/** Advance `from` by the offset word at `at`. */
function follow(callData: Uint8Array, from: number, at: number): ReadResult<number> {
  const word = readPointer(callData, at);
  if (typeof word !== "number") return word;
  if (word > callData.length - from) {
    return { code: "CALLDATA_OUT_OF_BOUNDS" };
  }
  return from + word;
}

/** Follow `hopCount` hop entries from `base` and return the calldata offset they reach. */
function chain(
  policy: Uint8Array,
  callData: Uint8Array,
  base: number,
  hopsOffset: number,
  hopCount: number,
): ReadResult<number> {
  for (let i = 0; i < hopCount; i++) {
    const hop = hopsOffset + i * PF.HINT_HOP_SIZE;
    const index = readU16(policy, hop + PF.HINT_HOP_INDEX_OFFSET);

    if (index === PF.HINT_NO_INDEX) {
      const next = follow(callData, base, base + readU32(policy, hop));
      if (typeof next !== "number") return next;
      base = next;
      continue;
    }

    const meta = readU16(policy, hop + PF.HINT_HOP_META_OFFSET);
    let elems = base;
    if ((meta & PF.HINT_META_DYNAMIC_ARRAY) !== 0) {
      const length = readLength(callData, elems);
      if (typeof length !== "bigint") return length;
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
// Operator application
///////////////////////////////////////////////////////////////////////////

/**
 * Resolve the operand of a single-operand comparison with a context source: the property's word, or null when the
 * context does not supply it. Every other operand reads from the operator data, so it resolves to undefined here.
 */
function resolveOperand(
  enforcement: Enforcement,
  opCode: number,
  dataOffset: number,
  ruleOffset: number,
): bigint | null | undefined {
  const source = sourceOf(opCode);
  if (!isSourceCode(source))
    throw new CallciumError(
      "UNKNOWN_OPERATOR",
      `Unknown operator code ${formatCode(opCode & ~Op.NOT, PF.RULE_OPCODE_SIZE)}`,
      ruleOffset,
    );
  switch (source) {
    case Source.CONSTANT:
      return undefined;
    case Source.CONTEXT:
      return enforcement.context[readU16(enforcement.policy, dataOffset)] ?? null;
    default:
      return source satisfies never;
  }
}

/**
 * Apply an operator to `value`, a word of type `typeCode`, using the operator data in
 * `policy[dataOffset : dataOffset+dataLength)` or the context operand already resolved. A length compares as
 * `LENGTH_TYPE`. Handles the NOT flag by inverting the base result.
 */
function applyOperator(
  opCode: number,
  value: bigint,
  typeCode: number,
  policy: Uint8Array,
  dataOffset: number,
  dataLength: number,
  contextOperand: bigint | undefined,
  ruleOffset: number,
): boolean {
  const comparison = comparisonOf(opCode);
  if (!isComparisonCode(comparison))
    throw new CallciumError(
      "UNKNOWN_OPERATOR",
      `Unknown operator code ${formatCode(opCode & ~Op.NOT, PF.RULE_OPCODE_SIZE)}`,
      ruleOffset,
    );
  const operand = () => contextOperand ?? loadOperand(policy, dataOffset, typeCode);
  const upper = () => loadOperand(policy, dataOffset + operandWidth(typeCode)!, typeCode);
  let result: boolean;

  switch (comparison) {
    case Op.EQ:
    case Op.LENGTH_EQ:
      result = value === operand();
      break;
    case Op.GT:
    case Op.LENGTH_GT:
      result = compareTyped(value, operand(), typeCode) > 0;
      break;
    case Op.LT:
    case Op.LENGTH_LT:
      result = compareTyped(value, operand(), typeCode) < 0;
      break;
    case Op.GTE:
    case Op.LENGTH_GTE:
      result = compareTyped(value, operand(), typeCode) >= 0;
      break;
    case Op.LTE:
    case Op.LENGTH_LTE:
      result = compareTyped(value, operand(), typeCode) <= 0;
      break;
    case Op.BETWEEN:
    case Op.LENGTH_BETWEEN:
      result = compareTyped(value, operand(), typeCode) >= 0 && compareTyped(value, upper(), typeCode) <= 0;
      break;
    case Op.IN:
      result = isIn(value, typeCode, policy, dataOffset, dataLength);
      break;
    case Op.BITMASK_ALL: {
      const mask = operand();
      result = (value & mask) === mask;
      break;
    }
    case Op.BITMASK_ANY:
      result = (value & operand()) !== 0n;
      break;
    case Op.BITMASK_NONE:
      result = (value & operand()) === 0n;
      break;
    default:
      return comparison satisfies never;
  }

  return (opCode & Op.NOT) !== 0 ? !result : result;
}

/** Compare two 256-bit values, using two's complement interpretation for signed type codes. */
function compareTyped(value: bigint, operand: bigint, typeCode: number): number {
  if (isSigned(typeCode)) {
    const signedValue = BigInt.asIntN(256, value);
    const signedOperand = BigInt.asIntN(256, operand);
    return signedValue < signedOperand ? -1 : signedValue > signedOperand ? 1 : 0;
  }
  return value < operand ? -1 : value > operand ? 1 : 0;
}

/**
 * Binary search for `value` among the members of an IN operand. The members are packed as consecutive operands of the
 * width of `typeCode` and strictly ascending as loaded words compared unsigned.
 */
function isIn(value: bigint, typeCode: number, policy: Uint8Array, dataOffset: number, dataLength: number): boolean {
  const width = operandWidth(typeCode)!;
  let low = 0;
  let high = dataLength / width - 1;
  while (low <= high) {
    const mid = (low + high) >>> 1;
    const member = loadOperand(policy, dataOffset + mid * width, typeCode);
    if (value === member) return true;
    if (value < member) high = mid - 1;
    else low = mid + 1;
  }
  return false;
}

/** Check and enforce policies against ABI-encoded call data. */
export const PolicyEnforcer = { check, enforce };

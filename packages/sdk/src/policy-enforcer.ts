import { hexToBytes, bytesToHex, readU16, readU32, bigintToHex } from "./bytes";
import {
  PolicyFormat as PF,
  Scope,
  MAX_CONTEXT_PROPERTY_ID,
  Limits,
  Quantifier,
  isQuantifier,
  lookupContextProperty,
} from "./constants";
import { CallciumError, PolicyViolationError } from "./errors";
import { applyOperator, toBigInt, isLengthOp, canonicalize } from "./operators";
import { decodePolicy, parsePathSteps } from "./policy-coder";
import { locate, arrayShape, arrayElementAt, loadScalar, loadSlice, descendPath, readPointer } from "./reader";

import type { Location } from "./reader";
import type { Context, DescNode, EnforceResult, Hex, NavigationViolationCode, Violation, ViolationCode } from "./types";

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

/**
 * Walk a descriptor subtree through path steps and return the terminal leaf type code.
 *
 * Used only for violation metadata. Valid policies have structurally valid
 * quantifier suffixes (enforced by `PolicyValidator`); if a hand-crafted blob
 * violates that invariant, return the last resolvable node's type code as
 * best-effort diagnostic context.
 */
function resolveLeafTypeCode(elementNode: DescNode, remainingPath: Uint8Array): number {
  let node: DescNode = elementNode;
  const stepCount = remainingPath.length / 2;
  for (let step = 0; step < stepCount; step++) {
    const childIndex = readU16(remainingPath, step * 2);
    if (node.type === "tuple") {
      const field = node.fields[childIndex];
      if (!field) break;
      node = field;
    } else if (node.type === "staticArray" || node.type === "dynamicArray") {
      node = node.element;
    } else {
      break;
    }
  }
  return node.typeCode;
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
  const { policy: decoded, tree } = decodePolicy(policy);
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
      const violation = evaluateRule(rule, tree, callDataBytes, baseOffset, groupIndex, ruleIndex, context);
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

/** Evaluate a single rule against calldata or context, returning a violation or null on pass. */
function evaluateRule(
  rule: {
    scope: { value: number };
    path: { value: Hex };
    hint?: { value: Hex };
    opCode: { value: number };
    data: { value: Hex };
  },
  tree: DescNode[],
  callDataBytes: Uint8Array,
  baseOffset: number,
  groupIndex: number,
  ruleIndex: number,
  context?: Context,
): Violation | null {
  const scope = rule.scope.value;
  const pathBytes = hexToBytes(rule.path.value);
  const opCode = rule.opCode.value;
  const operandData = hexToBytes(rule.data.value);

  if (scope === Scope.CONTEXT) {
    return evaluateContextRule(pathBytes, opCode, operandData, groupIndex, ruleIndex, rule.path.value, context);
  }

  // A concrete hint addresses the target directly; only a sentinel resolves by traversal.
  const hintBytes = rule.hint === undefined ? new Uint8Array(0) : hexToBytes(rule.hint.value);
  if (hintBytes.length > 0 && readU32(hintBytes, 0) !== PF.HINT_SENTINEL_OFFSET) {
    return evaluateHintedRule(
      hintBytes,
      pathBytes,
      tree,
      callDataBytes,
      baseOffset,
      opCode,
      operandData,
      groupIndex,
      ruleIndex,
      rule.path.value,
    );
  }

  // Calldata rule: locate the path target.
  const locResult = locate(tree, callDataBytes, pathBytes, baseOffset);

  if (!locResult.ok) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: locResult.code,
      scope: Scope.CALLDATA,
      path: rule.path.value,
      opCode,
      operandData: rule.data.value,
    };
  }

  // Quantifier: delegate to composable quantifier evaluator.
  if (locResult.type === "quantifier") {
    return evaluateQuantifier(
      locResult.quantifier,
      callDataBytes,
      opCode,
      operandData,
      groupIndex,
      ruleIndex,
      rule.path.value,
    );
  }

  // Leaf: evaluate directly.
  return evaluateLeaf(locResult.location, callDataBytes, opCode, operandData, groupIndex, ruleIndex, rule.path.value);
}

///////////////////////////////////////////////////////////////////////////
// Hinted rule evaluation
///////////////////////////////////////////////////////////////////////////

/** Evaluate a calldata rule through its concrete hint block. */
function evaluateHintedRule(
  hintBytes: Uint8Array,
  pathBytes: Uint8Array,
  tree: DescNode[],
  callDataBytes: Uint8Array,
  baseOffset: number,
  opCode: number,
  operandData: Uint8Array,
  groupIndex: number,
  ruleIndex: number,
  pathHex: Hex,
): Violation | null {
  const quantifier = parsePathSteps(pathHex).find(isQuantifier);
  if (quantifier !== undefined) {
    return evaluateHintedQuantifier(
      hintBytes,
      quantifier,
      callDataBytes,
      baseOffset,
      opCode,
      operandData,
      groupIndex,
      ruleIndex,
      pathHex,
    );
  }

  const typeCode = hintBytes[PF.HINT_STATIC_SIZE - 1]!;
  const location: Location = {
    head: baseOffset + readU32(hintBytes, 0),
    base: baseOffset,
    // A compilable path crosses no dynamic node, so a dynamic target is a top-level parameter and
    // its element metadata comes from that parameter's node.
    node: hintTargetNode(typeCode, tree[readU16(pathBytes, 0)]),
  };

  return evaluateLeaf(location, callDataBytes, opCode, operandData, groupIndex, ruleIndex, pathHex);
}

/** Evaluate a quantified calldata rule through its concrete hint block. */
function evaluateHintedQuantifier(
  hintBytes: Uint8Array,
  quantifier: number,
  callDataBytes: Uint8Array,
  baseOffset: number,
  opCode: number,
  operandData: Uint8Array,
  groupIndex: number,
  ruleIndex: number,
  pathHex: Hex,
): Violation | null {
  const arrayHead = baseOffset + readU32(hintBytes, 0);
  const arrayBaseWord = readPointer(callDataBytes, arrayHead);
  if (typeof arrayBaseWord !== "number") {
    return outOfBounds(groupIndex, ruleIndex, pathHex, opCode, operandData);
  }
  const arrayBase = baseOffset + arrayBaseWord;
  const length = readPointer(callDataBytes, arrayBase);
  if (typeof length !== "number") {
    return outOfBounds(groupIndex, ruleIndex, pathHex, opCode, operandData);
  }

  if (length > Limits.MAX_QUANTIFIED_ARRAY_LENGTH) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "QUANTIFIER_LIMIT_EXCEEDED",
      scope: Scope.CALLDATA,
      path: pathHex,
      resolvedValue: bigintToHex(BigInt(length)),
    };
  }

  if (length === 0) {
    if (quantifier === Quantifier.ALL) return null;
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "QUANTIFIER_EMPTY_ARRAY",
      scope: Scope.CALLDATA,
      path: pathHex,
    };
  }

  const typeCode = hintBytes[PF.HINT_QUANTIFIED_SIZE - 1]!;
  // A compilable quantified path targets a static element, so the target is always a scalar.
  const node = hintTargetNode(typeCode);
  const elemStride = readU32(hintBytes, PF.HINT_ELEM_STRIDE_OFFSET);
  const isUniversal = quantifier === Quantifier.ALL;

  let target = arrayBase + 32 + readU32(hintBytes, PF.HINT_SUFFIX_OFFSET);
  let anyPassed = false;

  for (let elemIndex = 0; elemIndex < length; elemIndex++, target += elemStride) {
    const applied = applyLeafOperator(callDataBytes, { head: target, base: arrayBase, node }, opCode, operandData);

    if ("error" in applied) {
      // An abort-effect violation ends evaluation whatever the quantifier; a later element cannot
      // rescue calldata the enforcer cannot read (spec §9.3).
      if (applied.error === "NON_CANONICAL_VALUE") {
        return {
          group: groupIndex,
          rule: ruleIndex,
          code: applied.error,
          scope: Scope.CALLDATA,
          path: pathHex,
          opCode,
          operandData: bytesToHex(operandData),
          typeCode,
          elementIndex: elemIndex,
          resolvedValue: applied.resolvedValue,
        };
      }

      return {
        group: groupIndex,
        rule: ruleIndex,
        code: applied.error,
        scope: Scope.CALLDATA,
        path: pathHex,
        opCode,
        operandData: bytesToHex(operandData),
        typeCode,
        elementIndex: elemIndex,
      };
    }

    if (applied.passed) {
      anyPassed = true;
      if (!isUniversal) return null;
    } else if (isUniversal) {
      return {
        group: groupIndex,
        rule: ruleIndex,
        code: "VALUE_MISMATCH",
        scope: Scope.CALLDATA,
        path: pathHex,
        opCode,
        operandData: bytesToHex(operandData),
        typeCode,
        elementIndex: elemIndex,
        resolvedValue: applied.resolvedValue,
      };
    }
  }

  if (isUniversal || anyPassed) return null;
  return {
    group: groupIndex,
    rule: ruleIndex,
    code: "VALUE_MISMATCH",
    scope: Scope.CALLDATA,
    path: pathHex,
    opCode,
    operandData: bytesToHex(operandData),
    typeCode,
  };
}

/**
 * Build the descriptor node a hint's type code stands for. Dynamic targets keep their decoded node
 * so element metadata (and with it the payload stride) stays available.
 */
function hintTargetNode(typeCode: number, decoded?: DescNode): DescNode {
  if (decoded !== undefined && decoded.typeCode === typeCode && decoded.isDynamic) return decoded;
  return { type: "elementary", typeCode, isDynamic: false, staticSize: 32 };
}

/** Build a calldata bounds violation for a hinted read. */
function outOfBounds(
  groupIndex: number,
  ruleIndex: number,
  pathHex: Hex,
  opCode: number,
  operandData: Uint8Array,
): Violation {
  return {
    group: groupIndex,
    rule: ruleIndex,
    code: "CALLDATA_OUT_OF_BOUNDS",
    scope: Scope.CALLDATA,
    path: pathHex,
    opCode,
    operandData: bytesToHex(operandData),
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
      "INVALID_CONTEXT_PATH",
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

  const result = applyOperator(opCode, value, 32, operandData, propInfo.typeCode);

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

///////////////////////////////////////////////////////////////////////////
// Core leaf operator
///////////////////////////////////////////////////////////////////////////

type LeafResult =
  | { passed: boolean; resolvedValue: Hex }
  | { error: NavigationViolationCode }
  | { error: "NON_CANONICAL_VALUE"; resolvedValue: Hex };

/**
 * Load a value from calldata at the given location and apply the operator.
 *
 * `resolvedValue` is normalised at the decision point: length operators encode
 * the byte/element count as a hex bigint; scalar operators preserve the full
 * 32-byte ABI word so downstream rendering can decode left-aligned `bytesN` faithfully.
 */
function applyLeafOperator(
  callDataBytes: Uint8Array,
  location: Location,
  opCode: number,
  operandData: Uint8Array,
): LeafResult {
  const { node } = location;

  if (isLengthOp(opCode)) {
    let valueLength: number;

    if (node.isDynamic) {
      const lengthResult = loadSlice(callDataBytes, location);
      if (!lengthResult.ok) return { error: lengthResult.code };
      valueLength = lengthResult.length;
    } else {
      valueLength = node.staticSize;
    }

    const passed = applyOperator(opCode, 0n, valueLength, operandData, node.typeCode);
    return { passed, resolvedValue: bigintToHex(BigInt(valueLength)) };
  }

  // A value operator needs a 32-byte elementary scalar; no other node shape carries one.
  if (node.isDynamic || node.type !== "elementary") {
    throw new CallciumError("NOT_SCALAR", "Value operator on a target without a scalar word.");
  }

  const result = loadScalar(callDataBytes, location);
  if (!result.ok) return { error: result.code };

  const value = toBigInt(result.value, 0);
  if (canonicalize(value, node.typeCode) !== value) {
    return { error: "NON_CANONICAL_VALUE", resolvedValue: bigintToHex(value) };
  }

  const passed = applyOperator(opCode, value, 32, operandData, node.typeCode);
  return { passed, resolvedValue: bigintToHex(value) };
}

///////////////////////////////////////////////////////////////////////////
// Leaf evaluation
///////////////////////////////////////////////////////////////////////////

/** Evaluate a leaf rule, producing a violation on failure or null on pass. */
function evaluateLeaf(
  location: Location,
  callDataBytes: Uint8Array,
  opCode: number,
  operandData: Uint8Array,
  groupIndex: number,
  ruleIndex: number,
  pathHex: Hex,
): Violation | null {
  const result = applyLeafOperator(callDataBytes, location, opCode, operandData);
  const typeCode = location.node.typeCode;

  if ("error" in result) {
    if (result.error === "NON_CANONICAL_VALUE") {
      return {
        group: groupIndex,
        rule: ruleIndex,
        code: result.error,
        scope: Scope.CALLDATA,
        path: pathHex,
        opCode,
        operandData: bytesToHex(operandData),
        typeCode,
        resolvedValue: result.resolvedValue,
      };
    }

    return {
      group: groupIndex,
      rule: ruleIndex,
      code: result.error,
      scope: Scope.CALLDATA,
      path: pathHex,
      opCode,
      operandData: bytesToHex(operandData),
      typeCode,
    };
  }

  if (!result.passed) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "VALUE_MISMATCH",
      scope: Scope.CALLDATA,
      path: pathHex,
      opCode,
      operandData: bytesToHex(operandData),
      typeCode,
      resolvedValue: result.resolvedValue,
    };
  }

  return null;
}

///////////////////////////////////////////////////////////////////////////
// Quantifier evaluation
///////////////////////////////////////////////////////////////////////////

/** Evaluate a quantified rule by iterating over array elements with ALL/ANY semantics. */
function evaluateQuantifier(
  qResult: {
    quantifier: number;
    location: Location;
    remainingPath: Uint8Array;
  },
  callDataBytes: Uint8Array,
  opCode: number,
  operandData: Uint8Array,
  groupIndex: number,
  ruleIndex: number,
  pathHex: Hex,
): Violation | null {
  const { quantifier, location: arrayLocation, remainingPath } = qResult;
  const operandHex = bytesToHex(operandData);
  // Diagnostic metadata only — resolved before any calldata read so shape/element/navigation
  // failures can carry it too. Falls back best-effort for hand-crafted blobs that bypass validation.
  const arrayNode = arrayLocation.node;
  const elementNode =
    arrayNode.type === "staticArray" || arrayNode.type === "dynamicArray" ? arrayNode.element : arrayNode;
  const leafTypeCode = resolveLeafTypeCode(elementNode, remainingPath);

  // Compute array shape from the array location.
  const shapeResult = arrayShape(callDataBytes, arrayLocation);
  if (!shapeResult.ok) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: shapeResult.code,
      scope: Scope.CALLDATA,
      path: pathHex,
      opCode,
      operandData: operandHex,
      typeCode: leafTypeCode,
    };
  }
  const shape = shapeResult.shape;

  // Check quantifier limit.
  if (shape.length > Limits.MAX_QUANTIFIED_ARRAY_LENGTH) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "QUANTIFIER_LIMIT_EXCEEDED",
      scope: Scope.CALLDATA,
      path: pathHex,
      resolvedValue: bigintToHex(BigInt(shape.length)),
    };
  }

  // Empty array semantics.
  if (shape.length === 0) {
    if (quantifier === Quantifier.ALL) {
      return null;
    }
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "QUANTIFIER_EMPTY_ARRAY",
      scope: Scope.CALLDATA,
      path: pathHex,
    };
  }

  const isUniversal = quantifier === Quantifier.ALL;
  const hasSuffix = remainingPath.length > 0;

  for (let elemIndex = 0; elemIndex < shape.length; elemIndex++) {
    // Resolve element location via arrayElementAt.
    const elemResult = arrayElementAt(shape, elemIndex, callDataBytes);
    if (!elemResult.ok) {
      // Navigation failures abort under every quantifier: calldata the enforcer cannot read is
      // not an element that merely fails the operator (spec §9.3).
      return {
        group: groupIndex,
        rule: ruleIndex,
        code: elemResult.code,
        scope: Scope.CALLDATA,
        path: pathHex,
        opCode,
        operandData: operandHex,
        typeCode: leafTypeCode,
        elementIndex: elemIndex,
      };
    }
    const elemLocation = elemResult.location;

    // Resolve the leaf location: post-descend for suffix paths, the element itself otherwise.
    let leafLocation: Location;
    if (hasSuffix) {
      const navResult = descendPath(callDataBytes, elemLocation, remainingPath);
      if (!navResult.ok) {
        return {
          group: groupIndex,
          rule: ruleIndex,
          code: navResult.code,
          scope: Scope.CALLDATA,
          path: pathHex,
          opCode,
          operandData: operandHex,
          typeCode: leafTypeCode,
          elementIndex: elemIndex,
        };
      }
      leafLocation = navResult.location;
    } else {
      leafLocation = elemLocation;
    }

    const applied = applyLeafOperator(callDataBytes, leafLocation, opCode, operandData);

    if ("error" in applied) {
      // An abort-effect violation ends evaluation whatever the quantifier; a later element
      // cannot rescue calldata the enforcer cannot read.
      if (applied.error === "NON_CANONICAL_VALUE") {
        return {
          group: groupIndex,
          rule: ruleIndex,
          code: applied.error,
          scope: Scope.CALLDATA,
          path: pathHex,
          opCode,
          operandData: operandHex,
          typeCode: leafTypeCode,
          elementIndex: elemIndex,
          resolvedValue: applied.resolvedValue,
        };
      }

      return {
        group: groupIndex,
        rule: ruleIndex,
        code: applied.error,
        scope: Scope.CALLDATA,
        path: pathHex,
        opCode,
        operandData: operandHex,
        typeCode: leafTypeCode,
        elementIndex: elemIndex,
      };
    }

    if (isUniversal && !applied.passed) {
      return {
        group: groupIndex,
        rule: ruleIndex,
        code: "VALUE_MISMATCH",
        scope: Scope.CALLDATA,
        path: pathHex,
        opCode,
        operandData: operandHex,
        typeCode: leafTypeCode,
        resolvedValue: applied.resolvedValue,
        elementIndex: elemIndex,
      };
    }
    if (!isUniversal && applied.passed) {
      return null;
    }
  }

  if (isUniversal) {
    return null;
  }
  // Existential (ANY) failure: every element rejected the constraint.
  return {
    group: groupIndex,
    rule: ruleIndex,
    code: "VALUE_MISMATCH",
    scope: Scope.CALLDATA,
    path: pathHex,
    opCode,
    operandData: operandHex,
    typeCode: leafTypeCode,
  };
}

/** Check and enforce policies against ABI-encoded call data. */
export const PolicyEnforcer = { check, enforce };

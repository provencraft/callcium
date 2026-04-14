import { hexToBytes, bytesToHex, readU16, bigintToHex } from "./bytes";
import {
  PolicyFormat as PF,
  Scope,
  ContextProperty,
  MAX_CONTEXT_PROPERTY_ID,
  Limits,
  Quantifier,
  TypeCode,
} from "./constants";
import { CallciumError, PolicyViolationError } from "./errors";
import { applyOperator, toBigInt, isLengthOp } from "./operators";
import { decodePolicy } from "./policy-coder";
import { locate, arrayShape, arrayElementAt, loadScalar, loadSlice, descendPath } from "./reader";

import type { Location } from "./reader";
import type { Context, DescNode, EnforceResult, Hex, Violation, ViolationCode } from "./types";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** Convert a hex address to a 256-bit bigint (zero-padded to 32 bytes). */
function addressToBigInt(hex: string): bigint {
  const bytes = hexToBytes(hex);
  const padded = new Uint8Array(32);
  padded.set(bytes, 32 - bytes.length);
  return toBigInt(padded, 0);
}

///////////////////////////////////////////////////////////////////////////
// Context property map
///////////////////////////////////////////////////////////////////////////

const CTX_PROPERTY_KEYS: Record<number, keyof Context> = {
  [ContextProperty.MSG_SENDER]: "msgSender",
  [ContextProperty.MSG_VALUE]: "msgValue",
  [ContextProperty.BLOCK_TIMESTAMP]: "blockTimestamp",
  [ContextProperty.BLOCK_NUMBER]: "blockNumber",
  [ContextProperty.CHAIN_ID]: "chainId",
  [ContextProperty.TX_ORIGIN]: "txOrigin",
};

///////////////////////////////////////////////////////////////////////////
// Public API
///////////////////////////////////////////////////////////////////////////

/**
 * Check a policy against ABI-encoded call data without throwing on violations.
 * @param policy - Binary policy blob as 0x-prefixed hex string.
 * @param callData - ABI-encoded call data as 0x-prefixed hex string.
 * @param context - Optional execution context for context-scoped rules.
 * @returns Pass with matched group index, or fail with one violation per failed group.
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
        violations: [
          {
            code: "MISSING_SELECTOR",
            message: "Calldata too short to contain a selector",
          },
        ],
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
            message: `Expected selector ${expectedSelector}, got ${actualSelector}`,
            resolvedValue: actualSelector,
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

  if (pathBytes.length / 2 > Limits.MAX_PATH_DEPTH) {
    throw new CallciumError(
      "INVALID_PATH",
      `Path depth ${pathBytes.length / 2} exceeds maximum ${Limits.MAX_PATH_DEPTH}.`,
    );
  }

  if (scope === Scope.CONTEXT) {
    return evaluateContextRule(pathBytes, opCode, operandData, groupIndex, ruleIndex, rule.path.value, context);
  }

  // Calldata rule: locate the path target.
  const locResult = locate(tree, callDataBytes, pathBytes, baseOffset);

  if (!locResult.ok) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: locResult.code,
      message: `Navigation failed: ${locResult.code}`,
      path: rule.path.value,
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

  const key = CTX_PROPERTY_KEYS[propertyId]!;
  const contextValue = context?.[key];

  if (contextValue === undefined) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "MISSING_CONTEXT",
      message: `Context property "${key}" not provided`,
      path: pathHex,
    };
  }

  let value: bigint;
  if (typeof contextValue === "string") {
    value = addressToBigInt(contextValue);
  } else {
    value = contextValue;
  }

  const result = applyOperator(opCode, value, 32, operandData, TypeCode.UINT_MAX);

  if (!result) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "VALUE_MISMATCH",
      message: "Context value does not satisfy operator",
      path: pathHex,
      resolvedValue: bigintToHex(value),
    };
  }

  return null;
}

///////////////////////////////////////////////////////////////////////////
// Core leaf operator
///////////////////////////////////////////////////////////////////////////

type LeafResult =
  | { passed: true; value?: bigint; length?: number }
  | { passed: false; value?: bigint; length?: number }
  | { error: ViolationCode };

/** Load a value from calldata at the given location and apply the operator. */
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
    return { passed, length: valueLength };
  }

  const result = loadScalar(callDataBytes, location);
  if (!result.ok) return { error: result.code };

  const value = toBigInt(result.value, 0);
  const passed = applyOperator(opCode, value, 32, operandData, node.typeCode);
  return { passed, value };
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

  if ("error" in result) {
    const message = isLengthOp(opCode)
      ? `Failed to read length: ${result.error}`
      : `Failed to load value: ${result.error}`;
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: result.error,
      message,
      path: pathHex,
    };
  }

  if (!result.passed) {
    const resolvedValue =
      result.value !== undefined ? bigintToHex(result.value) : bigintToHex(BigInt(result.length ?? 0));
    const message = isLengthOp(opCode) ? "Length does not satisfy operator" : "Value does not satisfy operator";
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "VALUE_MISMATCH",
      message,
      path: pathHex,
      resolvedValue,
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

  // Compute array shape from the array location.
  const shapeResult = arrayShape(callDataBytes, arrayLocation);
  if (!shapeResult.ok) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: shapeResult.code,
      message: `Failed to read array shape: ${shapeResult.code}`,
      path: pathHex,
    };
  }
  const shape = shapeResult.shape;

  // Check quantifier limit.
  if (shape.length > Limits.MAX_QUANTIFIED_ARRAY_LENGTH) {
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "QUANTIFIER_LIMIT_EXCEEDED",
      message: `Array length ${shape.length} exceeds maximum ${Limits.MAX_QUANTIFIED_ARRAY_LENGTH}`,
      path: pathHex,
    };
  }

  // Empty array semantics.
  if (shape.length === 0) {
    if (quantifier === Quantifier.ALL_OR_EMPTY) {
      return null;
    }
    return {
      group: groupIndex,
      rule: ruleIndex,
      code: "QUANTIFIER_EMPTY_ARRAY",
      message: "Quantifier applied to empty array",
      path: pathHex,
    };
  }

  const isUniversal = quantifier === Quantifier.ALL_OR_EMPTY || quantifier === Quantifier.ALL;
  const hasSuffix = remainingPath.length > 0;

  for (let elemIndex = 0; elemIndex < shape.length; elemIndex++) {
    // Resolve element location via arrayElementAt.
    const elemResult = arrayElementAt(shape, elemIndex, callDataBytes);
    if (!elemResult.ok) {
      if (isUniversal) {
        return {
          group: groupIndex,
          rule: ruleIndex,
          code: elemResult.code,
          message: `Quantifier element ${elemIndex}: ${elemResult.code}`,
          path: pathHex,
        };
      }
      continue;
    }
    const elemLocation = elemResult.location;

    let elemPassed: boolean;

    if (hasSuffix) {
      // Descend through suffix path from element location.
      const leafResult = descendPath(callDataBytes, elemLocation, remainingPath);

      if (!leafResult.ok) {
        if (isUniversal) {
          return {
            group: groupIndex,
            rule: ruleIndex,
            code: leafResult.code,
            message: `Quantifier element ${elemIndex} navigation failed: ${leafResult.code}`,
            path: pathHex,
          };
        }
        continue;
      }

      elemPassed = evaluateLeafValue(leafResult.location, callDataBytes, opCode, operandData);
    } else {
      // Element itself is the target.
      const leafResult = applyLeafOperator(callDataBytes, elemLocation, opCode, operandData);
      if ("error" in leafResult) {
        if (isUniversal) {
          return {
            group: groupIndex,
            rule: ruleIndex,
            code: leafResult.error,
            message: `Quantifier element ${elemIndex}: ${leafResult.error}`,
            path: pathHex,
          };
        }
        continue;
      }
      elemPassed = leafResult.passed;
    }

    // Short-circuit.
    if (isUniversal && !elemPassed) {
      return {
        group: groupIndex,
        rule: ruleIndex,
        code: "VALUE_MISMATCH",
        message: `Quantifier: element ${elemIndex} failed`,
        path: pathHex,
      };
    }
    if (!isUniversal && elemPassed) {
      return null;
    }
  }

  if (isUniversal) {
    return null;
  }
  return {
    group: groupIndex,
    rule: ruleIndex,
    code: "VALUE_MISMATCH",
    message: "Quantifier ANY: no element satisfied the operator",
    path: pathHex,
  };
}

///////////////////////////////////////////////////////////////////////////
// Leaf value evaluation
///////////////////////////////////////////////////////////////////////////

/** Apply a leaf operator and return a boolean. Returns false on calldata read failure. */
function evaluateLeafValue(
  location: Location,
  callDataBytes: Uint8Array,
  opCode: number,
  operandData: Uint8Array,
): boolean {
  const result = applyLeafOperator(callDataBytes, location, opCode, operandData);
  if ("error" in result) return false;
  return result.passed;
}

/** Check and enforce policies against ABI-encoded call data. */
export const PolicyEnforcer = { check, enforce };

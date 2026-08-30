import {
  type Hex,
  isLengthOp,
  lookupOp,
  Op,
  parsePathSteps,
  Scope,
  TypeCode,
  type ValueMismatchViolation,
  type Violation,
} from "@callcium/sdk";
import { formatCalldataPath, formatContextPath, formatOpLabel } from "./format-path";
import { decodeOperandsFromData, decodeValue } from "./format-value";
import type { ParamNode } from "@/tools/policy-builder/builder-engine";

///////////////////////////////////////////////////////////////////////////
// Path
///////////////////////////////////////////////////////////////////////////

function formatPath(path: Hex, scope: number, params?: ParamNode[]): string {
  if (scope === Scope.CONTEXT) {
    const propertyId = Number.parseInt(path.slice(2, 6), 16);
    return formatContextPath(propertyId);
  }
  if (scope === Scope.CALLDATA) {
    return formatCalldataPath(parsePathSteps(path), params);
  }
  return path;
}

///////////////////////////////////////////////////////////////////////////
// Constraint
///////////////////////////////////////////////////////////////////////////

function formatOperands(operandData: Hex, typeCode: number, opCode: number): string[] {
  const opBase = opCode & ~Op.NOT;
  // Length ops always render as decimal counts regardless of the declared leaf type.
  const decodeType = isLengthOp(opCode) ? TypeCode.UINT_MAX : typeCode;
  return decodeOperandsFromData(operandData, decodeType, opBase);
}

function formatConstraint(opCode: number, operandData: Hex, typeCode: number): string {
  const opBase = opCode & ~Op.NOT;
  const negated = (opCode & Op.NOT) !== 0;
  const operator = formatOpLabel(opBase, negated);
  const operands = formatOperands(operandData, typeCode, opCode);
  const arity = lookupOp(opBase).operands;

  if (arity === "variadic") return `${operator} [${operands.join(", ")}]`;
  if (arity === "range") return `${operator} [${operands[0]}, ${operands[1]}]`;
  return `${operator} ${operands[0]}`;
}

///////////////////////////////////////////////////////////////////////////
// Actual
///////////////////////////////////////////////////////////////////////////

function formatLeafActual(resolvedValue: Hex, opCode: number, typeCode: number): string {
  if (isLengthOp(opCode)) return BigInt(resolvedValue).toString(10);
  return decodeValue(resolvedValue, typeCode);
}

///////////////////////////////////////////////////////////////////////////
// Per-variant rendering
///////////////////////////////////////////////////////////////////////////

function renderValueMismatch(v: ValueMismatchViolation, params?: ParamNode[]): string {
  const path = formatPath(v.path, v.scope, params);
  const operandNote = v.resolvedOperand === undefined ? "" : ` (${decodeValue(v.resolvedOperand, v.typeCode)})`;
  const constraint = formatConstraint(v.opCode, v.operandData, v.typeCode) + operandNote;
  const actual = v.resolvedValue !== undefined ? formatLeafActual(v.resolvedValue, v.opCode, v.typeCode) : undefined;

  if (v.elementIndex !== undefined) {
    if (actual !== undefined) return `${path}: ${constraint} violated at element ${v.elementIndex} by ${actual}`;
    return `${path}: ${constraint} violated at element ${v.elementIndex}`;
  }
  if (actual !== undefined) return `${path}: ${constraint} violated by ${actual}`;
  return `${path}: ${constraint} violated by all elements`;
}

///////////////////////////////////////////////////////////////////////////
// Public entry
///////////////////////////////////////////////////////////////////////////

/**
 * Render a structured violation as a one-line human-readable string.
 *
 * Path, constraint, and value formatting all live here — the SDK exposes raw
 * semantic data only. Pass `params` (decoded descriptor parameter trees) to
 * enable positional path labels (`arg(0).field(1)`); without them the formatter
 * still renders generic placeholders.
 */
export function formatViolation(v: Violation, params?: ParamNode[]): string {
  switch (v.code) {
    case "MISSING_SELECTOR":
      return "calldata too short to contain a selector";
    case "SELECTOR_MISMATCH":
      return `selector mismatch: expected ${v.expectedValue}, got ${v.resolvedValue}`;
    case "MISSING_CONTEXT": {
      const path = formatPath(v.path, v.scope, params);
      // With operand data the missing property is the rule's operand; the path names the target.
      if (v.operandData !== undefined) {
        return `${decodeOperandsFromData(v.operandData, v.typeCode, Op.EQ_CTX)[0]} not provided (referenced by ${path})`;
      }
      return `${path} not provided`;
    }
    case "VALUE_MISMATCH":
      return renderValueMismatch(v, params);
    case "QUANTIFIER_LIMIT_EXCEEDED":
      return `${formatPath(v.path, v.scope, params)}: array length ${BigInt(v.resolvedValue).toString(10)} exceeds maximum`;
    case "QUANTIFIER_EMPTY_ARRAY":
      return `${formatPath(v.path, v.scope, params)}: quantifier applied to empty array`;
    case "NON_CANONICAL_VALUE":
      return `${formatPath(v.path, v.scope, params)}: ${v.resolvedValue} is not a canonical encoding`;
    case "CALLDATA_OUT_OF_BOUNDS":
    case "ARRAY_INDEX_OUT_OF_BOUNDS": {
      const path = formatPath(v.path, v.scope, params);
      const elem = v.elementIndex !== undefined ? ` at element ${v.elementIndex}` : "";
      return `${path}: ${v.code}${elem}`;
    }
  }
}

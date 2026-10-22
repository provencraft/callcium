import {
  type DecodedOperator,
  type DecodedPolicy,
  lookupOp,
  parsePathSteps,
  Scope,
  Source,
  type ValueMismatchViolation,
  type Violation,
} from "@callcium/sdk";
import { formatCalldataPath, formatContextPath, formatOpLabel, loopSteps } from "./format-path";
import { decodeOperands, decodeValue, formatOperandList } from "./format-value";
import { type ParamNode, toParamNodes } from "./policy-builder";

///////////////////////////////////////////////////////////////////////////
// Path
///////////////////////////////////////////////////////////////////////////

/** A violation that locates a rule. */
type RuleViolation = Extract<Violation, { group: number }>;

function formatPath(v: RuleViolation, policy: DecodedPolicy, params: ParamNode[]): string {
  const steps = parsePathSteps(v.path);
  if (v.scope === Scope.CONTEXT) return formatContextPath(steps[0]);
  const rule = policy.groups[v.group].rules[v.rule];
  if (!("body" in rule)) return formatCalldataPath(steps, params);
  // A loop violation names the loop; a body test's path starts at the element.
  const loop = loopSteps(rule.path.value, rule.quantifier.value);
  return formatCalldataPath(v.scope === Scope.LOOP ? loop : [...loop, ...steps], params);
}

///////////////////////////////////////////////////////////////////////////
// Constraint
///////////////////////////////////////////////////////////////////////////

function formatConstraint(operator: DecodedOperator): string {
  const label = formatOpLabel(operator.opCode, operator.negated);
  return `${label} ${formatOperandList(lookupOp(operator.opCode).operands, decodeOperands(operator))}`;
}

///////////////////////////////////////////////////////////////////////////
// Per-variant rendering
///////////////////////////////////////////////////////////////////////////

function renderValueMismatch(v: ValueMismatchViolation, path: string): string {
  const { operator } = v;
  const operandNote =
    v.resolvedOperand === undefined ? "" : ` (${decodeValue(v.resolvedOperand, operator.operandType)})`;
  const elem = v.elementIndex !== undefined ? ` at element ${v.elementIndex}` : "";
  const actual = decodeValue(v.resolvedValue, operator.operandType);
  return `${path}: ${formatConstraint(operator)}${operandNote} violated${elem} by ${actual}`;
}

///////////////////////////////////////////////////////////////////////////
// Public entry
///////////////////////////////////////////////////////////////////////////

/**
 * Render a structured violation as a one-line human-readable string.
 *
 * Path, constraint, and value formatting all live here — the SDK exposes raw semantic data only. `policy` is the
 * inspected policy the violation came from: it supplies the loop a body test's path starts in and the parameter trees
 * behind positional path labels (`arg(0).field(1)`).
 */
export function formatViolation(v: Violation, policy: DecodedPolicy): string {
  switch (v.code) {
    case "MISSING_SELECTOR":
      return "calldata too short to contain a selector";
    case "SELECTOR_MISMATCH":
      return `selector mismatch: expected ${v.expectedValue}, got ${v.resolvedValue}`;
  }

  const path = formatPath(v, policy, toParamNodes(policy.descriptor.params));
  switch (v.code) {
    case "MISSING_CONTEXT":
      // With a context operand the missing property is the operand; the path names the target.
      if (v.operator?.source === Source.CONTEXT) {
        return `${decodeOperands(v.operator)[0]} not provided (referenced by ${path})`;
      }
      return `${path} not provided`;
    case "VALUE_MISMATCH":
      return renderValueMismatch(v, path);
    case "QUANTIFIER_LIMIT_EXCEEDED":
      return `${path}: array length ${BigInt(v.resolvedValue).toString(10)} exceeds maximum`;
    case "QUANTIFIER_NO_MATCH":
      return `${path}: no element satisfies the loop body`;
    case "NON_CANONICAL_VALUE":
      return `${path}: ${v.resolvedValue} is not a canonical encoding`;
    case "CALLDATA_OUT_OF_BOUNDS":
    case "ARRAY_INDEX_OUT_OF_BOUNDS": {
      const elem = v.elementIndex !== undefined ? ` at element ${v.elementIndex}` : "";
      return `${path}: ${v.code}${elem}`;
    }
  }
}

import type { Hex, Issue } from "./types";

///////////////////////////////////////////////////////////////////////////
// Constants
///////////////////////////////////////////////////////////////////////////

const ZERO: Hex = `0x${"0".repeat(64)}`;

///////////////////////////////////////////////////////////////////////////
// Type mismatch
///////////////////////////////////////////////////////////////////////////

/** Create an issue from operator compatibility results. */
export function fromOpRule(
  code: string,
  message: string,
  groupIndex: number,
  constraintIndex: number,
  opCode: Hex,
): Issue {
  return {
    severity: "error",
    category: "typeMismatch",
    groupIndex,
    constraintIndex,
    code,
    value1: opCode,
    value2: ZERO,
    message,
  };
}

/** Issue for an operand that is not canonically encoded for the declared type. */
export function nonCanonicalOperand(groupIndex: number, constraintIndex: number, operand: Hex, canonical: Hex): Issue {
  return {
    severity: "error",
    category: "typeMismatch",
    groupIndex,
    constraintIndex,
    code: "NON_CANONICAL_OPERAND",
    value1: operand,
    value2: canonical,
    message: "Operand is not the canonical encoding for the declared type",
  };
}

///////////////////////////////////////////////////////////////////////////
// Contradiction
///////////////////////////////////////////////////////////////////////////

/** eq(v)/neq(v) or lengthEq(v)/lengthNeq(v) on the same path. */
export function eqNeqContradiction(isLength: boolean, groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: isLength ? "LENGTH_EQ_NEQ_CONTRADICTION" : "EQ_NEQ_CONTRADICTION",
    value1: value,
    value2: ZERO,
    message: isLength ? "lengthEq(v) and lengthNeq(v) on same path" : "eq(v) and neq(v) on same path",
  };
}

/** Multiple eq()/lengthEq() operators with different values. */
export function conflictingEquality(
  isLength: boolean,
  groupIndex: number,
  constraintIndex: number,
  existing: Hex,
  newValue: Hex,
): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: isLength ? "CONFLICTING_LENGTH" : "CONFLICTING_EQUALITY",
    value1: existing,
    value2: newValue,
    message: isLength
      ? "Multiple lengthEq() operators with different values"
      : "Multiple eq() operators with different values",
  };
}

/** Value/length is outside the physical range of its type. */
export function outOfPhysicalBounds(isLength: boolean, groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: isLength ? "OUT_OF_PHYSICAL_LENGTH_BOUNDS" : "OUT_OF_PHYSICAL_BOUNDS",
    value1: value,
    value2: ZERO,
    message: isLength
      ? "Length value is outside the physical range"
      : "Value is outside the physical range of the type",
  };
}

/** gt()/lengthGt() on the maximum is impossible. */
export function impossibleGt(isLength: boolean, groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: isLength ? "IMPOSSIBLE_LENGTH_GT" : "IMPOSSIBLE_GT",
    value1: value,
    value2: ZERO,
    message: isLength ? "lengthGt() on maximum length is impossible" : "gt() on type maximum is impossible",
  };
}

/** lt()/lengthLt() on the minimum is impossible. */
export function impossibleLt(isLength: boolean, groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: isLength ? "IMPOSSIBLE_LENGTH_LT" : "IMPOSSIBLE_LT",
    value1: value,
    value2: ZERO,
    message: isLength ? "lengthLt() on minimum length is impossible" : "lt() on type minimum is impossible",
  };
}

/** eq()/lengthEq() value is excluded by a bound. */
export function boundsExcludeEquality(
  isLength: boolean,
  groupIndex: number,
  constraintIndex: number,
  eq: Hex,
  bound: Hex,
): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: isLength ? "BOUNDS_EXCLUDE_LENGTH" : "BOUNDS_EXCLUDE_EQUALITY",
    value1: eq,
    value2: bound,
    message: isLength ? "lengthEq() value is excluded by bound" : "eq() value is excluded by bound",
  };
}

/** Lower bound/length exceeds the upper bound. */
export function impossibleRange(
  isLength: boolean,
  groupIndex: number,
  constraintIndex: number,
  lower: Hex,
  upper: Hex,
): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: isLength ? "IMPOSSIBLE_LENGTH_RANGE" : "IMPOSSIBLE_RANGE",
    value1: lower,
    value2: upper,
    message: isLength ? "Lower length bound exceeds upper bound" : "Lower bound exceeds upper bound",
  };
}

/** Set operation excludes existing eq() value. */
export function setExcludesEquality(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: "SET_EXCLUDES_EQUALITY",
    value1: value,
    value2: ZERO,
    message: "Set operation excludes existing eq() value",
  };
}

/** Multiple isIn() sets have no intersection. */
export function emptySetIntersection(groupIndex: number, constraintIndex: number): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: "EMPTY_SET_INTERSECTION",
    value1: ZERO,
    value2: ZERO,
    message: "Multiple isIn() sets have no intersection",
  };
}

/** All values in isIn() set are excluded by neq/notIn. */
export function setFullyExcluded(groupIndex: number, constraintIndex: number): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: "SET_FULLY_EXCLUDED",
    value1: ZERO,
    value2: ZERO,
    message: "All values in isIn() set are excluded by neq/notIn",
  };
}

/** Bitmask operators conflict. */
export function bitmaskContradiction(groupIndex: number, constraintIndex: number, mask: Hex, conflicting: Hex): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: "BITMASK_CONTRADICTION",
    value1: mask,
    value2: conflicting,
    message: "Bitmask operators conflict",
  };
}

/** bitmaskAny is impossible because all bits are forbidden. */
export function bitmaskAnyImpossible(groupIndex: number, constraintIndex: number, mask: Hex, mustBeZero: Hex): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: "BITMASK_ANY_IMPOSSIBLE",
    value1: mask,
    value2: mustBeZero,
    message: "bitmaskAny is impossible because all bits are forbidden",
  };
}

/** isIn/notIn set is not strictly sorted and deduplicated. */
export function unsortedInSet(groupIndex: number, constraintIndex: number): Issue {
  return {
    severity: "error",
    category: "contradiction",
    groupIndex,
    constraintIndex,
    code: "UNSORTED_IN_SET",
    value1: ZERO,
    value2: ZERO,
    message: "isIn/notIn set is not strictly sorted and deduplicated.",
  };
}

/** Group contains zero constraints. */
export function emptyGroup(groupIndex: number): Issue {
  return {
    severity: "error",
    category: "vacuity",
    groupIndex,
    constraintIndex: 0,
    code: "EMPTY_GROUP",
    value1: ZERO,
    value2: ZERO,
    message: "Group contains zero constraints.",
  };
}

///////////////////////////////////////////////////////////////////////////
// Redundancy
///////////////////////////////////////////////////////////////////////////

/** Numeric/length bound dominated by a stricter bound. */
export function dominatedBound(isLength: boolean, groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return {
    severity: "warning",
    category: "redundancy",
    groupIndex,
    constraintIndex,
    code: isLength ? "DOMINATED_LENGTH_BOUND" : "DOMINATED_BOUND",
    value1: value,
    value2: ZERO,
    message: isLength
      ? "Length bound is dominated by a stricter bound"
      : "Numeric bound is dominated by a stricter bound",
  };
}

/** Bound redundant because eq()/lengthEq() is set. */
export function redundantBound(
  isLength: boolean,
  groupIndex: number,
  constraintIndex: number,
  bound: Hex,
  eq: Hex,
): Issue {
  return {
    severity: "warning",
    category: "redundancy",
    groupIndex,
    constraintIndex,
    code: isLength ? "REDUNDANT_LENGTH_BOUND" : "REDUNDANT_BOUND",
    value1: bound,
    value2: eq,
    message: isLength
      ? "Length bound is redundant because lengthEq() is set"
      : "Bound is redundant because eq() is set",
  };
}

/** notIn() value was present in isIn() set. */
export function setReduction(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return {
    severity: "warning",
    category: "redundancy",
    groupIndex,
    constraintIndex,
    code: "SET_REDUCTION",
    value1: value,
    value2: ZERO,
    message: "notIn() value was present in isIn() set",
  };
}

/** isIn() sets partially overlap. */
export function setRedundancy(groupIndex: number, constraintIndex: number, intersectionCount: Hex): Issue {
  return {
    severity: "warning",
    category: "redundancy",
    groupIndex,
    constraintIndex,
    code: "SET_REDUNDANCY",
    value1: intersectionCount,
    value2: ZERO,
    message: "isIn() sets partially overlap",
  };
}

/** Some values in isIn() set are excluded by neq/notIn. */
export function setPartiallyExcluded(groupIndex: number, constraintIndex: number, excludedCount: Hex): Issue {
  return {
    severity: "warning",
    category: "redundancy",
    groupIndex,
    constraintIndex,
    code: "SET_PARTIALLY_EXCLUDED",
    value1: excludedCount,
    value2: ZERO,
    message: "Some values in isIn() set are excluded by neq/notIn",
  };
}

/** Bitmask operation is redundant. */
export function redundantBitmask(groupIndex: number, constraintIndex: number, mask: Hex, existing: Hex): Issue {
  return {
    severity: "warning",
    category: "redundancy",
    groupIndex,
    constraintIndex,
    code: "REDUNDANT_BITMASK",
    value1: mask,
    value2: existing,
    message: "Bitmask operation is redundant",
  };
}

/** gte/lte pair fusible into a single range operator. */
export function fusibleRange(
  isLength: boolean,
  groupIndex: number,
  constraintIndex: number,
  low: Hex,
  high: Hex,
): Issue {
  return {
    severity: "warning",
    category: "redundancy",
    groupIndex,
    constraintIndex,
    code: isLength ? "FUSIBLE_LENGTH_RANGE" : "FUSIBLE_RANGE",
    value1: low,
    value2: high,
    message: isLength
      ? "lengthGte() and lengthLte() fuse into a single lengthBetween()"
      : "gte() and lte() fuse into a single between()",
  };
}

/** Duplicate operator in constraint. */
export function duplicateConstraint(groupIndex: number, constraintIndex: number): Issue {
  return {
    severity: "warning",
    category: "redundancy",
    groupIndex,
    constraintIndex,
    code: "DUPLICATE_CONSTRAINT",
    value1: ZERO,
    value2: ZERO,
    message: "Duplicate operator in constraint",
  };
}

///////////////////////////////////////////////////////////////////////////
// Vacuity
///////////////////////////////////////////////////////////////////////////

/** gte(min)/lengthGte(0) is always true. */
export function vacuousGte(isLength: boolean, groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return {
    severity: "info",
    category: "vacuity",
    groupIndex,
    constraintIndex,
    code: isLength ? "VACUOUS_LENGTH_GTE" : "VACUOUS_GTE",
    value1: value,
    value2: ZERO,
    message: isLength ? "lengthGte(0) is always true" : "gte() bound equals type minimum (always true)",
  };
}

/** lte(max)/lengthLte(max) is always true. */
export function vacuousLte(isLength: boolean, groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return {
    severity: "info",
    category: "vacuity",
    groupIndex,
    constraintIndex,
    code: isLength ? "VACUOUS_LENGTH_LTE" : "VACUOUS_LTE",
    value1: value,
    value2: ZERO,
    message: isLength
      ? "lengthLte() bound equals maximum (always true)"
      : "lte() bound equals type maximum (always true)",
  };
}

///////////////////////////////////////////////////////////////////////////
// Compatibility
///////////////////////////////////////////////////////////////////////////

/** Path deeper than the reference enforcer's cap. */
export function pathDepthExceeded(groupIndex: number, constraintIndex: number, depth: Hex, maxDepth: Hex): Issue {
  return {
    severity: "warning",
    category: "compatibility",
    groupIndex,
    constraintIndex,
    code: "PATH_DEPTH_EXCEEDED",
    value1: depth,
    value2: maxDepth,
    message: "Path depth exceeds the reference enforcer cap",
  };
}

/** Quantifier over a static array beyond the reference enforcer's iteration cap. */
export function quantifierOverStaticLimit(
  groupIndex: number,
  constraintIndex: number,
  arrayLength: Hex,
  maxLength: Hex,
): Issue {
  return {
    severity: "warning",
    category: "compatibility",
    groupIndex,
    constraintIndex,
    code: "QUANTIFIER_OVER_STATIC_LIMIT",
    value1: arrayLength,
    value2: maxLength,
    message: "Quantifier over static array exceeds the reference enforcer cap",
  };
}

/** Context property ID outside the assigned set. */
export function unknownContextProperty(
  groupIndex: number,
  constraintIndex: number,
  contextId: Hex,
  maxContextId: Hex,
): Issue {
  return {
    severity: "warning",
    category: "compatibility",
    groupIndex,
    constraintIndex,
    code: "UNKNOWN_CONTEXT_PROPERTY",
    value1: contextId,
    value2: maxContextId,
    message: "Unknown context property ID",
  };
}

/** Negated operator under the existential quantifier. */
export function negationUnderAny(groupIndex: number, constraintIndex: number, opCode: Hex): Issue {
  return {
    severity: "warning",
    category: "compatibility",
    groupIndex,
    constraintIndex,
    code: "NEGATION_UNDER_ANY",
    value1: opCode,
    value2: ZERO,
    message: "Negated operator under any() passes when a decoy element differs",
  };
}

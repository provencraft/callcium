import type { Hex, Issue, IssueCategory, IssueSeverity } from "./types";

///////////////////////////////////////////////////////////////////////////
// Constants
///////////////////////////////////////////////////////////////////////////

export const ZERO: Hex = `0x${"0".repeat(64)}`;

///////////////////////////////////////////////////////////////////////////
// Internal helper
///////////////////////////////////////////////////////////////////////////

/** Construct a fully populated Issue. */
function _issue(
  severity: IssueSeverity,
  category: IssueCategory,
  groupIndex: number,
  constraintIndex: number,
  code: string,
  value1: Hex,
  value2: Hex,
  message: string,
): Issue {
  return { severity, category, groupIndex, constraintIndex, code, value1, value2, message };
}

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
  return _issue("error", "typeMismatch", groupIndex, constraintIndex, code, opCode, ZERO, message);
}

///////////////////////////////////////////////////////////////////////////
// Contradiction
///////////////////////////////////////////////////////////////////////////

/** eq(v) and neq(v) on same path. */
export function eqNeqContradiction(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "EQ_NEQ_CONTRADICTION",
    value,
    ZERO,
    "eq(v) and neq(v) on same path",
  );
}

/** Multiple eq() operators with different values. */
export function conflictingEquality(groupIndex: number, constraintIndex: number, existing: Hex, newValue: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "CONFLICTING_EQUALITY",
    existing,
    newValue,
    "Multiple eq() operators with different values",
  );
}

/** Value is outside the physical range of the type. */
export function outOfPhysicalBounds(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "OUT_OF_PHYSICAL_BOUNDS",
    value,
    ZERO,
    "Value is outside the physical range of the type",
  );
}

/** gt() on type maximum is impossible. */
export function impossibleGt(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "IMPOSSIBLE_GT",
    value,
    ZERO,
    "gt() on type maximum is impossible",
  );
}

/** lt() on type minimum is impossible. */
export function impossibleLt(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "IMPOSSIBLE_LT",
    value,
    ZERO,
    "lt() on type minimum is impossible",
  );
}

/** eq() value is excluded by bound. */
export function boundsExcludeEquality(groupIndex: number, constraintIndex: number, eq: Hex, bound: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "BOUNDS_EXCLUDE_EQUALITY",
    eq,
    bound,
    "eq() value is excluded by bound",
  );
}

/** Lower bound exceeds upper bound. */
export function impossibleRange(groupIndex: number, constraintIndex: number, lower: Hex, upper: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "IMPOSSIBLE_RANGE",
    lower,
    upper,
    "Lower bound exceeds upper bound",
  );
}

/** Set operation excludes existing eq() value. */
export function setExcludesEquality(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "SET_EXCLUDES_EQUALITY",
    value,
    ZERO,
    "Set operation excludes existing eq() value",
  );
}

/** Multiple isIn() sets have no intersection. */
export function emptySetIntersection(groupIndex: number, constraintIndex: number): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "EMPTY_SET_INTERSECTION",
    ZERO,
    ZERO,
    "Multiple isIn() sets have no intersection",
  );
}

/** All values in isIn() set are excluded by neq/notIn. */
export function setFullyExcluded(groupIndex: number, constraintIndex: number): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "SET_FULLY_EXCLUDED",
    ZERO,
    ZERO,
    "All values in isIn() set are excluded by neq/notIn",
  );
}

/** lengthEq(v) and lengthNeq(v) on same path. */
export function lengthEqNeqContradiction(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "LENGTH_EQ_NEQ_CONTRADICTION",
    value,
    ZERO,
    "lengthEq(v) and lengthNeq(v) on same path",
  );
}

/** Multiple lengthEq() operators with different values. */
export function conflictingLength(groupIndex: number, constraintIndex: number, existing: Hex, newValue: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "CONFLICTING_LENGTH",
    existing,
    newValue,
    "Multiple lengthEq() operators with different values",
  );
}

/** lengthEq() value is excluded by bound. */
export function boundsExcludeLength(groupIndex: number, constraintIndex: number, eq: Hex, bound: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "BOUNDS_EXCLUDE_LENGTH",
    eq,
    bound,
    "lengthEq() value is excluded by bound",
  );
}

/** Lower length bound exceeds upper bound. */
export function impossibleLengthRange(groupIndex: number, constraintIndex: number, lower: Hex, upper: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "IMPOSSIBLE_LENGTH_RANGE",
    lower,
    upper,
    "Lower length bound exceeds upper bound",
  );
}

/** Length value is outside the physical range. */
export function outOfPhysicalLengthBounds(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "OUT_OF_PHYSICAL_LENGTH_BOUNDS",
    value,
    ZERO,
    "Length value is outside the physical range",
  );
}

/** lengthGt() on maximum length is impossible. */
export function impossibleLengthGt(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "IMPOSSIBLE_LENGTH_GT",
    value,
    ZERO,
    "lengthGt() on maximum length is impossible",
  );
}

/** lengthLt() on minimum length is impossible. */
export function impossibleLengthLt(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "IMPOSSIBLE_LENGTH_LT",
    value,
    ZERO,
    "lengthLt() on minimum length is impossible",
  );
}

/** Bitmask operators conflict. */
export function bitmaskContradiction(groupIndex: number, constraintIndex: number, mask: Hex, conflicting: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "BITMASK_CONTRADICTION",
    mask,
    conflicting,
    "Bitmask operators conflict",
  );
}

/** bitmaskAny is impossible because all bits are forbidden. */
export function bitmaskAnyImpossible(groupIndex: number, constraintIndex: number, mask: Hex, mustBeZero: Hex): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "BITMASK_ANY_IMPOSSIBLE",
    mask,
    mustBeZero,
    "bitmaskAny is impossible because all bits are forbidden",
  );
}

/** isIn/notIn set is not strictly sorted and deduplicated. */
export function unsortedInSet(groupIndex: number, constraintIndex: number): Issue {
  return _issue(
    "error",
    "contradiction",
    groupIndex,
    constraintIndex,
    "UNSORTED_IN_SET",
    ZERO,
    ZERO,
    "isIn/notIn set is not strictly sorted and deduplicated.",
  );
}

/** Group contains zero constraints. */
export function emptyGroup(groupIndex: number): Issue {
  return _issue("error", "vacuity", groupIndex, 0, "EMPTY_GROUP", ZERO, ZERO, "Group contains zero constraints.");
}

///////////////////////////////////////////////////////////////////////////
// Redundancy
///////////////////////////////////////////////////////////////////////////

/** Numeric bound is dominated by a stricter bound. */
export function dominatedBound(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "warning",
    "redundancy",
    groupIndex,
    constraintIndex,
    "DOMINATED_BOUND",
    value,
    ZERO,
    "Numeric bound is dominated by a stricter bound",
  );
}

/** Bound is redundant because eq() is set. */
export function redundantBound(groupIndex: number, constraintIndex: number, bound: Hex, eq: Hex): Issue {
  return _issue(
    "warning",
    "redundancy",
    groupIndex,
    constraintIndex,
    "REDUNDANT_BOUND",
    bound,
    eq,
    "Bound is redundant because eq() is set",
  );
}

/** notIn() value was present in isIn() set. */
export function setReduction(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "warning",
    "redundancy",
    groupIndex,
    constraintIndex,
    "SET_REDUCTION",
    value,
    ZERO,
    "notIn() value was present in isIn() set",
  );
}

/** isIn() sets partially overlap. */
export function setRedundancy(groupIndex: number, constraintIndex: number, intersectionCount: Hex): Issue {
  return _issue(
    "warning",
    "redundancy",
    groupIndex,
    constraintIndex,
    "SET_REDUNDANCY",
    intersectionCount,
    ZERO,
    "isIn() sets partially overlap",
  );
}

/** Some values in isIn() set are excluded by neq/notIn. */
export function setPartiallyExcluded(groupIndex: number, constraintIndex: number, excludedCount: Hex): Issue {
  return _issue(
    "warning",
    "redundancy",
    groupIndex,
    constraintIndex,
    "SET_PARTIALLY_EXCLUDED",
    excludedCount,
    ZERO,
    "Some values in isIn() set are excluded by neq/notIn",
  );
}

/** Length bound is dominated by a stricter bound. */
export function dominatedLengthBound(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "warning",
    "redundancy",
    groupIndex,
    constraintIndex,
    "DOMINATED_LENGTH_BOUND",
    value,
    ZERO,
    "Length bound is dominated by a stricter bound",
  );
}

/** Length bound is redundant because lengthEq() is set. */
export function redundantLengthBound(groupIndex: number, constraintIndex: number, bound: Hex, eq: Hex): Issue {
  return _issue(
    "warning",
    "redundancy",
    groupIndex,
    constraintIndex,
    "REDUNDANT_LENGTH_BOUND",
    bound,
    eq,
    "Length bound is redundant because lengthEq() is set",
  );
}

/** Bitmask operation is redundant. */
export function redundantBitmask(groupIndex: number, constraintIndex: number, mask: Hex, existing: Hex): Issue {
  return _issue(
    "warning",
    "redundancy",
    groupIndex,
    constraintIndex,
    "REDUNDANT_BITMASK",
    mask,
    existing,
    "Bitmask operation is redundant",
  );
}

/** Duplicate operator in constraint. */
export function duplicateConstraint(groupIndex: number, constraintIndex: number): Issue {
  return _issue(
    "warning",
    "redundancy",
    groupIndex,
    constraintIndex,
    "DUPLICATE_CONSTRAINT",
    ZERO,
    ZERO,
    "Duplicate operator in constraint",
  );
}

///////////////////////////////////////////////////////////////////////////
// Vacuity
///////////////////////////////////////////////////////////////////////////

/** gte() bound equals type minimum (always true). */
export function vacuousGte(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "info",
    "vacuity",
    groupIndex,
    constraintIndex,
    "VACUOUS_GTE",
    value,
    ZERO,
    "gte() bound equals type minimum (always true)",
  );
}

/** lte() bound equals type maximum (always true). */
export function vacuousLte(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "info",
    "vacuity",
    groupIndex,
    constraintIndex,
    "VACUOUS_LTE",
    value,
    ZERO,
    "lte() bound equals type maximum (always true)",
  );
}

/** lengthGte(0) is always true. */
export function vacuousLengthGte(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "info",
    "vacuity",
    groupIndex,
    constraintIndex,
    "VACUOUS_LENGTH_GTE",
    value,
    ZERO,
    "lengthGte(0) is always true",
  );
}

/** lengthLte() bound equals maximum (always true). */
export function vacuousLengthLte(groupIndex: number, constraintIndex: number, value: Hex): Issue {
  return _issue(
    "info",
    "vacuity",
    groupIndex,
    constraintIndex,
    "VACUOUS_LENGTH_LTE",
    value,
    ZERO,
    "lengthLte() bound equals maximum (always true)",
  );
}

///////////////////////////////////////////////////////////////////////////
// Bound issue factory set
///////////////////////////////////////////////////////////////////////////

/** Pre-select value or length issue factories for a bound domain. */
export function boundIssues(isLength: boolean) {
  return {
    eqNeqContradiction: isLength ? lengthEqNeqContradiction : eqNeqContradiction,
    conflicting: isLength ? conflictingLength : conflictingEquality,
    outOfPhysicalBounds: isLength ? outOfPhysicalLengthBounds : outOfPhysicalBounds,
    impossibleGt: isLength ? impossibleLengthGt : impossibleGt,
    impossibleLt: isLength ? impossibleLengthLt : impossibleLt,
    boundsExcludeEquality: isLength ? boundsExcludeLength : boundsExcludeEquality,
    impossibleRange: isLength ? impossibleLengthRange : impossibleRange,
    dominated: isLength ? dominatedLengthBound : dominatedBound,
    redundant: isLength ? redundantLengthBound : redundantBound,
    vacuousGte: isLength ? vacuousLengthGte : vacuousGte,
    vacuousLte: isLength ? vacuousLengthLte : vacuousLte,
  };
}

/** Issue factory set returned by {@link boundIssues}. */
export type BoundIssueSet = ReturnType<typeof boundIssues>;

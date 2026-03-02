// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IssueCode
/// @notice Machine-readable codes for policy validation issues.
library IssueCode {
    /*/////////////////////////////////////////////////////////////////////////
                                  TYPE MISMATCH
    /////////////////////////////////////////////////////////////////////////*/

    /// Value operator used on a dynamic type.
    bytes32 internal constant VALUE_OP_ON_DYNAMIC = "VALUE_OP_ON_DYNAMIC";
    /// Comparison operator used on a non-numeric type.
    bytes32 internal constant NUMERIC_OP_ON_NON_NUMERIC = "NUMERIC_OP_ON_NON_NUMERIC";
    /// Bitmask operator used on an incompatible type.
    bytes32 internal constant BITMASK_ON_INVALID = "BITMASK_ON_INVALID";
    /// Length operator used on a non-dynamic type.
    bytes32 internal constant LENGTH_ON_STATIC = "LENGTH_ON_STATIC";
    /// Unrecognised operator code.
    bytes32 internal constant UNKNOWN_OPERATOR = "UNKNOWN_OPERATOR";

    /*/////////////////////////////////////////////////////////////////////////
                                  CONTRADICTION
    /////////////////////////////////////////////////////////////////////////*/

    /// eq(v) and neq(v) on the same path.
    bytes32 internal constant EQ_NEQ_CONTRADICTION = "EQ_NEQ_CONTRADICTION";
    /// Multiple eq() operators with different values.
    bytes32 internal constant CONFLICTING_EQUALITY = "CONFLICTING_EQUALITY";
    /// Value is outside the physical range of the type.
    bytes32 internal constant OUT_OF_PHYSICAL_BOUNDS = "OUT_OF_PHYSICAL_BOUNDS";
    /// gt() on the type maximum is impossible.
    bytes32 internal constant IMPOSSIBLE_GT = "IMPOSSIBLE_GT";
    /// lt() on the type minimum is impossible.
    bytes32 internal constant IMPOSSIBLE_LT = "IMPOSSIBLE_LT";
    /// eq() value is excluded by a bound.
    bytes32 internal constant BOUNDS_EXCLUDE_EQUALITY = "BOUNDS_EXCLUDE_EQUALITY";
    /// Lower bound exceeds upper bound.
    bytes32 internal constant IMPOSSIBLE_RANGE = "IMPOSSIBLE_RANGE";
    /// Set operation excludes the existing eq() value.
    bytes32 internal constant SET_EXCLUDES_EQUALITY = "SET_EXCLUDES_EQUALITY";
    /// Multiple isIn() sets have no intersection.
    bytes32 internal constant EMPTY_SET_INTERSECTION = "EMPTY_SET_INTERSECTION";
    /// All values in an isIn() set are excluded by neq/notIn.
    bytes32 internal constant SET_FULLY_EXCLUDED = "SET_FULLY_EXCLUDED";
    /// lengthEq(v) and lengthNeq(v) on the same path.
    bytes32 internal constant LENGTH_EQ_NEQ_CONTRADICTION = "LENGTH_EQ_NEQ_CONTRADICTION";
    /// Multiple lengthEq() operators with different values.
    bytes32 internal constant CONFLICTING_LENGTH = "CONFLICTING_LENGTH";
    /// lengthEq() value is excluded by a bound.
    bytes32 internal constant BOUNDS_EXCLUDE_LENGTH = "BOUNDS_EXCLUDE_LENGTH";
    /// Lower length bound exceeds upper bound.
    bytes32 internal constant IMPOSSIBLE_LENGTH_RANGE = "IMPOSSIBLE_LENGTH_RANGE";
    /// Length value is outside the physical range.
    bytes32 internal constant OUT_OF_PHYSICAL_LENGTH_BOUNDS = "OUT_OF_PHYSICAL_LENGTH_BOUNDS";
    /// lengthGt() on the maximum length is impossible.
    bytes32 internal constant IMPOSSIBLE_LENGTH_GT = "IMPOSSIBLE_LENGTH_GT";
    /// lengthLt() on the minimum length is impossible.
    bytes32 internal constant IMPOSSIBLE_LENGTH_LT = "IMPOSSIBLE_LENGTH_LT";
    /// Bitmask operators conflict.
    bytes32 internal constant BITMASK_CONTRADICTION = "BITMASK_CONTRADICTION";
    /// bitmaskAny is impossible because all bits are forbidden.
    bytes32 internal constant BITMASK_ANY_IMPOSSIBLE = "BITMASK_ANY_IMPOSSIBLE";
    /// isIn/notIn set is not strictly sorted and deduplicated.
    bytes32 internal constant UNSORTED_IN_SET = "UNSORTED_IN_SET";
    /// A group contains zero constraints.
    bytes32 internal constant EMPTY_GROUP = "EMPTY_GROUP";

    /*/////////////////////////////////////////////////////////////////////////
                                   REDUNDANCY
    /////////////////////////////////////////////////////////////////////////*/

    /// Numeric bound is dominated by a stricter bound.
    bytes32 internal constant DOMINATED_BOUND = "DOMINATED_BOUND";
    /// Bound is redundant because eq() is set.
    bytes32 internal constant REDUNDANT_BOUND = "REDUNDANT_BOUND";
    /// notIn() value was present in an isIn() set.
    bytes32 internal constant SET_REDUCTION = "SET_REDUCTION";
    /// isIn() sets partially overlap.
    bytes32 internal constant SET_REDUNDANCY = "SET_REDUNDANCY";
    /// Some values in an isIn() set are excluded by neq/notIn.
    bytes32 internal constant SET_PARTIALLY_EXCLUDED = "SET_PARTIALLY_EXCLUDED";
    /// Length bound is dominated by a stricter bound.
    bytes32 internal constant DOMINATED_LENGTH_BOUND = "DOMINATED_LENGTH_BOUND";
    /// Length bound is redundant because lengthEq() is set.
    bytes32 internal constant REDUNDANT_LENGTH_BOUND = "REDUNDANT_LENGTH_BOUND";
    /// Bitmask operation is redundant.
    bytes32 internal constant REDUNDANT_BITMASK = "REDUNDANT_BITMASK";
    /// Duplicate operator in a constraint.
    bytes32 internal constant DUPLICATE_CONSTRAINT = "DUPLICATE_CONSTRAINT";

    /*/////////////////////////////////////////////////////////////////////////
                                     VACUITY
    /////////////////////////////////////////////////////////////////////////*/

    /// gte() bound equals the type minimum (always true).
    bytes32 internal constant VACUOUS_GTE = "VACUOUS_GTE";
    /// lte() bound equals the type maximum (always true).
    bytes32 internal constant VACUOUS_LTE = "VACUOUS_LTE";
    /// lengthGte(0) is always true.
    bytes32 internal constant VACUOUS_LENGTH_GTE = "VACUOUS_LENGTH_GTE";
    /// lengthLte() bound equals the maximum (always true).
    bytes32 internal constant VACUOUS_LENGTH_LTE = "VACUOUS_LENGTH_LTE";
}

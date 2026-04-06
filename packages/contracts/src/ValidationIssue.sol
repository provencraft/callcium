// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IssueCode } from "./IssueCode.sol";

/// @dev IssueSeverity levels for validation issues.
enum IssueSeverity {
    Info,
    Warning,
    Error
}

/// @dev Categories of validation issues.
enum IssueCategory {
    TypeMismatch,
    Contradiction,
    Redundancy,
    Vacuity
}

/// @notice A single validation issue found during policy analysis.
struct Issue {
    /// IssueSeverity level of the issue.
    IssueSeverity severity;
    /// IssueCategory of the issue.
    IssueCategory category;
    /// Group index where the issue was found.
    uint32 groupIndex;
    /// Constraint index within the group.
    uint32 constraintIndex;
    /// Machine-readable code (e.g., "LENGTH_ON_STATIC").
    bytes32 code;
    /// Conflict values or metadata.
    bytes32 value1;
    bytes32 value2;
    /// Human-readable description.
    string message;
}

/// @title ValidationIssue
/// @notice Factory library for creating validation issues with centralized definitions.
library ValidationIssue {
    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates an issue from operator compatibility results.
    /// @param code Machine-readable error code from the compatibility check.
    /// @param message Human-readable description from the compatibility check.
    /// @param groupIndex Group index where the issue was found.
    /// @param constraintIndex Constraint index within the group.
    /// @param opCode The operator code that failed compatibility.
    /// @return The constructed validation issue.
    function fromOpRule(
        bytes32 code,
        string memory message,
        uint32 groupIndex,
        uint32 constraintIndex,
        uint8 opCode
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.TypeMismatch,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: code,
            value1: bytes32(uint256(opCode)),
            value2: bytes32(0),
            message: message
        });
    }

    /// @notice Creates an issue for eq(v) and neq(v) on the same path.
    /// @return The constructed validation issue.
    function eqNeqContradiction(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.EQ_NEQ_CONTRADICTION,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "eq(v) and neq(v) on same path"
        });
    }

    /// @notice Creates an issue for multiple eq() operators with different values.
    /// @return The constructed validation issue.
    function conflictingEquality(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 existing,
        uint256 newValue
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.CONFLICTING_EQUALITY,
            value1: bytes32(existing),
            value2: bytes32(newValue),
            message: "Multiple eq() operators with different values"
        });
    }

    /// @notice Creates an issue for a value outside the physical range of its type.
    /// @return The constructed validation issue.
    function outOfPhysicalBounds(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.OUT_OF_PHYSICAL_BOUNDS,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "Value is outside the physical range of the type"
        });
    }

    /// @notice Creates an issue for gt() on the type maximum.
    /// @return The constructed validation issue.
    function impossibleGt(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.IMPOSSIBLE_GT,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "gt() on type maximum is impossible"
        });
    }

    /// @notice Creates an issue for lt() on the type minimum.
    /// @return The constructed validation issue.
    function impossibleLt(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.IMPOSSIBLE_LT,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "lt() on type minimum is impossible"
        });
    }

    /// @notice Creates an issue when an eq() value is excluded by a bound.
    /// @return The constructed validation issue.
    function boundsExcludeEquality(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 eq,
        uint256 bound
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.BOUNDS_EXCLUDE_EQUALITY,
            value1: bytes32(eq),
            value2: bytes32(bound),
            message: "eq() value is excluded by bound"
        });
    }

    /// @notice Creates an issue when a lower bound exceeds the upper bound.
    /// @return The constructed validation issue.
    function impossibleRange(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 lower,
        uint256 upper
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.IMPOSSIBLE_RANGE,
            value1: bytes32(lower),
            value2: bytes32(upper),
            message: "Lower bound exceeds upper bound"
        });
    }

    /// @notice Creates an issue when a set operation excludes the existing eq() value.
    /// @return The constructed validation issue.
    function setExcludesEquality(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.SET_EXCLUDES_EQUALITY,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "Set operation excludes existing eq() value"
        });
    }

    /// @notice Creates an issue when multiple isIn() sets have no intersection.
    /// @return The constructed validation issue.
    function emptySetIntersection(uint32 groupIndex, uint32 constraintIndex) internal pure returns (Issue memory) {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.EMPTY_SET_INTERSECTION,
            value1: bytes32(0),
            value2: bytes32(0),
            message: "Multiple isIn() sets have no intersection"
        });
    }

    /// @notice Creates an issue when all values in an isIn() set are excluded.
    /// @return The constructed validation issue.
    function setFullyExcluded(uint32 groupIndex, uint32 constraintIndex) internal pure returns (Issue memory) {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.SET_FULLY_EXCLUDED,
            value1: bytes32(0),
            value2: bytes32(0),
            message: "All values in isIn() set are excluded by neq/notIn"
        });
    }

    /// @notice Creates an issue for lengthEq(v) and lengthNeq(v) on the same path.
    /// @return The constructed validation issue.
    function lengthEqNeqContradiction(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.LENGTH_EQ_NEQ_CONTRADICTION,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "lengthEq(v) and lengthNeq(v) on same path"
        });
    }

    /// @notice Creates an issue for multiple lengthEq() operators with different values.
    /// @return The constructed validation issue.
    function conflictingLength(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 existing,
        uint256 newValue
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.CONFLICTING_LENGTH,
            value1: bytes32(existing),
            value2: bytes32(newValue),
            message: "Multiple lengthEq() operators with different values"
        });
    }

    /// @notice Creates an issue when a lengthEq() value is excluded by a bound.
    /// @return The constructed validation issue.
    function boundsExcludeLength(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 eq,
        uint256 bound
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.BOUNDS_EXCLUDE_LENGTH,
            value1: bytes32(eq),
            value2: bytes32(bound),
            message: "lengthEq() value is excluded by bound"
        });
    }

    /// @notice Creates an issue when a lower length bound exceeds the upper bound.
    /// @return The constructed validation issue.
    function impossibleLengthRange(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 lower,
        uint256 upper
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.IMPOSSIBLE_LENGTH_RANGE,
            value1: bytes32(lower),
            value2: bytes32(upper),
            message: "Lower length bound exceeds upper bound"
        });
    }

    /// @notice Creates an issue for a length value outside the physical range.
    /// @return The constructed validation issue.
    function outOfPhysicalLengthBounds(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.OUT_OF_PHYSICAL_LENGTH_BOUNDS,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "Length value is outside the physical range"
        });
    }

    /// @notice Creates an issue for lengthGt() on the maximum length.
    /// @return The constructed validation issue.
    function impossibleLengthGt(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.IMPOSSIBLE_LENGTH_GT,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "lengthGt() on maximum length is impossible"
        });
    }

    /// @notice Creates an issue for lengthLt(0) which is impossible.
    /// @return The constructed validation issue.
    function impossibleLengthLt(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.IMPOSSIBLE_LENGTH_LT,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "lengthLt() on minimum length is impossible"
        });
    }

    /// @notice Creates an issue for conflicting bitmask operators.
    /// @return The constructed validation issue.
    function bitmaskContradiction(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 mask,
        uint256 conflicting
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.BITMASK_CONTRADICTION,
            value1: bytes32(mask),
            value2: bytes32(conflicting),
            message: "Bitmask operators conflict"
        });
    }

    /// @notice Creates an issue when bitmaskAny is impossible because all bits are forbidden.
    /// @return The constructed validation issue.
    function bitmaskAnyImpossible(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 mask,
        uint256 mustBeZero
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.BITMASK_ANY_IMPOSSIBLE,
            value1: bytes32(mask),
            value2: bytes32(mustBeZero),
            message: "bitmaskAny is impossible because all bits are forbidden"
        });
    }

    /// @notice Creates a warning for a numeric bound dominated by a stricter bound.
    /// @return The constructed validation issue.
    function dominatedBound(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Redundancy,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.DOMINATED_BOUND,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "Numeric bound is dominated by a stricter bound"
        });
    }

    /// @notice Creates a warning for a bound that is redundant because eq() is set.
    /// @return The constructed validation issue.
    function redundantBound(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 bound,
        uint256 eq
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Redundancy,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.REDUNDANT_BOUND,
            value1: bytes32(bound),
            value2: bytes32(eq),
            message: "Bound is redundant because eq() is set"
        });
    }

    /// @notice Creates a warning when a notIn() value was present in an isIn() set.
    /// @return The constructed validation issue.
    function setReduction(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Redundancy,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.SET_REDUCTION,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "notIn() value was present in isIn() set"
        });
    }

    /// @notice Creates a warning when isIn() sets partially overlap.
    /// @return The constructed validation issue.
    function setRedundancy(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 intersectionCount
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Redundancy,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.SET_REDUNDANCY,
            value1: bytes32(intersectionCount),
            value2: bytes32(0),
            message: "isIn() sets partially overlap"
        });
    }

    /// @notice Creates a warning when some isIn() values are excluded by neq/notIn.
    /// @return The constructed validation issue.
    function setPartiallyExcluded(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 excludedCount
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Redundancy,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.SET_PARTIALLY_EXCLUDED,
            value1: bytes32(excludedCount),
            value2: bytes32(0),
            message: "Some values in isIn() set are excluded by neq/notIn"
        });
    }

    /// @notice Creates an error when an isIn/notIn set is not strictly sorted and deduplicated.
    /// @return The constructed validation issue.
    function unsortedInSet(uint32 groupIndex, uint32 constraintIndex) internal pure returns (Issue memory) {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Contradiction,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.UNSORTED_IN_SET,
            value1: bytes32(0),
            value2: bytes32(0),
            message: "isIn/notIn set is not strictly sorted and deduplicated."
        });
    }

    /// @notice Creates an error when a group contains zero constraints.
    /// @return The constructed validation issue.
    function emptyGroup(uint32 groupIndex) internal pure returns (Issue memory) {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.Vacuity,
            groupIndex: groupIndex,
            constraintIndex: 0,
            code: IssueCode.EMPTY_GROUP,
            value1: bytes32(0),
            value2: bytes32(0),
            message: "Group contains zero constraints."
        });
    }

    /// @notice Creates a warning for a length bound dominated by a stricter bound.
    /// @return The constructed validation issue.
    function dominatedLengthBound(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Redundancy,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.DOMINATED_LENGTH_BOUND,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "Length bound is dominated by a stricter bound"
        });
    }

    /// @notice Creates a warning for a length bound that is redundant because lengthEq() is set.
    /// @return The constructed validation issue.
    function redundantLengthBound(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 bound,
        uint256 eq
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Redundancy,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.REDUNDANT_LENGTH_BOUND,
            value1: bytes32(bound),
            value2: bytes32(eq),
            message: "Length bound is redundant because lengthEq() is set"
        });
    }

    /// @notice Creates a warning for a redundant bitmask operation.
    /// @return The constructed validation issue.
    function redundantBitmask(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 mask,
        uint256 existing
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Redundancy,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.REDUNDANT_BITMASK,
            value1: bytes32(mask),
            value2: bytes32(existing),
            message: "Bitmask operation is redundant"
        });
    }

    /// @notice Creates a warning for a duplicate operator in a constraint.
    /// @return The constructed validation issue.
    function duplicateConstraint(uint32 groupIndex, uint32 constraintIndex) internal pure returns (Issue memory) {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Redundancy,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.DUPLICATE_CONSTRAINT,
            value1: bytes32(0),
            value2: bytes32(0),
            message: "Duplicate operator in constraint"
        });
    }

    /// @notice Creates an info issue for gte() on the type minimum (always true).
    /// @return The constructed validation issue.
    function vacuousGte(uint32 groupIndex, uint32 constraintIndex, uint256 value) internal pure returns (Issue memory) {
        return Issue({
            severity: IssueSeverity.Info,
            category: IssueCategory.Vacuity,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.VACUOUS_GTE,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "gte() bound equals type minimum (always true)"
        });
    }

    /// @notice Creates an info issue for lte() on the type maximum (always true).
    /// @return The constructed validation issue.
    function vacuousLte(uint32 groupIndex, uint32 constraintIndex, uint256 value) internal pure returns (Issue memory) {
        return Issue({
            severity: IssueSeverity.Info,
            category: IssueCategory.Vacuity,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.VACUOUS_LTE,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "lte() bound equals type maximum (always true)"
        });
    }

    /// @notice Creates an info issue for lengthGte(0) which is always true.
    /// @return The constructed validation issue.
    function vacuousLengthGte(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Info,
            category: IssueCategory.Vacuity,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.VACUOUS_LENGTH_GTE,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "lengthGte(0) is always true"
        });
    }

    /// @notice Creates an info issue for lengthLte() on the maximum (always true).
    /// @return The constructed validation issue.
    function vacuousLengthLte(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 value
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Info,
            category: IssueCategory.Vacuity,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.VACUOUS_LENGTH_LTE,
            value1: bytes32(value),
            value2: bytes32(0),
            message: "lengthLte() bound equals maximum (always true)"
        });
    }
}

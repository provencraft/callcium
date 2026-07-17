// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
    Vacuity,
    Compatibility
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
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function eqNeqContradiction(
        bool isLength,
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
            code: isLength ? IssueCode.LENGTH_EQ_NEQ_CONTRADICTION : IssueCode.EQ_NEQ_CONTRADICTION,
            value1: bytes32(value),
            value2: bytes32(0),
            message: isLength ? "lengthEq(v) and lengthNeq(v) on same path" : "eq(v) and neq(v) on same path"
        });
    }

    /// @notice Creates an issue for multiple eq() operators with different values.
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function conflictingEquality(
        bool isLength,
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
            code: isLength ? IssueCode.CONFLICTING_LENGTH : IssueCode.CONFLICTING_EQUALITY,
            value1: bytes32(existing),
            value2: bytes32(newValue),
            message: isLength
                ? "Multiple lengthEq() operators with different values"
                : "Multiple eq() operators with different values"
        });
    }

    /// @notice Creates an issue for a value outside the physical range of its type.
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function outOfPhysicalBounds(
        bool isLength,
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
            code: isLength ? IssueCode.OUT_OF_PHYSICAL_LENGTH_BOUNDS : IssueCode.OUT_OF_PHYSICAL_BOUNDS,
            value1: bytes32(value),
            value2: bytes32(0),
            message: isLength
                ? "Length value is outside the physical range"
                : "Value is outside the physical range of the type"
        });
    }

    /// @notice Creates an issue for gt() on the type maximum.
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function impossibleGt(
        bool isLength,
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
            code: isLength ? IssueCode.IMPOSSIBLE_LENGTH_GT : IssueCode.IMPOSSIBLE_GT,
            value1: bytes32(value),
            value2: bytes32(0),
            message: isLength ? "lengthGt() on maximum length is impossible" : "gt() on type maximum is impossible"
        });
    }

    /// @notice Creates an issue for lt() on the type minimum.
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function impossibleLt(
        bool isLength,
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
            code: isLength ? IssueCode.IMPOSSIBLE_LENGTH_LT : IssueCode.IMPOSSIBLE_LT,
            value1: bytes32(value),
            value2: bytes32(0),
            message: isLength ? "lengthLt() on minimum length is impossible" : "lt() on type minimum is impossible"
        });
    }

    /// @notice Creates an issue when an eq() value is excluded by a bound.
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function boundsExcludeEquality(
        bool isLength,
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
            code: isLength ? IssueCode.BOUNDS_EXCLUDE_LENGTH : IssueCode.BOUNDS_EXCLUDE_EQUALITY,
            value1: bytes32(eq),
            value2: bytes32(bound),
            message: isLength ? "lengthEq() value is excluded by bound" : "eq() value is excluded by bound"
        });
    }

    /// @notice Creates an issue when a lower bound exceeds the upper bound.
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function impossibleRange(
        bool isLength,
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
            code: isLength ? IssueCode.IMPOSSIBLE_LENGTH_RANGE : IssueCode.IMPOSSIBLE_RANGE,
            value1: bytes32(lower),
            value2: bytes32(upper),
            message: isLength ? "Lower length bound exceeds upper bound" : "Lower bound exceeds upper bound"
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
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function dominatedBound(
        bool isLength,
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
            code: isLength ? IssueCode.DOMINATED_LENGTH_BOUND : IssueCode.DOMINATED_BOUND,
            value1: bytes32(value),
            value2: bytes32(0),
            message: isLength
                ? "Length bound is dominated by a stricter bound"
                : "Numeric bound is dominated by a stricter bound"
        });
    }

    /// @notice Creates a warning for a bound that is redundant because eq() is set.
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function redundantBound(
        bool isLength,
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
            code: isLength ? IssueCode.REDUNDANT_LENGTH_BOUND : IssueCode.REDUNDANT_BOUND,
            value1: bytes32(bound),
            value2: bytes32(eq),
            message: isLength
                ? "Length bound is redundant because lengthEq() is set"
                : "Bound is redundant because eq() is set"
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
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function vacuousGte(
        bool isLength,
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
            code: isLength ? IssueCode.VACUOUS_LENGTH_GTE : IssueCode.VACUOUS_GTE,
            value1: bytes32(value),
            value2: bytes32(0),
            message: isLength ? "lengthGte(0) is always true" : "gte() bound equals type minimum (always true)"
        });
    }

    /// @notice Creates an info issue for lte() on the type maximum (always true).
    /// @param isLength True to report the length-domain variant of this issue.
    /// @return The constructed validation issue.
    function vacuousLte(
        bool isLength,
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
            code: isLength ? IssueCode.VACUOUS_LENGTH_LTE : IssueCode.VACUOUS_LTE,
            value1: bytes32(value),
            value2: bytes32(0),
            message: isLength
                ? "lengthLte() bound equals maximum (always true)"
                : "lte() bound equals type maximum (always true)"
        });
    }

    /// @notice Creates a warning for a path deeper than the reference enforcer's cap.
    /// @return The constructed validation issue.
    function pathDepthExceeded(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 depth,
        uint256 maxDepth
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Compatibility,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.PATH_DEPTH_EXCEEDED,
            value1: bytes32(depth),
            value2: bytes32(maxDepth),
            message: "Path depth exceeds the reference enforcer cap"
        });
    }

    /// @notice Creates a warning for a quantifier over a static array beyond the iteration cap.
    /// @return The constructed validation issue.
    function quantifierOverStaticLimit(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 arrayLength,
        uint256 maxLength
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Compatibility,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.QUANTIFIER_OVER_STATIC_LIMIT,
            value1: bytes32(arrayLength),
            value2: bytes32(maxLength),
            message: "Quantifier over static array exceeds the reference enforcer cap"
        });
    }

    /// @notice Creates a warning for an unassigned context property ID.
    /// @return The constructed validation issue.
    function unknownContextProperty(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 contextId,
        uint256 maxContextId
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Compatibility,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.UNKNOWN_CONTEXT_PROPERTY,
            value1: bytes32(contextId),
            value2: bytes32(maxContextId),
            message: "Unknown context property ID"
        });
    }

    /// @notice Creates a warning for a negated operator under an existential quantifier.
    /// @return The constructed validation issue.
    function negationUnderAny(
        uint32 groupIndex,
        uint32 constraintIndex,
        uint256 opCode
    )
        internal
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: IssueSeverity.Warning,
            category: IssueCategory.Compatibility,
            groupIndex: groupIndex,
            constraintIndex: constraintIndex,
            code: IssueCode.NEGATION_UNDER_ANY,
            value1: bytes32(opCode),
            value2: bytes32(0),
            message: "Negated operator under any() passes when a decoy element differs"
        });
    }

    /// @notice Creates an issue for an operand that is not canonically encoded for the declared type.
    /// @return The constructed validation issue.
    function nonCanonicalOperand(
        uint32 groupIndex,
        uint32 constraintIndex,
        bytes32 operand,
        bytes32 canonical
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
            code: IssueCode.NON_CANONICAL_OPERAND,
            value1: operand,
            value2: canonical,
            message: "Operand is not the canonical encoding for the declared type"
        });
    }
}

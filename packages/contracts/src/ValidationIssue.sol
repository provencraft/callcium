// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IssueCode } from "./IssueCode.sol";

/// @dev Severity of a validation issue.
enum IssueSeverity {
    Info,
    Warning,
    Error
}

/// @dev Kind of defect a validation issue reports.
enum IssueCategory {
    TypeMismatch,
    Contradiction,
    Redundancy,
    Vacuity,
    Compatibility
}

/// @notice The rule a validation issue names.
struct RuleLocation {
    /// Group of the rule.
    uint256 groupIndex;
    /// Position of the rule in its group.
    uint256 ruleIndex;
    /// Position of the test in its loop body, or `NO_INDEX`.
    uint256 bodyRuleIndex;
    /// Scope of the rule.
    uint8 scope;
    /// BE16-encoded path. A path in a body starts at the element.
    bytes path;
    /// Encoded operator: opCode(1) || each operand value as a 32-byte word, a context property as its ID.
    bytes operator;
}

/// @notice A single validation issue found during policy analysis.
struct Issue {
    /// Severity of the issue.
    IssueSeverity severity;
    /// Kind of defect the issue reports.
    IssueCategory category;
    /// Machine-readable code (for example "HINT_MISMATCH").
    bytes32 code;
    /// Group of the rule, or `NO_INDEX`.
    uint256 groupIndex;
    /// Position of the rule in its group, or `NO_INDEX`.
    uint256 ruleIndex;
    /// Position of the test in its loop body, or `NO_INDEX`.
    uint256 bodyRuleIndex;
    /// Scope of the rule.
    uint8 scope;
    /// BE16-encoded path. A path in a body starts at the element.
    bytes path;
    /// Encoded operator: opCode(1) || each operand value as a 32-byte word, a context property as its ID.
    bytes operator;
    /// First value that shows the defect, or zero.
    bytes32 value1;
    /// Second value that shows the defect, or zero.
    bytes32 value2;
    /// Human-readable description.
    string message;
}

/// @title ValidationIssue
/// @notice Constructors for validation issues.
library ValidationIssue {
    /// @dev Index of a location an issue does not name.
    uint256 internal constant NO_INDEX = type(uint256).max;

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates an issue for a descriptor whose composite node disagrees with its children.
    /// @param offset The descriptor offset of the node.
    /// @return The constructed validation issue.
    function invalidDescriptor(uint256 offset) internal pure returns (Issue memory) {
        return Issue({
            severity: IssueSeverity.Error,
            category: IssueCategory.TypeMismatch,
            code: IssueCode.INVALID_DESCRIPTOR,
            groupIndex: NO_INDEX,
            ruleIndex: NO_INDEX,
            bodyRuleIndex: NO_INDEX,
            scope: 0,
            path: "",
            operator: "",
            value1: bytes32(offset),
            value2: bytes32(0),
            message: "Descriptor node metadata disagrees with its children"
        });
    }

    /// @notice Creates an issue for a path that does not navigate the descriptor.
    /// @param location The rule.
    /// @param stepIndex The index of the step at fault.
    /// @param bound The bound the step broke: a parameter, field or element count, or a type code.
    /// @return The constructed validation issue.
    function unnavigablePath(
        RuleLocation memory location,
        uint256 stepIndex,
        uint256 bound
    )
        internal
        pure
        returns (Issue memory)
    {
        return _issue(
            location,
            IssueSeverity.Error,
            IssueCategory.TypeMismatch,
            IssueCode.UNNAVIGABLE_PATH,
            bytes32(stepIndex),
            bytes32(bound),
            "Path does not navigate the descriptor"
        );
    }

    /// @notice Creates an issue for a loop whose array path does not end at an array.
    /// @param location The loop.
    /// @param typeCode The type code of the node the path ends at.
    /// @return The constructed validation issue.
    function quantifierOnNonArray(RuleLocation memory location, uint256 typeCode) internal pure returns (Issue memory) {
        return _issue(
            location,
            IssueSeverity.Error,
            IssueCategory.TypeMismatch,
            IssueCode.QUANTIFIER_ON_NON_ARRAY,
            bytes32(typeCode),
            bytes32(0),
            "Loop path does not end at an array"
        );
    }

    /// @notice Creates an issue for a hint other than the compilation of its path.
    /// @param location The rule.
    /// @return The constructed validation issue.
    function hintMismatch(RuleLocation memory location) internal pure returns (Issue memory) {
        return _issue(
            location,
            IssueSeverity.Error,
            IssueCategory.TypeMismatch,
            IssueCode.HINT_MISMATCH,
            bytes32(0),
            bytes32(0),
            "Hint does not match the path compiled against the descriptor"
        );
    }

    /// @notice Creates an issue for an operator the compatibility matrix does not admit on its target type.
    /// @param code Machine-readable error code from the compatibility check.
    /// @param message Human-readable description from the compatibility check.
    /// @param location The rule.
    /// @param opCode The operator code.
    /// @return The constructed validation issue.
    function fromOpRule(
        bytes32 code,
        string memory message,
        RuleLocation memory location,
        uint8 opCode
    )
        internal
        pure
        returns (Issue memory)
    {
        return _issue(
            location,
            IssueSeverity.Error,
            IssueCategory.TypeMismatch,
            code,
            bytes32(uint256(opCode)),
            bytes32(0),
            message
        );
    }

    /// @notice Creates an issue for a context operand whose property type does not pair with the target type.
    /// @param location The rule.
    /// @param contextPropertyId The operand's context property ID.
    /// @param typeCode The target's type code.
    /// @return The constructed validation issue.
    function contextTypeMismatch(
        RuleLocation memory location,
        uint256 contextPropertyId,
        uint256 typeCode
    )
        internal
        pure
        returns (Issue memory)
    {
        return _issue(
            location,
            IssueSeverity.Error,
            IssueCategory.TypeMismatch,
            IssueCode.CONTEXT_TYPE_MISMATCH,
            bytes32(contextPropertyId),
            bytes32(typeCode),
            "Context property type does not match the target type"
        );
    }

    /// @notice Creates an issue for a constant outside its type's values.
    /// @param location The rule.
    /// @param value The constant.
    /// @return The constructed validation issue.
    function outOfPhysicalBounds(RuleLocation memory location, uint256 value) internal pure returns (Issue memory) {
        return _issue(
            location,
            IssueSeverity.Error,
            IssueCategory.Contradiction,
            IssueCode.OUT_OF_PHYSICAL_BOUNDS,
            bytes32(value),
            bytes32(0),
            "Value is outside the physical range of the type"
        );
    }

    /// @notice Creates an issue for the rule at which the rules on its subject, in order, stop being satisfiable
    /// together.
    /// @param location The rule.
    /// @return The constructed validation issue.
    function contradictoryRule(RuleLocation memory location) internal pure returns (Issue memory) {
        return _issue(
            location,
            IssueSeverity.Error,
            IssueCategory.Contradiction,
            IssueCode.CONTRADICTORY_RULE,
            bytes32(0),
            bytes32(0),
            "Rules on the subject are not satisfiable together"
        );
    }

    /// @notice Creates an issue for a rule the other rules on its subject imply.
    /// @param location The rule.
    /// @return The constructed validation issue.
    function redundantRule(RuleLocation memory location) internal pure returns (Issue memory) {
        return _issue(
            location,
            IssueSeverity.Warning,
            IssueCategory.Redundancy,
            IssueCode.REDUNDANT_RULE,
            bytes32(0),
            bytes32(0),
            "Rule is implied by the other rules on its subject"
        );
    }

    /// @notice Creates an issue for a bound looser than the tightest bound on its side of the subject.
    /// @param isLength True to report the length-domain variant of this issue.
    /// @param location The rule.
    /// @param bound The bound.
    /// @param tightest The tightest bound on its side.
    /// @return The constructed validation issue.
    function dominatedBound(
        bool isLength,
        RuleLocation memory location,
        uint256 bound,
        uint256 tightest
    )
        internal
        pure
        returns (Issue memory)
    {
        return _issue(
            location,
            IssueSeverity.Warning,
            IssueCategory.Redundancy,
            isLength ? IssueCode.DOMINATED_LENGTH_BOUND : IssueCode.DOMINATED_BOUND,
            bytes32(bound),
            bytes32(tightest),
            isLength
                ? "Length bound is dominated by a stricter bound"
                : "Numeric bound is dominated by a stricter bound"
        );
    }

    /// @notice Creates an issue for a rule that holds for every value and every context.
    /// @param location The rule.
    /// @return The constructed validation issue.
    function vacuousRule(RuleLocation memory location) internal pure returns (Issue memory) {
        return _issue(
            location,
            IssueSeverity.Info,
            IssueCategory.Vacuity,
            IssueCode.VACUOUS_RULE,
            bytes32(0),
            bytes32(0),
            "Rule holds for every value"
        );
    }

    /// @notice Creates an issue for a loop over a static array declared longer than the quantified maximum.
    /// @param location The loop.
    /// @param arrayLength The declared length of the array.
    /// @param maxLength The maximum quantified length.
    /// @return The constructed validation issue.
    function quantifierOverStaticLimit(
        RuleLocation memory location,
        uint256 arrayLength,
        uint256 maxLength
    )
        internal
        pure
        returns (Issue memory)
    {
        return _issue(
            location,
            IssueSeverity.Error,
            IssueCategory.Compatibility,
            IssueCode.QUANTIFIER_OVER_STATIC_LIMIT,
            bytes32(arrayLength),
            bytes32(maxLength),
            "Quantifier over static array exceeds the maximum quantified length"
        );
    }

    /// @notice Creates an issue for a loop body that contains no test of the element.
    /// @param location The loop.
    /// @return The constructed validation issue.
    function contextOnlyBody(RuleLocation memory location) internal pure returns (Issue memory) {
        return _issue(
            location,
            IssueSeverity.Error,
            IssueCategory.Compatibility,
            IssueCode.CONTEXT_ONLY_BODY,
            bytes32(0),
            bytes32(0),
            "Loop body holds no test of the element"
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns an issue naming the rule at `location`.
    function _issue(
        RuleLocation memory location,
        IssueSeverity severity,
        IssueCategory category,
        bytes32 code,
        bytes32 value1,
        bytes32 value2,
        string memory message
    )
        private
        pure
        returns (Issue memory)
    {
        return Issue({
            severity: severity,
            category: category,
            code: code,
            groupIndex: location.groupIndex,
            ruleIndex: location.ruleIndex,
            bodyRuleIndex: location.bodyRuleIndex,
            scope: location.scope,
            path: location.path,
            operator: location.operator,
            value1: value1,
            value2: value2,
            message: message
        });
    }
}

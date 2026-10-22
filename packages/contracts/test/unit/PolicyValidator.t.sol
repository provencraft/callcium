// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { arg } from "src/Constraint.sol";
import { Descriptor } from "src/Descriptor.sol";
import { DescriptorFormat as DF } from "src/DescriptorFormat.sol";
import { IssueCode } from "src/IssueCode.sol";
import { OpCode } from "src/OpCode.sol";
import { Path } from "src/Path.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";
import { PolicyValidator } from "src/PolicyValidator.sol";
import { TypeCode } from "src/TypeCode.sol";
import { Issue, IssueCategory, IssueSeverity, ValidationIssue } from "src/ValidationIssue.sol";

contract PolicyValidatorValidateTest is Test {
    /// @dev Returns the first issue validation reports on the validation vector `id`.
    function _firstIssue(string memory id) private view returns (Issue memory) {
        string memory json = vm.readFile("../../spec/vectors/validation.json");
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat(".[", vm.toString(i), "]")); ++i) {
            string memory key = string.concat(".[", vm.toString(i), "]");
            if (keccak256(bytes(vm.parseJsonString(json, string.concat(key, ".id")))) != keccak256(bytes(id))) {
                continue;
            }
            return PolicyValidator.validate(vm.parseJsonBytes(json, string.concat(key, ".blob")))[0];
        }
        revert(string.concat("no vector ", id));
    }

    /// @dev Asserts the severity, category, values and message of the first issue on the vector `id`.
    function _assertIssue(
        string memory id,
        IssueSeverity severity,
        IssueCategory category,
        uint256 value1,
        uint256 value2,
        string memory message
    )
        private
        view
    {
        Issue memory issue = _firstIssue(id);
        assertEq(uint8(issue.severity), uint8(severity), id);
        assertEq(uint8(issue.category), uint8(category), id);
        assertEq(issue.value1, bytes32(value1), id);
        assertEq(issue.value2, bytes32(value2), id);
        assertEq(issue.message, message, id);
    }

    function test_RevertWhen_BlobFailsStorageValidationBeforeAnalysis() public {
        bytes memory policy = PolicyBuilder.create("foo((uint256))").add(arg(0, 0).eq(uint256(1))).build();
        // The low byte of the tuple's field count, set to zero.
        policy[PF.POLICY_DESC_OFFSET + DF.HEADER_SIZE + DF.TUPLE_FIELDCOUNT_OFFSET + 1] = 0;

        vm.expectRevert(abi.encodeWithSelector(Descriptor.InvalidTupleFieldCount.selector, DF.HEADER_SIZE, 0));
        PolicyValidator.validate(policy);
    }

    function test_NamesARootTestByItsPositionPathAndOperator() public pure {
        bytes memory policy = PolicyBuilder.create("foo(address)").add(arg(0).gt(uint256(1))).buildUnsafe();

        Issue memory issue = PolicyValidator.validate(policy)[0];
        assertEq(issue.groupIndex, 0);
        assertEq(issue.ruleIndex, 0);
        assertEq(issue.bodyRuleIndex, ValidationIssue.NO_INDEX);
        assertEq(issue.scope, PF.SCOPE_CALLDATA);
        assertEq(issue.path, Path.encode(0));
        assertEq(issue.operator, abi.encodePacked(OpCode.GT, uint256(1)));
    }

    function test_NamesABodyTestByItsLoopPositionPathAndOperator() public pure {
        bytes memory policy =
            PolicyBuilder.create("foo((uint256,address)[])").add(arg(0, Path.ALL, 1).gt(uint256(1))).buildUnsafe();

        Issue[] memory issues = PolicyValidator.validate(policy);
        assertEq(issues.length, 1);
        Issue memory issue = issues[0];
        assertEq(issue.groupIndex, 0);
        assertEq(issue.ruleIndex, 0);
        assertEq(issue.bodyRuleIndex, 0);
        assertEq(issue.scope, PF.SCOPE_CALLDATA);
        assertEq(issue.path, Path.encode(1));
        assertEq(issue.operator, abi.encodePacked(OpCode.GT, uint256(1)));
        assertEq(uint8(issue.severity), uint8(IssueSeverity.Error));
        assertEq(uint8(issue.category), uint8(IssueCategory.TypeMismatch));
        assertEq(issue.code, IssueCode.NUMERIC_OP_ON_NON_NUMERIC);
        assertEq(issue.value1, bytes32(uint256(OpCode.GT)));
        assertEq(issue.value2, bytes32(0));
        assertEq(issue.message, "Comparison operator used on non-numeric type");
    }

    function test_IssuesCarryTheirCategorySeverityValuesAndMessage() public view {
        _assertIssue(
            "invalid-descriptor",
            IssueSeverity.Error,
            IssueCategory.TypeMismatch,
            3,
            0,
            "Descriptor node metadata disagrees with its children"
        );
        _assertIssue(
            "unnavigable-path",
            IssueSeverity.Error,
            IssueCategory.TypeMismatch,
            1,
            2,
            "Path does not navigate the descriptor"
        );
        _assertIssue(
            "quantifier-on-non-array",
            IssueSeverity.Error,
            IssueCategory.TypeMismatch,
            TypeCode.UINT256,
            0,
            "Loop path does not end at an array"
        );
        _assertIssue(
            "hint-mismatch",
            IssueSeverity.Error,
            IssueCategory.TypeMismatch,
            0,
            0,
            "Hint does not match the path compiled against the descriptor"
        );
        _assertIssue(
            "context-operand-on-signed",
            IssueSeverity.Error,
            IssueCategory.TypeMismatch,
            PF.CTX_MSG_VALUE,
            TypeCode.INT256,
            "Context property type does not match the target type"
        );
        _assertIssue(
            "bool-operand-two",
            IssueSeverity.Error,
            IssueCategory.Contradiction,
            2,
            0,
            "Value is outside the physical range of the type"
        );
        _assertIssue(
            "quantifier-over-static-limit",
            IssueSeverity.Error,
            IssueCategory.Compatibility,
            PF.MAX_QUANTIFIED_ARRAY_LENGTH + 1,
            PF.MAX_QUANTIFIED_ARRAY_LENGTH,
            "Quantifier over static array exceeds the maximum quantified length"
        );
        _assertIssue(
            "mask-contradiction",
            IssueSeverity.Error,
            IssueCategory.Contradiction,
            0,
            0,
            "Rules on the subject are not satisfiable together"
        );
        _assertIssue(
            "bound-implied-by-mask",
            IssueSeverity.Warning,
            IssueCategory.Redundancy,
            0,
            0,
            "Rule is implied by the other rules on its subject"
        );
        _assertIssue(
            "signed-dominated-bound",
            IssueSeverity.Warning,
            IssueCategory.Redundancy,
            uint256(int256(-10)),
            uint256(int256(-2)),
            "Numeric bound is dominated by a stricter bound"
        );
        _assertIssue(
            "int256-dominated-bound",
            IssueSeverity.Warning,
            IssueCategory.Redundancy,
            uint256(type(int256).min),
            uint256(type(int256).min + 1),
            "Numeric bound is dominated by a stricter bound"
        );
        _assertIssue(
            "dominated-length-bound",
            IssueSeverity.Warning,
            IssueCategory.Redundancy,
            10,
            4,
            "Length bound is dominated by a stricter bound"
        );
        _assertIssue("vacuous-length", IssueSeverity.Info, IssueCategory.Vacuity, 0, 0, "Rule holds for every value");
        _assertIssue(
            "context-only-all-body",
            IssueSeverity.Error,
            IssueCategory.Compatibility,
            0,
            0,
            "Loop body holds no test of the element"
        );
    }
}

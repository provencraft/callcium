// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Constraint } from "src/Constraint.sol";
import { PolicyData } from "src/PolicyCoder.sol";
import { Issue, IssueCategory, IssueSeverity } from "src/ValidationIssue.sol";

import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for PolicyValidator unit tests.
abstract contract PolicyValidatorTest is BaseTest {
    /// @dev Compares two IssueSeverity values for equality.
    function assertEq(IssueSeverity a, IssueSeverity b) internal pure {
        assertEq(uint8(a), uint8(b));
    }

    /// @dev Compares two IssueCategory values for equality.
    function assertEq(IssueCategory a, IssueCategory b) internal pure {
        assertEq(uint8(a), uint8(b));
    }

    /// @dev Finds and returns the first issue matching the given code. Fails if not found.
    function _findIssue(Issue[] memory issues, bytes32 code) internal pure returns (Issue memory) {
        for (uint256 i; i < issues.length; ++i) {
            if (issues[i].code == code) return issues[i];
        }
        revert("Issue not found");
    }

    /// @dev Asserts that at least one issue with the given code exists.
    function _assertIssue(Issue[] memory issues, bytes32 code) internal pure {
        _findIssue(issues, code);
    }

    /// @dev Asserts no issue with the given code exists.
    function _assertNoIssue(Issue[] memory issues, bytes32 code) internal pure {
        for (uint256 i; i < issues.length; ++i) {
            assertTrue(issues[i].code != code);
        }
    }

    /// @dev Helper to create a PolicyData with a single group and single constraint.
    function _createPolicyData(
        string memory sig,
        bytes memory desc,
        Constraint memory constraint
    )
        internal
        pure
        returns (PolicyData memory)
    {
        Constraint[][] memory groups = new Constraint[][](1);
        groups[0] = new Constraint[](1);
        groups[0][0] = constraint;

        bytes4 selector = bytes4(keccak256(bytes(sig)));
        return PolicyData({ isSelectorless: false, selector: selector, descriptor: desc, groups: groups });
    }

    /// @dev Helper to create a PolicyData with multiple constraints in one group.
    function _createPolicyDataMulti(
        string memory sig,
        bytes memory desc,
        Constraint[] memory constraints
    )
        internal
        pure
        returns (PolicyData memory)
    {
        Constraint[][] memory groups = new Constraint[][](1);
        groups[0] = constraints;

        bytes4 selector = bytes4(keccak256(bytes(sig)));
        return PolicyData({ isSelectorless: false, selector: selector, descriptor: desc, groups: groups });
    }

    /// @dev Appends an encoded operator to an existing operator array.
    function _appendOp(bytes[] memory ops, uint8 opCode, bytes memory data) internal pure returns (bytes[] memory) {
        bytes[] memory next = new bytes[](ops.length + 1);
        for (uint256 i; i < ops.length; ++i) {
            next[i] = ops[i];
        }
        next[ops.length] = abi.encodePacked(opCode, data);
        return next;
    }
}

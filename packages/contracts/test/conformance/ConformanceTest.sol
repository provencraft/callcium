// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { CalldataReader } from "src/CalldataReader.sol";
import { Descriptor } from "src/Descriptor.sol";
import { Hint } from "src/Hint.sol";
import { Policy } from "src/Policy.sol";
import { PolicyCoder } from "src/PolicyCoder.sol";
import { PolicyEnforcer } from "src/PolicyEnforcer.sol";
import { Issue, ValidationIssue } from "src/ValidationIssue.sol";

import { PolicyCoderHarness } from "test/harnesses/PolicyCoderHarness.sol";

/// @notice Shared reading of the vector files, re-encoding through the encoder, and the spelling of aborts and issues.
abstract contract ConformanceTest is Test {
    error UnknownFixtureError(string name);

    /// @dev Counts the entries of the top-level array in `json`.
    function _vectorCount(string memory json) internal view returns (uint256 count) {
        while (vm.keyExistsJson(json, string.concat(".[", vm.toString(count), "]"))) ++count;
    }

    /// @dev Encodes the policy `blob` states through the unchecked encoder; empty where re-encoding refuses a
    /// descriptor whose composite node disagrees with its children, a path that does not compile, a comparison or a
    /// constant. Any other revert fails the test.
    function _reencode(PolicyCoderHarness coder, bytes memory blob) internal pure returns (bytes memory) {
        try coder.reencode(blob) returns (bytes memory encoded) {
            return encoded;
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertTrue(
                selector == Descriptor.NodeLengthMismatch.selector
                    || selector == Descriptor.StaticWordsMismatch.selector
                    || selector == Descriptor.ParamIndexOutOfBounds.selector
                    || selector == Descriptor.TupleFieldOutOfBounds.selector
                    || selector == Descriptor.StaticArrayIndexOutOfBounds.selector
                    || selector == Descriptor.NotComposite.selector || selector == Hint.QuantifierOnNonArray.selector
                    || selector == PolicyCoder.OutOfPhysicalBounds.selector
                    || selector == PolicyCoder.OperatorTargetMismatch.selector,
                "unexpected encoder revert"
            );
            return "";
        }
    }

    /// @dev Returns the spelling of the abort `reason` encodes, or "integrity" for an error the enforcer raises at
    /// entry. Any other revert fails the test.
    function _abortCode(bytes memory reason) internal pure returns (string memory) {
        // An abort is a custom error; a panic or a revert without data is a crash in the enforcer.
        assertTrue(reason.length >= 4, "enforcer crashed");
        bytes4 selector = bytes4(reason);
        if (selector == CalldataReader.CalldataOutOfBounds.selector) return "CALLDATA_OUT_OF_BOUNDS";
        if (selector == PolicyEnforcer.NonCanonicalValue.selector) return "NON_CANONICAL_VALUE";
        if (selector == PolicyEnforcer.QuantifierLimitExceeded.selector) return "QUANTIFIER_LIMIT_EXCEEDED";
        if (selector == PolicyEnforcer.MissingSelector.selector) return "MISSING_SELECTOR";
        if (selector == PolicyEnforcer.SelectorMismatch.selector) return "SELECTOR_MISMATCH";
        bool isIntegrity = selector == Policy.MalformedHeader.selector || selector == Policy.UnsupportedVersion.selector
            || selector == PolicyEnforcer.UnsupportedMinor.selector;
        assertTrue(isIntegrity, "enforcer crashed");
        return "integrity";
    }

    /// @dev Returns the keys of `issues`.
    function _issueKeys(Issue[] memory issues) internal pure returns (string[] memory keys) {
        keys = new string[](issues.length);
        for (uint256 i = 0; i < issues.length; ++i) {
            keys[i] = _issueKey(issues[i]);
        }
    }

    /// @dev Asserts that `actual` and `expected` hold the same issue keys, in any order.
    function _assertSameIssues(string[] memory actual, string[] memory expected, string memory label) internal pure {
        assertEq(actual.length, expected.length, label);
        for (uint256 i = 0; i < expected.length; ++i) {
            assertEq(_occurrences(actual, expected[i]), _occurrences(expected, expected[i]), label);
        }
    }

    /// @dev Returns an issue as the vectors and the validation corpus spell it: its code, then its rule's indices.
    function _issueKey(Issue memory issue) private pure returns (string memory key) {
        bytes memory code = abi.encodePacked(issue.code);
        uint256 length = 0;
        while (length < code.length && code[length] != 0) ++length;
        assembly ("memory-safe") {
            mstore(code, length)
        }
        key = string(code);
        if (issue.groupIndex == ValidationIssue.NO_INDEX) return key;
        key = string.concat(key, "@", vm.toString(issue.groupIndex), ".", vm.toString(issue.ruleIndex));
        if (issue.bodyRuleIndex != ValidationIssue.NO_INDEX) {
            key = string.concat(key, ".", vm.toString(issue.bodyRuleIndex));
        }
    }

    /// @dev Returns how many entries of `keys` equal `key`.
    function _occurrences(string[] memory keys, string memory key) private pure returns (uint256 count) {
        for (uint256 i = 0; i < keys.length; ++i) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(key))) ++count;
        }
    }
}

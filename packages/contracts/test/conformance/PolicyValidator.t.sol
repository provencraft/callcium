// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyData } from "src/PolicyCoder.sol";
import { PolicyValidator } from "src/PolicyValidator.sol";
import { Issue, IssueSeverity } from "src/ValidationIssue.sol";

import { ConformanceTest } from "test/conformance/ConformanceTest.sol";

// forge-lint: disable-next-item(unsafe-cheatcode)
contract PolicyValidatorConformanceTest is ConformanceTest {
    struct IssueFixture {
        /// @dev Machine-readable issue code (e.g., "DOMINATED_BOUND").
        string code;
        /// @dev Constraint index within the group.
        uint256 constraintIndex;
        /// @dev Group index the issue is reported on.
        uint256 groupIndex;
        /// @dev Issue severity name ("info", "warning", or "error").
        string severity;
    }

    struct ValidationFixture {
        /// @dev Whether the strict build() gate accepts the policy (true iff issues is empty).
        bool builds;
        /// @dev Human-readable description of the test case.
        string description;
        /// @dev Unique fixture identifier.
        string id;
        /// @dev Expected issue multiset.
        IssueFixture[] issues;
        // "policy" key in JSON sorts after "issues" and is parsed separately (nested dynamic arrays).
    }

    /// @dev Loads and parses all fixtures from the validation vector file, also returning the raw JSON for path lookups.
    function _fixtures() private view returns (string memory json, ValidationFixture[] memory fixtures) {
        json = vm.readFile("../../spec/vectors/validation.json");
        uint256 count = _vectorCount(json);
        fixtures = new ValidationFixture[](count);
        for (uint256 i = 0; i < count; ++i) {
            fixtures[i] = abi.decode(vm.parseJson(json, string.concat(".[", vm.toString(i), "]")), (ValidationFixture));
        }
    }

    /// @dev Asserts the actual issues match the fixture's expected multiset (order-insensitive).
    function _assertIssues(Issue[] memory actual, IssueFixture[] memory expected, string memory id) private pure {
        assertEq(actual.length, expected.length, string.concat(id, ": issue count"));

        bool[] memory used = new bool[](actual.length);
        for (uint256 i = 0; i < expected.length; ++i) {
            bytes32 code = bytes32(bytes(expected[i].code));
            IssueSeverity severity = _severity(expected[i].severity);

            bool matched;
            for (uint256 j = 0; j < actual.length; ++j) {
                if (used[j]) continue;
                if (
                    actual[j].code == code && actual[j].severity == severity
                        && actual[j].groupIndex == expected[i].groupIndex
                        && actual[j].constraintIndex == expected[i].constraintIndex
                ) {
                    used[j] = true;
                    matched = true;
                    break;
                }
            }
            assertTrue(matched, string.concat(id, ": missing expected issue ", expected[i].code));
        }
    }

    /// @dev Maps a severity string to the enum.
    function _severity(string memory name) private pure returns (IssueSeverity) {
        bytes32 h = keccak256(bytes(name));
        if (h == keccak256("info")) return IssueSeverity.Info;
        if (h == keccak256("warning")) return IssueSeverity.Warning;
        return IssueSeverity.Error;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                SPECIFICATION TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_ValidatesConformWithSpecification() public view {
        (string memory json, ValidationFixture[] memory fixtures) = _fixtures();
        for (uint256 i = 0; i < fixtures.length; ++i) {
            ValidationFixture memory f = fixtures[i];

            PolicyData memory data = _policyData(json, vm.toString(i));
            Issue[] memory actual = PolicyValidator.validate(data);

            _assertIssues(actual, f.issues, f.id);
            assertEq(f.builds, actual.length == 0, string.concat(f.id, ": builds flag"));
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Constraint } from "src/Constraint.sol";
import { PolicyData } from "src/PolicyCoder.sol";
import { PolicyValidator } from "src/PolicyValidator.sol";
import { Issue, IssueSeverity } from "src/ValidationIssue.sol";

import { BaseTest } from "test/unit/BaseTest.sol";

// forge-lint: disable-next-item(unsafe-cheatcode)
contract PolicyValidatorConformanceTest is BaseTest {
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
        json = vm.readFile("test/vectors/validation.json");
        uint256 count;
        while (vm.keyExistsJson(json, string.concat(".[", vm.toString(count), "]"))) ++count;
        fixtures = new ValidationFixture[](count);
        for (uint256 i; i < count; ++i) {
            fixtures[i] = abi.decode(vm.parseJson(json, string.concat(".[", vm.toString(i), "]")), (ValidationFixture));
        }
    }

    /// @dev Builds a PolicyData from the fixture's policy object at the given index.
    function _policyData(string memory json, string memory indexString) private view returns (PolicyData memory data) {
        string memory policyPath = string.concat(".[", indexString, "].policy");

        data.isSelectorless = vm.parseJsonBool(json, string.concat(policyPath, ".isSelectorless"));
        data.selector = bytes4(vm.parseJsonBytes(json, string.concat(policyPath, ".selector")));
        data.descriptor = vm.parseJsonBytes(json, string.concat(policyPath, ".descriptor"));

        uint256 groupCount;
        while (vm.keyExistsJson(json, string.concat(policyPath, ".groups[", vm.toString(groupCount), "]"))) {
            ++groupCount;
        }

        data.groups = new Constraint[][](groupCount);
        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            string memory groupPath = string.concat(policyPath, ".groups[", vm.toString(groupIndex), "].constraints");
            uint256 constraintCount;
            while (vm.keyExistsJson(json, string.concat(groupPath, "[", vm.toString(constraintCount), "]"))) {
                ++constraintCount;
            }
            data.groups[groupIndex] = new Constraint[](constraintCount);
            for (uint256 constraintIndex; constraintIndex < constraintCount; ++constraintIndex) {
                string memory constraintPath = string.concat(groupPath, "[", vm.toString(constraintIndex), "]");
                uint256 operatorCount;
                while (vm.keyExistsJson(
                        json, string.concat(constraintPath, ".operators[", vm.toString(operatorCount), "]")
                    )) ++operatorCount;
                bytes[] memory operators = new bytes[](operatorCount);
                for (uint256 operatorIndex; operatorIndex < operatorCount; ++operatorIndex) {
                    operators[operatorIndex] = vm.parseJsonBytes(
                        json, string.concat(constraintPath, ".operators[", vm.toString(operatorIndex), "]")
                    );
                }
                // forge-lint: disable-next-line(unsafe-typecast)
                data.groups[groupIndex][constraintIndex] = Constraint({
                    scope: uint8(vm.parseJsonUint(json, string.concat(constraintPath, ".scope"))),
                    path: vm.parseJsonBytes(json, string.concat(constraintPath, ".path")),
                    operators: operators
                });
            }
        }
    }

    /// @dev Asserts the actual issues match the fixture's expected multiset (order-insensitive).
    function _assertIssues(Issue[] memory actual, IssueFixture[] memory expected, string memory id) private pure {
        assertEq(actual.length, expected.length, string.concat(id, ": issue count"));

        bool[] memory used = new bool[](actual.length);
        for (uint256 i; i < expected.length; ++i) {
            bytes32 code = bytes32(bytes(expected[i].code));
            IssueSeverity severity = _severity(expected[i].severity);

            bool matched;
            for (uint256 j; j < actual.length; ++j) {
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
        for (uint256 i; i < fixtures.length; ++i) {
            ValidationFixture memory f = fixtures[i];

            PolicyData memory data = _policyData(json, vm.toString(i));
            Issue[] memory actual = PolicyValidator.validate(data);

            _assertIssues(actual, f.issues, f.id);
            assertEq(f.builds, actual.length == 0, string.concat(f.id, ": builds flag"));
        }
    }
}

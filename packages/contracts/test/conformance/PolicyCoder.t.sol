// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Constraint } from "src/Constraint.sol";
import { Policy } from "src/Policy.sol";
import { PolicyCoder, PolicyData } from "src/PolicyCoder.sol";

import { BaseTest } from "test/unit/BaseTest.sol";

// forge-lint: disable-next-item(unsafe-cheatcode)
contract PolicyCoderConformanceTest is BaseTest {
    struct PolicyFixture {
        /// @dev Expected encoded policy blob.
        bytes blob;
        /// @dev Human-readable description of the test case.
        string description;
        /// @dev Expected error name, or empty string for valid cases.
        string error;
        /// @dev ABI-encoded 32-byte arguments for the expected error, or empty.
        bytes32[] errorArgs;
        /// @dev Unique fixture identifier.
        string id;
        // "spec" key in JSON (decoded + encodingInput) sorts after "id" and is parsed separately.
    }

    error UnknownFixtureError(string name);

    /// @dev External wrapper so `vm.expectRevert` can intercept reverts from decode.
    function decode(bytes memory blob) external pure returns (PolicyData memory) {
        return PolicyCoder.decode(blob);
    }

    /// @dev Maps a fixture error name to its error selector.
    function _errorSelector(string memory name) private pure returns (bytes4) {
        bytes32 h = keccak256(bytes(name));
        if (h == keccak256("EmptyGroup")) return Policy.EmptyGroup.selector;
        if (h == keccak256("EmptyPath")) return Policy.EmptyPath.selector;
        if (h == keccak256("EmptyPolicy")) return Policy.EmptyPolicy.selector;
        if (h == keccak256("GroupOverflow")) return Policy.GroupOverflow.selector;
        if (h == keccak256("GroupSizeMismatch")) return Policy.GroupSizeMismatch.selector;
        if (h == keccak256("GroupTooSmall")) return Policy.GroupTooSmall.selector;
        if (h == keccak256("InvalidContextPath")) return Policy.InvalidContextPath.selector;
        if (h == keccak256("InvalidScope")) return Policy.InvalidScope.selector;
        if (h == keccak256("MalformedHeader")) return Policy.MalformedHeader.selector;
        if (h == keccak256("RuleOverflow")) return Policy.RuleOverflow.selector;
        if (h == keccak256("RuleSizeMismatch")) return Policy.RuleSizeMismatch.selector;
        if (h == keccak256("RuleTooSmall")) return Policy.RuleTooSmall.selector;
        if (h == keccak256("UnexpectedEnd")) return Policy.UnexpectedEnd.selector;
        if (h == keccak256("UnknownOperator")) return Policy.UnknownOperator.selector;
        if (h == keccak256("UnsupportedVersion")) return Policy.UnsupportedVersion.selector;
        revert UnknownFixtureError(name);
    }

    /// @dev Reads the first four bytes of a byte array as a bytes4 value.
    function _toBytes4(bytes memory b) internal pure returns (bytes4 r) {
        assembly ("memory-safe") {
            r := mload(add(b, 32))
        }
    }

    /// @dev Loads and parses all fixtures from the policy vector file, also returning the raw JSON for path lookups.
    function _loadFixtures() private view returns (string memory json, PolicyFixture[] memory fixtures) {
        json = vm.readFile("test/vectors/policies.json");
        uint256 count;
        while (vm.keyExistsJson(json, string.concat(".[", vm.toString(count), "]"))) ++count;
        fixtures = new PolicyFixture[](count);
        for (uint256 i; i < count; ++i) {
            fixtures[i] = abi.decode(vm.parseJson(json, string.concat(".[", vm.toString(i), "]")), (PolicyFixture));
        }
    }

    /// @dev Encodes the fixture at the given index from the raw JSON into a policy blob.
    function _encode(string memory json, string memory indexString) private view returns (bytes memory) {
        string memory encodingInputPath = string.concat(".[", indexString, "].spec.encodingInput");

        bool isSelectorless = vm.parseJsonBool(json, string.concat(encodingInputPath, ".isSelectorless"));
        uint256 groupCount;
        while (vm.keyExistsJson(json, string.concat(encodingInputPath, ".groups[", vm.toString(groupCount), "]"))) {
            ++groupCount;
        }

        PolicyCoder.Group[] memory groups = new PolicyCoder.Group[](groupCount);
        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            string memory groupPath = string.concat(encodingInputPath, ".groups[", vm.toString(groupIndex), "]");
            uint256 ruleCount;
            while (vm.keyExistsJson(json, string.concat(groupPath, ".rules[", vm.toString(ruleCount), "]"))) {
                ++ruleCount;
            }
            groups[groupIndex].rules = new PolicyCoder.Rule[](ruleCount);
            for (uint256 ruleIndex; ruleIndex < ruleCount; ++ruleIndex) {
                string memory rulePath = string.concat(groupPath, ".rules[", vm.toString(ruleIndex), "]");
                // forge-lint: disable-next-line(unsafe-typecast)
                groups[groupIndex].rules[ruleIndex].scope =
                    uint8(vm.parseJsonUint(json, string.concat(rulePath, ".scope")));
                groups[groupIndex].rules[ruleIndex].path = vm.parseJsonBytes(json, string.concat(rulePath, ".path"));
                groups[groupIndex].rules[ruleIndex].operator =
                    vm.parseJsonBytes(json, string.concat(rulePath, ".operator"));
            }
        }

        bytes memory descriptor = vm.parseJsonBytes(json, string.concat(encodingInputPath, ".descriptor"));

        if (isSelectorless) {
            // PolicyCoder.encode(PolicyData) is required for the selectorless flag.
            // Convert the flat Rule[] into Constraint[][] (each rule becomes one Constraint
            // since selectorless fixtures never share (scope, path) across rules).
            Constraint[][] memory constraints = new Constraint[][](groupCount);
            for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
                constraints[groupIndex] = new Constraint[](groups[groupIndex].rules.length);
                for (uint256 ruleIndex; ruleIndex < groups[groupIndex].rules.length; ++ruleIndex) {
                    bytes[] memory operators = new bytes[](1);
                    operators[0] = groups[groupIndex].rules[ruleIndex].operator;
                    // forgefmt: disable-next-item
                    constraints[groupIndex][ruleIndex] = Constraint({ scope: groups[groupIndex].rules[ruleIndex].scope, path: groups[groupIndex].rules[ruleIndex].path, operators: operators });
                }
            }
            PolicyData memory data;
            data.isSelectorless = true;
            data.selector = bytes4(0);
            data.descriptor = descriptor;
            data.groups = constraints;
            return PolicyCoder.encode(data);
        }
        bytes memory selector = vm.parseJsonBytes(json, string.concat(encodingInputPath, ".selector"));
        return PolicyCoder.encode(groups, _toBytes4(selector), descriptor);
    }

    /// @dev Asserts the decoded fields of a policy against the expected fixture values.
    function _assertDecoded(
        PolicyData memory data,
        string memory json,
        string memory indexString,
        string memory id
    )
        private
    {
        string memory decodedPath = string.concat(".[", indexString, "].spec.decoded");
        assertEq(data.isSelectorless, vm.parseJsonBool(json, string.concat(decodedPath, ".isSelectorless")), id);
        assertEq(data.selector, _toBytes4(vm.parseJsonBytes(json, string.concat(decodedPath, ".selector"))), id);
        assertEq(
            keccak256(data.descriptor),
            keccak256(vm.parseJsonBytes(json, string.concat(decodedPath, ".descriptor"))),
            id
        );
        uint256 groupCount;
        while (vm.keyExistsJson(json, string.concat(decodedPath, ".groups[", vm.toString(groupCount), "]"))) {
            ++groupCount;
        }
        assertEq(data.groups.length, groupCount, id);
        for (uint256 groupIndex; groupIndex < data.groups.length; ++groupIndex) {
            _assertGroup(
                data.groups[groupIndex], json, decodedPath, groupIndex, string.concat(id, ":g", vm.toString(groupIndex))
            );
        }
    }

    /// @dev Asserts a single constraint group against the expected fixture values.
    function _assertGroup(
        Constraint[] memory group,
        string memory json,
        string memory decodedPath,
        uint256 groupIndex,
        string memory groupLabel
    )
        private
        view
    {
        string memory groupPath = string.concat(decodedPath, ".groups[", vm.toString(groupIndex), "]");
        uint256 constraintCount;
        while (vm.keyExistsJson(json, string.concat(groupPath, ".constraints[", vm.toString(constraintCount), "]"))) {
            ++constraintCount;
        }
        assertEq(group.length, constraintCount, string.concat(groupLabel, ".constraints.length"));
        for (uint256 constraintIndex; constraintIndex < group.length; ++constraintIndex) {
            string memory constraintPath = string.concat(groupPath, ".constraints[", vm.toString(constraintIndex), "]");
            string memory constraintLabel = string.concat(groupLabel, "c", vm.toString(constraintIndex));
            assertEq(
                uint256(group[constraintIndex].scope),
                vm.parseJsonUint(json, string.concat(constraintPath, ".scope")),
                string.concat(constraintLabel, ".scope")
            );
            assertEq(
                keccak256(group[constraintIndex].path),
                keccak256(vm.parseJsonBytes(json, string.concat(constraintPath, ".path"))),
                string.concat(constraintLabel, ".path")
            );
            uint256 opCount;
            while (vm.keyExistsJson(json, string.concat(constraintPath, ".operators[", vm.toString(opCount), "]"))) {
                ++opCount;
            }
            assertEq(
                group[constraintIndex].operators.length, opCount, string.concat(constraintLabel, ".operators.length")
            );
            for (uint256 operatorIndex; operatorIndex < group[constraintIndex].operators.length; ++operatorIndex) {
                bytes memory op = vm.parseJsonBytes(
                    json, string.concat(constraintPath, ".operators[", vm.toString(operatorIndex), "]")
                );
                assertEq(
                    keccak256(group[constraintIndex].operators[operatorIndex]),
                    keccak256(op),
                    string.concat(constraintLabel, "op", vm.toString(operatorIndex))
                );
            }
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                                SPECIFICATION TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_DecodesConformWithSpecification() public {
        (string memory json, PolicyFixture[] memory fixtures) = _loadFixtures();
        for (uint256 i; i < fixtures.length; ++i) {
            PolicyFixture memory f = fixtures[i];
            if (bytes(f.error).length > 0) {
                bytes4 sel = _errorSelector(f.error);
                bytes memory revertData = abi.encodePacked(sel);
                for (uint256 j; j < f.errorArgs.length; ++j) {
                    revertData = bytes.concat(revertData, f.errorArgs[j]);
                }
                vm.expectRevert(revertData);
                this.decode(f.blob);
                continue;
            }
            PolicyData memory data = PolicyCoder.decode(f.blob);
            _assertDecoded(data, json, vm.toString(i), f.id);
        }
    }

    function test_EncodesConformWithSpecification() public {
        (string memory json, PolicyFixture[] memory fixtures) = _loadFixtures();
        for (uint256 i; i < fixtures.length; ++i) {
            PolicyFixture memory f = fixtures[i];
            if (bytes(f.error).length > 0) continue;
            assertEq(keccak256(_encode(json, vm.toString(i))), keccak256(f.blob), f.id);
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Descriptor } from "src/Descriptor.sol";
import { Policy } from "src/Policy.sol";

import { ConformanceTest } from "test/conformance/ConformanceTest.sol";
import { PolicyCoderHarness } from "test/harnesses/PolicyCoderHarness.sol";
import { PolicyHarness } from "test/harnesses/PolicyHarness.sol";

contract PolicyConformanceTest is ConformanceTest {
    PolicyHarness internal harness;
    PolicyCoderHarness internal coder;

    function setUp() public {
        harness = new PolicyHarness();
        coder = new PolicyCoderHarness();
    }

    /// @dev Maps a vector error name to its error selector.
    function _errorSelector(string memory name) private pure returns (bytes4) {
        bytes32 nameHash = keccak256(bytes(name));
        if (nameHash == keccak256("DataLengthMismatch")) return Policy.DataLengthMismatch.selector;
        if (nameHash == keccak256("EmptyGroup")) return Policy.EmptyGroup.selector;
        if (nameHash == keccak256("EmptyPath")) return Policy.EmptyPath.selector;
        if (nameHash == keccak256("EmptyPolicy")) return Policy.EmptyPolicy.selector;
        if (nameHash == keccak256("GroupOverflow")) return Policy.GroupOverflow.selector;
        if (nameHash == keccak256("GroupSizeMismatch")) return Policy.GroupSizeMismatch.selector;
        if (nameHash == keccak256("InvalidContextOperand")) return Policy.InvalidContextOperand.selector;
        if (nameHash == keccak256("InvalidContextPath")) return Policy.InvalidContextPath.selector;
        if (nameHash == keccak256("InvalidNestedLoop")) return Policy.InvalidNestedLoop.selector;
        if (nameHash == keccak256("MalformedHeader")) return Policy.MalformedHeader.selector;
        if (nameHash == keccak256("MalformedHint")) return Policy.MalformedHint.selector;
        if (nameHash == keccak256("MinorMismatch")) return Policy.MinorMismatch.selector;
        if (nameHash == keccak256("OperatorTargetMismatch")) return Policy.OperatorTargetMismatch.selector;
        if (nameHash == keccak256("ParamCountMismatch")) return Descriptor.ParamCountMismatch.selector;
        if (nameHash == keccak256("PathTooDeep")) return Policy.PathTooDeep.selector;
        if (nameHash == keccak256("RuleOverflow")) return Policy.RuleOverflow.selector;
        if (nameHash == keccak256("RuleSizeMismatch")) return Policy.RuleSizeMismatch.selector;
        if (nameHash == keccak256("RuleTooSmall")) return Policy.RuleTooSmall.selector;
        if (nameHash == keccak256("TrailingBytes")) return Policy.TrailingBytes.selector;
        if (nameHash == keccak256("UnexpectedEnd")) return Policy.UnexpectedEnd.selector;
        if (nameHash == keccak256("UnknownContextProperty")) return Policy.UnknownContextProperty.selector;
        if (nameHash == keccak256("UnknownOperator")) return Policy.UnknownOperator.selector;
        if (nameHash == keccak256("UnknownPathStep")) return Policy.UnknownPathStep.selector;
        if (nameHash == keccak256("UnknownQuantifier")) return Policy.UnknownQuantifier.selector;
        if (nameHash == keccak256("UnknownScope")) return Policy.UnknownScope.selector;
        if (nameHash == keccak256("UnsortedInSet")) return Policy.UnsortedInSet.selector;
        if (nameHash == keccak256("UnsupportedVersion")) return Policy.UnsupportedVersion.selector;
        revert UnknownFixtureError(name);
    }

    /// @dev Validates `blob`, returning whether it is accepted and the revert data otherwise.
    function _validate(bytes memory blob) private view returns (bool accepted, bytes memory reason) {
        try harness.validate(blob) {
            accepted = true;
        } catch (bytes memory revertData) {
            reason = revertData;
        }
    }

    function test_ValidatesConformWithSpecification() public view {
        string memory json = vm.readFile("../../spec/vectors/policies.json");
        uint256 count = _vectorCount(json);
        assertGt(count, 0, "no vectors");
        for (uint256 i = 0; i < count; ++i) {
            string memory key = string.concat(".[", vm.toString(i), "]");
            string memory id = vm.parseJsonString(json, string.concat(key, ".id"));
            string memory expected = vm.parseJsonString(json, string.concat(key, ".error"));
            (bool accepted, bytes memory reason) = _validate(vm.parseJsonBytes(json, string.concat(key, ".blob")));
            if (bytes(expected).length == 0) {
                assertTrue(accepted, id);
                bool canonical = vm.parseJsonBool(json, string.concat(key, ".canonical"));
                bytes memory blob = vm.parseJsonBytes(json, string.concat(key, ".blob"));
                assertEq(keccak256(_reencode(coder, blob)) == keccak256(blob), canonical, id);
            } else {
                assertFalse(accepted, id);
                assertEq(bytes4(reason), _errorSelector(expected), id);
            }
        }
    }
}

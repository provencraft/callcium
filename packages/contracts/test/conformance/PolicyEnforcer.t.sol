// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CalldataReader } from "src/CalldataReader.sol";
import { PolicyCoder } from "src/PolicyCoder.sol";
import { PolicyEnforcer } from "src/PolicyEnforcer.sol";

import { ConformanceTest } from "test/conformance/ConformanceTest.sol";
import { PolicyEnforcerHarness } from "test/harnesses/PolicyEnforcerHarness.sol";

// forge-lint: disable-next-item(unsafe-cheatcode)
contract PolicyEnforcerConformanceTest is ConformanceTest {
    // "context", "expected", "expectedError", and "violations" are present only on the vectors that need them, so
    // entries are read key by key rather than decoded into a fixture struct.

    PolicyEnforcerHarness private harness;

    function setUp() public {
        harness = new PolicyEnforcerHarness();
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    HELPERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Maps a violation code to the selector the enforcer reverts with.
    function _errorSelector(string memory code) private pure returns (bytes4) {
        bytes32 h = keccak256(bytes(code));
        if (h == keccak256("CALLDATA_OUT_OF_BOUNDS")) return CalldataReader.CalldataOutOfBounds.selector;
        if (h == keccak256("ARRAY_INDEX_OUT_OF_BOUNDS")) return CalldataReader.ArrayIndexOutOfBounds.selector;
        if (h == keccak256("NON_CANONICAL_VALUE")) return PolicyEnforcer.NonCanonicalValue.selector;
        if (h == keccak256("QUANTIFIER_LIMIT_EXCEEDED")) return PolicyEnforcer.QuantifierLimitExceeded.selector;
        if (h == keccak256("SELECTOR_MISMATCH")) return PolicyEnforcer.SelectorMismatch.selector;
        if (h == keccak256("MISSING_SELECTOR")) return PolicyEnforcer.MissingSelector.selector;
        revert(string.concat("Unmapped violation code: ", code));
    }

    /// @dev Runs one vector under its declared context, returning the enforcement verdict.
    function _check(
        string memory json,
        string memory indexString,
        bytes memory policy,
        bytes memory callData
    )
        private
        returns (bool)
    {
        string memory ctxPath = string.concat(".[", indexString, "].context");
        if (!vm.keyExistsJson(json, ctxPath)) return harness.check(policy, callData);

        address sender = vm.parseAddress(vm.parseJsonString(json, string.concat(ctxPath, ".msgSender")));
        uint256 value = uint256(vm.parseBytes32(vm.parseJsonString(json, string.concat(ctxPath, ".msgValue"))));
        uint256 baseFee = uint256(vm.parseBytes32(vm.parseJsonString(json, string.concat(ctxPath, ".baseFee"))));
        uint256 gasPrice = uint256(vm.parseBytes32(vm.parseJsonString(json, string.concat(ctxPath, ".gasPrice"))));

        vm.fee(baseFee);
        vm.txGasPrice(gasPrice);

        // A view call observes the pinned fee fields. A value-bearing call cannot be view, and under
        // the isolate profile it lands in a fresh block whose fee fields are recomputed, so the two
        // context kinds cannot be pinned in the same vector.
        if (value == 0) {
            // The txOrigin field appears only on vectors that pin it; the default origin is a
            // nonzero sentinel, so those vectors always set it explicitly.
            string memory originPath = string.concat(ctxPath, ".txOrigin");
            if (vm.keyExistsJson(json, originPath)) {
                vm.prank(sender, vm.parseAddress(vm.parseJsonString(json, originPath)));
            } else {
                vm.prank(sender);
            }
            return harness.check(policy, callData);
        }

        require(baseFee == 0 && gasPrice == 0, "Vector pins both a call value and a fee field");
        require(
            !vm.keyExistsJson(json, string.concat(ctxPath, ".txOrigin")), "Vector pins both a call value and txOrigin"
        );
        vm.deal(sender, value);
        vm.prank(sender);
        return harness.checkPayable{ value: value }(policy, callData);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                SPECIFICATION TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_EnforcementConformsWithSpecification() public {
        string memory json = vm.readFile("../../spec/vectors/enforcement.json");
        uint256 count = _vectorCount(json);

        for (uint256 i = 0; i < count; ++i) {
            string memory indexString = vm.toString(i);

            bytes memory policy = PolicyCoder.encode(_policyData(json, indexString));
            bytes memory callData = vm.parseJsonBytes(json, string.concat(".[", indexString, "].callData"));

            string memory errorPath = string.concat(".[", indexString, "].expectedError");
            if (vm.keyExistsJson(json, errorPath)) {
                vm.expectPartialRevert(_errorSelector(vm.parseJsonString(json, errorPath)));
                _check(json, indexString, policy, callData);
                continue;
            }

            string memory id = vm.parseJsonString(json, string.concat(".[", indexString, "].id"));
            bool expected = vm.parseJsonBool(json, string.concat(".[", indexString, "].expected"));
            assertEq(_check(json, indexString, policy, callData), expected, string.concat(id, ": verdict"));
        }
    }
}

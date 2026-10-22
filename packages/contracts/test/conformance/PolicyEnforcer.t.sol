// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ConformanceTest } from "test/conformance/ConformanceTest.sol";
import { PolicyEnforcerHarness } from "test/harnesses/PolicyEnforcerHarness.sol";

contract PolicyEnforcerConformanceTest is ConformanceTest {
    // "context", "expected", "expectedError" and "integrityError" are present only on the vectors that need them, so
    // entries are read key by key rather than decoded into a fixture struct.

    PolicyEnforcerHarness internal harness;

    function setUp() public {
        harness = new PolicyEnforcerHarness();
    }

    /// @dev Checks `callData` against `blob`, returning the verdict, or the revert data of an abort.
    function _try(
        bytes memory blob,
        bytes memory callData,
        uint256 value
    )
        private
        returns (bool reverted, bool ok, bytes memory reason)
    {
        if (value == 0) {
            try harness.check(blob, callData) returns (bool result) {
                ok = result;
            } catch (bytes memory revertData) {
                (reverted, reason) = (true, revertData);
            }
        } else {
            try harness.checkPayable{ value: value }(blob, callData) returns (bool result) {
                ok = result;
            } catch (bytes memory revertData) {
                (reverted, reason) = (true, revertData);
            }
        }
    }

    /// @dev Runs one vector under its declared context, returning the verdict, or the revert data of an abort.
    function _run(
        string memory json,
        string memory key,
        bytes memory blob,
        bytes memory callData
    )
        private
        returns (bool reverted, bool ok, bytes memory reason)
    {
        string memory contextKey = string.concat(key, ".context");
        if (!vm.keyExistsJson(json, contextKey)) return _try(blob, callData, 0);

        address sender = vm.parseAddress(vm.parseJsonString(json, string.concat(contextKey, ".msgSender")));
        uint256 value = vm.parseUint(vm.parseJsonString(json, string.concat(contextKey, ".msgValue")));
        uint256 baseFee = vm.parseUint(vm.parseJsonString(json, string.concat(contextKey, ".baseFee")));
        uint256 gasPrice = vm.parseUint(vm.parseJsonString(json, string.concat(contextKey, ".gasPrice")));
        vm.fee(baseFee);
        vm.txGasPrice(gasPrice);

        // The block fields appear only on the vectors that pin them.
        string memory timestampKey = string.concat(contextKey, ".blockTimestamp");
        if (vm.keyExistsJson(json, timestampKey)) vm.warp(vm.parseUint(vm.parseJsonString(json, timestampKey)));
        string memory numberKey = string.concat(contextKey, ".blockNumber");
        if (vm.keyExistsJson(json, numberKey)) vm.roll(vm.parseUint(vm.parseJsonString(json, numberKey)));
        string memory chainIdKey = string.concat(contextKey, ".chainId");
        if (vm.keyExistsJson(json, chainIdKey)) vm.chainId(vm.parseUint(vm.parseJsonString(json, chainIdKey)));

        // A view call observes the pinned fee fields. A value-bearing call cannot be view, and under the isolate
        // profile it lands in a fresh block with recomputed fee fields, so no vector pins both context kinds.
        string memory originKey = string.concat(contextKey, ".txOrigin");
        if (value == 0) {
            // The default origin is a nonzero sentinel, so the vectors that read it pin it.
            if (vm.keyExistsJson(json, originKey)) {
                vm.prank(sender, vm.parseAddress(vm.parseJsonString(json, originKey)));
            } else {
                vm.prank(sender);
            }
            return _try(blob, callData, 0);
        }

        require(baseFee == 0 && gasPrice == 0, "Vector pins both a call value and a fee field");
        require(!vm.keyExistsJson(json, originKey), "Vector pins both a call value and txOrigin");
        vm.deal(sender, value);
        vm.prank(sender);
        return _try(blob, callData, value);
    }

    function test_EnforcementConformsWithSpecification() public {
        string memory json = vm.readFile("../../spec/vectors/enforcement.json");
        uint256 count = _vectorCount(json);
        assertGt(count, 0, "no vectors");
        for (uint256 i = 0; i < count; ++i) {
            string memory key = string.concat(".[", vm.toString(i), "]");
            string memory id = vm.parseJsonString(json, string.concat(key, ".id"));
            bytes memory blob = vm.parseJsonBytes(json, string.concat(key, ".blob"));
            bytes memory callData = vm.parseJsonBytes(json, string.concat(key, ".callData"));
            (bool reverted, bool ok, bytes memory reason) = _run(json, key, blob, callData);

            string memory errorKey = string.concat(key, ".expectedError");
            if (vm.keyExistsJson(json, errorKey)) {
                assertTrue(reverted, id);
                assertEq(_abortCode(reason), vm.parseJsonString(json, errorKey), id);
            } else if (vm.keyExistsJson(json, string.concat(key, ".integrityError"))) {
                assertTrue(reverted, id);
                assertEq(_abortCode(reason), "integrity", id);
            } else {
                assertFalse(reverted, id);
                assertEq(ok, vm.parseJsonBool(json, string.concat(key, ".expected")), id);
            }
        }
    }
}

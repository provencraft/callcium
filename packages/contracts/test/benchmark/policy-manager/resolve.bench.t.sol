// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyManager.resolve() - the hot path.
contract ResolveBench is PolicyManagerBench {
    function setUp() public override {
        super.setUp();
        harness.bind(target, policyHash);
        harness.bind(address(0), policyHash);
    }

    function test_Target() public {
        bytes memory resolved = harness.resolve(target, SELECTOR);
        vm.snapshotGasLastCall("PolicyManager.resolve", "target");
        assertEq(resolved, policy);
    }

    function test_Default() public {
        bytes memory resolved = harness.resolve(UNBOUND_TARGET, SELECTOR);
        vm.snapshotGasLastCall("PolicyManager.resolve", "default");
        assertEq(resolved, policy);
    }
}

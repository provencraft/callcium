// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyManager.hashFor().
contract HashForBench is PolicyManagerBench {
    function setUp() public override {
        super.setUp();
        harness.bind(target, policyHash);
        harness.bind(address(0), policyHash);
    }

    function test_TargetBound() public {
        bytes32 hash = harness.hashFor(target, SELECTOR);
        vm.snapshotGasLastCall("PolicyManager.hashFor", "target_bound");
        assertEq(hash, policyHash);
    }

    function test_DefaultFallback() public {
        bytes32 hash = harness.hashFor(UNBOUND_TARGET, SELECTOR);
        vm.snapshotGasLastCall("PolicyManager.hashFor", "default_fallback");
        assertEq(hash, policyHash);
    }

    function test_None() public {
        bytes32 hash = harness.hashFor(UNBOUND_TARGET, UNBOUND_SELECTOR);
        vm.snapshotGasLastCall("PolicyManager.hashFor", "none");
        assertEq(hash, bytes32(0));
    }
}

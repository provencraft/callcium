// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.hashFor().
contract HashForBench is PolicyManagerBench {
    function setUp() public override {
        super.setUp();
        harness.bind(target, policyHash);
        harness.bind(address(0), policyHash);
    }

    function test_TargetBound() public {
        harness.hashFor(target, SELECTOR);
        vm.snapshotGasLastCall("PolicyManager.hashFor", "target_bound");
    }

    function test_DefaultFallback() public {
        harness.hashFor(address(0xffff), SELECTOR);
        vm.snapshotGasLastCall("PolicyManager.hashFor", "default_fallback");
    }

    function test_None() public {
        harness.hashFor(address(1), bytes4(0x12345678));
        vm.snapshotGasLastCall("PolicyManager.hashFor", "none");
    }
}

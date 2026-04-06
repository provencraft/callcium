// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyRegistryBench } from "../PolicyRegistry.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.hashFor().
contract HashForBench is PolicyRegistryBench {
    function setUp() public override {
        super.setUp();
        harness.bind(target, SELECTOR, policyHash);
        harness.bind(address(0), SELECTOR, policyHash);
    }

    function test_TargetBound() public {
        harness.hashFor(target, SELECTOR);
        vm.snapshotGasLastCall("PolicyRegistry.hashFor", "target_bound");
    }

    function test_DefaultFallback() public {
        harness.hashFor(address(0xffff), SELECTOR);
        vm.snapshotGasLastCall("PolicyRegistry.hashFor", "default_fallback");
    }

    function test_None() public {
        harness.hashFor(address(1), bytes4(0x12345678));
        vm.snapshotGasLastCall("PolicyRegistry.hashFor", "none");
    }
}

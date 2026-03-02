// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyRegistryBench } from "../PolicyRegistry.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.resolve() - the hot path.
contract ResolveBench is PolicyRegistryBench {
    function setUp() public override {
        super.setUp();
        harness.bind(target, SELECTOR, policyHash);
        harness.bind(address(0), SELECTOR, policyHash);
    }

    function test_Target() public {
        harness.resolve(target, SELECTOR);
        vm.snapshotGasLastCall("PolicyRegistry.resolve", "target");
    }

    function test_Default() public {
        harness.resolve(address(0xffff), SELECTOR);
        vm.snapshotGasLastCall("PolicyRegistry.resolve", "default");
    }
}

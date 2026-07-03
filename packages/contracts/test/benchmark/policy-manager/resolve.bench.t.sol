// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.resolve() - the hot path.
contract ResolveBench is PolicyManagerBench {
    function setUp() public override {
        super.setUp();
        harness.bind(target, policyHash);
        harness.bind(address(0), policyHash);
    }

    function test_Target() public {
        harness.resolve(target, SELECTOR);
        vm.snapshotGasLastCall("PolicyManager.resolve", "target");
    }

    function test_Default() public {
        harness.resolve(address(0xffff), SELECTOR);
        vm.snapshotGasLastCall("PolicyManager.resolve", "default");
    }
}

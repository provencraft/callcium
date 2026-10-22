// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @notice Benchmarks for PolicyManager.load().
contract LoadBench is PolicyManagerBench {
    function setUp() public override {
        super.setUp();
        harness.bind(target, policyHash);
    }

    function test_Existing() public {
        bytes memory loaded = harness.load(policyHash);
        vm.snapshotGasLastFrame("PolicyManager.load", "existing");
        assertEq(loaded, policy);
    }

    function test_NonExistent() public {
        bytes memory loaded = harness.load(UNKNOWN_HASH);
        vm.snapshotGasLastFrame("PolicyManager.load", "non_existent");
        assertEq(loaded.length, 0);
    }
}

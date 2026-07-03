// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.load().
contract LoadBench is PolicyManagerBench {
    function setUp() public override {
        super.setUp();
        harness.bind(target, policyHash);
    }

    function test_Existing() public {
        harness.load(policyHash);
        vm.snapshotGasLastCall("PolicyManager.load", "existing");
    }

    function test_NonExistent() public {
        harness.load(bytes32(uint256(1)));
        vm.snapshotGasLastCall("PolicyManager.load", "non_existent");
    }
}

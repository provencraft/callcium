// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyRegistryBench } from "../PolicyRegistry.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.load().
contract LoadBench is PolicyRegistryBench {
    function setUp() public override {
        super.setUp();
        harness.bind(target, SELECTOR, policyHash);
    }

    function test_Existing() public {
        harness.load(policyHash);
        vm.snapshotGasLastCall("PolicyRegistry.load", "existing");
    }

    function test_NonExistent() public {
        harness.load(bytes32(uint256(1)));
        vm.snapshotGasLastCall("PolicyRegistry.load", "non_existent");
    }
}

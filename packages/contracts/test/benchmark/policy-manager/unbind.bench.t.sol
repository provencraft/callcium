// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @notice Benchmarks for PolicyManager.unbind().
contract UnbindBench is PolicyManagerBench {
    function setUp() public override {
        super.setUp();
        harness.bind(target, policyHash);
    }

    function test_Target() public {
        harness.unbind(target, SELECTOR);
        vm.snapshotGasLastFrame("PolicyManager.unbind", "target");
        assertEq(harness.hashFor(target, SELECTOR), bytes32(0));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// forge-lint: disable-start(unused-return)

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyManager.bind().
contract BindBench is PolicyManagerBench {
    function test_Target() public {
        harness.bind(target, policyHash);
        vm.snapshotGasLastCall("PolicyManager.bind", "target");
        assertEq(harness.hashFor(target, SELECTOR), policyHash);
    }
}

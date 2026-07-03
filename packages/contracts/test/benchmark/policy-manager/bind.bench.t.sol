// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.bind().
contract BindBench is PolicyManagerBench {
    function test_Bind() public {
        harness.bind(target, policyHash);
        vm.snapshotGasLastCall("PolicyManager.bind", "bind");
    }
}

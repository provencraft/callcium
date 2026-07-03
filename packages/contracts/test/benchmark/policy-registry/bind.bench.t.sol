// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyRegistryBench } from "../PolicyRegistry.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.bind().
contract BindBench is PolicyRegistryBench {
    function test_Bind() public {
        harness.bind(target, policyHash);
        vm.snapshotGasLastCall("PolicyRegistry.bind", "bind");
    }
}

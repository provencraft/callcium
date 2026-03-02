// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyRegistryBench } from "../PolicyRegistry.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.exists().
contract ExistsBench is PolicyRegistryBench {
    function test_True() public {
        harness.exists(policyHash);
        vm.snapshotGasLastCall("PolicyRegistry.exists", "true");
    }

    function test_False() public {
        harness.exists(bytes32(uint256(1)));
        vm.snapshotGasLastCall("PolicyRegistry.exists", "false");
    }
}

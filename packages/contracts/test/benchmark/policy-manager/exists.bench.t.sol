// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.exists().
contract ExistsBench is PolicyManagerBench {
    function test_True() public {
        harness.exists(policyHash);
        vm.snapshotGasLastCall("PolicyManager.exists", "true");
    }

    function test_False() public {
        harness.exists(bytes32(uint256(1)));
        vm.snapshotGasLastCall("PolicyManager.exists", "false");
    }
}

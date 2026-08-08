// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyManager.exists().
contract ExistsBench is PolicyManagerBench {
    function test_True() public {
        bool found = harness.exists(policyHash);
        vm.snapshotGasLastCall("PolicyManager.exists", "true");
        assertTrue(found);
    }

    function test_False() public {
        bool found = harness.exists(UNKNOWN_HASH);
        vm.snapshotGasLastCall("PolicyManager.exists", "false");
        assertFalse(found);
    }
}

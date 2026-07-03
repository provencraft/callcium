// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.storeAndBind() - O(N) where N = targets.length.
contract StoreAndBindBench is PolicyManagerBench {
    function test_1Target() public {
        harness.storeAndBind(targets1, policy);
        vm.snapshotGasLastCall("PolicyManager.storeAndBind", "1_target");
    }

    function test_1Target_SingleOverload() public {
        harness.storeAndBind(target, policy);
        vm.snapshotGasLastCall("PolicyManager.storeAndBind", "1_target_single");
    }

    function test_10Targets() public {
        harness.storeAndBind(targets10, policy);
        vm.snapshotGasLastCall("PolicyManager.storeAndBind", "10_targets");
    }

    function test_Default() public {
        harness.storeAndBind(address(0), policy);
        vm.snapshotGasLastCall("PolicyManager.storeAndBind", "default");
    }
}

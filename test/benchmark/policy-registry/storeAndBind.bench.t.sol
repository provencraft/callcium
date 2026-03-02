// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyRegistryBench } from "../PolicyRegistry.bench.t.sol";

/// @dev Benchmarks for PolicyRegistry.storeAndBind() - O(N) where N = targets.length.
contract StoreAndBindBench is PolicyRegistryBench {
    function test_1Target() public {
        harness.storeAndBind(targets1, policy);
        vm.snapshotGasLastCall("PolicyRegistry.storeAndBind", "1_target");
    }

    function test_1Target_SingleOverload() public {
        harness.storeAndBind(target, policy);
        vm.snapshotGasLastCall("PolicyRegistry.storeAndBind", "1_target_single");
    }

    function test_10Targets() public {
        harness.storeAndBind(targets10, policy);
        vm.snapshotGasLastCall("PolicyRegistry.storeAndBind", "10_targets");
    }

    function test_Default() public {
        harness.storeAndBind(address(0), policy);
        vm.snapshotGasLastCall("PolicyRegistry.storeAndBind", "default");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyManager.storeAndBind() - O(N) where N = targets.length.
contract StoreAndBindBench is PolicyManagerBench {
    function test_1Target() public {
        bytes32 hash = harness.storeAndBind(targets1, unstoredPolicy);
        vm.snapshotGasLastCall("PolicyManager.storeAndBind", "1_target");
        assertTrue(harness.exists(hash));
    }

    function test_1TargetSingleOverload() public {
        bytes32 hash = harness.storeAndBind(target, unstoredPolicy);
        vm.snapshotGasLastCall("PolicyManager.storeAndBind", "1_target_single");
        assertTrue(harness.exists(hash));
    }

    function test_10Targets() public {
        bytes32 hash = harness.storeAndBind(targets10, unstoredPolicy);
        vm.snapshotGasLastCall("PolicyManager.storeAndBind", "10_targets");
        assertTrue(harness.exists(hash));
    }

    function test_Default() public {
        bytes32 hash = harness.storeAndBind(address(0), unstoredPolicy);
        vm.snapshotGasLastCall("PolicyManager.storeAndBind", "default");
        assertTrue(harness.exists(hash));
    }

    /// @dev The same call over a policy already in the registry, which reduces to the bind alone.
    function test_1TargetCached() public {
        bytes32 hash = harness.storeAndBind(targets1, policy);
        vm.snapshotGasLastCall("PolicyManager.storeAndBind", "1_target_cached");
        assertEq(hash, policyHash);
    }
}

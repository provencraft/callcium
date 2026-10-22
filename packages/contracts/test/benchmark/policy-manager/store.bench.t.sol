// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @notice Benchmarks for PolicyManager.store().
contract StoreBench is PolicyManagerBench {
    function test_StoreNewPolicy() public {
        (, address pointer) = harness.store(unstoredPolicy);
        vm.snapshotGasLastFrame("PolicyManager.store", "new_policy");
        assertTrue(pointer != address(0));
    }

    function test_StoreExistingPolicy() public {
        (bytes32 hash, address pointer) = harness.store(policy);
        vm.snapshotGasLastFrame("PolicyManager.store", "existing_policy");
        assertEq(hash, policyHash);
        assertTrue(pointer != address(0));
    }

    function test_StoreTuple() public {
        (, address pointer) = harness.store(policyTuple);
        vm.snapshotGasLastFrame("PolicyManager.store", "tuple_3fields");
        assertTrue(pointer != address(0));
    }

    function test_StoreNestedTuple() public {
        (, address pointer) = harness.store(policyNestedTuple);
        vm.snapshotGasLastFrame("PolicyManager.store", "nested_tuple");
        assertTrue(pointer != address(0));
    }

    function test_StoreArray() public {
        (, address pointer) = harness.store(policyArray);
        vm.snapshotGasLastFrame("PolicyManager.store", "dynamic_array");
        assertTrue(pointer != address(0));
    }

    function test_StoreComplex() public {
        (, address pointer) = harness.store(policyComplex);
        vm.snapshotGasLastFrame("PolicyManager.store", "complex_3params");
        assertTrue(pointer != address(0));
    }

    function test_StoreLargeInSet() public {
        (, address pointer) = harness.store(policyLargeIn);
        vm.snapshotGasLastFrame("PolicyManager.store", "large_in_set_256");
        assertTrue(pointer != address(0));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// forge-lint: disable-start(unused-return)

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @dev Benchmarks for PolicyManager.store().
contract StoreBench is PolicyManagerBench {
    function test_StoreNewPolicy() public {
        (, address pointer) = harness.store(unstoredPolicy);
        vm.snapshotGasLastCall("PolicyManager.store", "new_policy");
        assertTrue(pointer != address(0));
    }

    function test_StoreExistingPolicy() public {
        (bytes32 hash, address pointer) = harness.store(policy);
        vm.snapshotGasLastCall("PolicyManager.store", "existing_policy");
        assertEq(hash, policyHash);
        assertTrue(pointer != address(0));
    }

    function test_StoreTuple() public {
        (, address pointer) = harness.store(policyTuple);
        vm.snapshotGasLastCall("PolicyManager.store", "tuple_3fields");
        assertTrue(pointer != address(0));
    }

    function test_StoreNestedTuple() public {
        (, address pointer) = harness.store(policyNestedTuple);
        vm.snapshotGasLastCall("PolicyManager.store", "nested_tuple");
        assertTrue(pointer != address(0));
    }

    function test_StoreArray() public {
        (, address pointer) = harness.store(policyArray);
        vm.snapshotGasLastCall("PolicyManager.store", "dynamic_array");
        assertTrue(pointer != address(0));
    }

    function test_StoreComplex() public {
        (, address pointer) = harness.store(policyComplex);
        vm.snapshotGasLastCall("PolicyManager.store", "complex_3params");
        assertTrue(pointer != address(0));
    }

    function test_StoreLargeInSet() public {
        (, address pointer) = harness.store(policyLargeIn);
        vm.snapshotGasLastCall("PolicyManager.store", "large_in_set_256");
        assertTrue(pointer != address(0));
    }
}

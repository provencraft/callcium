// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";
import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

// forgefmt: disable-next-item
contract StoreBench is PolicyManagerBench {
    bytes internal newPolicy;

    function setUp() public virtual override {
        super.setUp();
        newPolicy = PolicyBuilder.create("bar(uint256)")
            .add(arg(0).eq(uint256(1337)))
            .buildUnsafe();
    }

    function test_StoreNewPolicy() public {
        harness.store(newPolicy);
        vm.snapshotGasLastCall("PolicyManager.store", "new_policy");
    }

    function test_StoreExistingPolicy() public {
        harness.store(policy);
        vm.snapshotGasLastCall("PolicyManager.store", "existing_policy");
    }

    function test_StoreTuple() public {
        harness.store(policyTuple);
        vm.snapshotGasLastCall("PolicyManager.store", "tuple_3fields");
    }

    function test_StoreNestedTuple() public {
        harness.store(policyNestedTuple);
        vm.snapshotGasLastCall("PolicyManager.store", "nested_tuple");
    }

    function test_StoreArray() public {
        harness.store(policyArray);
        vm.snapshotGasLastCall("PolicyManager.store", "dynamic_array");
    }

    function test_StoreComplex() public {
        harness.store(policyComplex);
        vm.snapshotGasLastCall("PolicyManager.store", "complex_3params");
    }

    function test_StoreLargeInSet() public {
        harness.store(policyLargeIn);
        vm.snapshotGasLastCall("PolicyManager.store", "large_in_set_256");
    }
}

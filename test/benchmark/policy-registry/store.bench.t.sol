// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyRegistryBench } from "../PolicyRegistry.bench.t.sol";
import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

// forgefmt: disable-next-item
contract StoreBench is PolicyRegistryBench {
    bytes internal newPolicy;

    function setUp() public virtual override {
        super.setUp();
        newPolicy = PolicyBuilder.create("bar(uint256)")
            .add(arg(0).eq(uint256(1337)))
            .buildUnsafe();
    }

    function test_StoreNewPolicy() public {
        harness.store(newPolicy);
        vm.snapshotGasLastCall("PolicyRegistry.store", "new_policy");
    }

    function test_StoreExistingPolicy() public {
        harness.store(policy);
        vm.snapshotGasLastCall("PolicyRegistry.store", "existing_policy");
    }

    function test_StoreTuple() public {
        harness.store(policyTuple);
        vm.snapshotGasLastCall("PolicyRegistry.store", "tuple_3fields");
    }

    function test_StoreNestedTuple() public {
        harness.store(policyNestedTuple);
        vm.snapshotGasLastCall("PolicyRegistry.store", "nested_tuple");
    }

    function test_StoreArray() public {
        harness.store(policyArray);
        vm.snapshotGasLastCall("PolicyRegistry.store", "dynamic_array");
    }

    function test_StoreComplex() public {
        harness.store(policyComplex);
        vm.snapshotGasLastCall("PolicyRegistry.store", "complex_3params");
    }
}

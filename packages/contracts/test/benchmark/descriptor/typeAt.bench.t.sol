// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { DescriptorHarness } from "../../harnesses/DescriptorHarness.sol";
import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

/// @dev Benchmarks for Descriptor.typeAt path traversal.
contract TypeAtBench is CalldataReaderBench {
    DescriptorHarness internal descriptorHarness;

    function setUp() public override {
        super.setUp();
        descriptorHarness = new DescriptorHarness();
    }

    function test_Depth1() public {
        descriptorHarness.typeAt(descElementary, _path(0));
        vm.snapshotGasLastCall("Descriptor.typeAt", "depth1");
    }

    function test_Depth2() public {
        descriptorHarness.typeAt(descStaticStruct, _path(0, 1));
        vm.snapshotGasLastCall("Descriptor.typeAt", "depth2");
    }

    function test_Tuple10Last() public {
        descriptorHarness.typeAt(descStaticTuple10, _path(0, 9));
        vm.snapshotGasLastCall("Descriptor.typeAt", "tuple10_last");
    }

    function test_Tuple32Last() public {
        descriptorHarness.typeAt(descStaticTuple32, _path(0, 31));
        vm.snapshotGasLastCall("Descriptor.typeAt", "tuple32_last");
    }
}

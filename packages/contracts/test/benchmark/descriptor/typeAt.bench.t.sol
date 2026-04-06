// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Descriptor } from "src/Descriptor.sol";

import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

/// @dev Benchmarks for Descriptor.typeAt path traversal.
contract TypeAtBench is CalldataReaderBench {
    using Descriptor for bytes;

    function test_Depth1() public {
        descElementary.typeAt(_path(0));
        vm.snapshotGasLastCall("Descriptor.typeAt", "depth1");
    }

    function test_Depth2() public {
        descStaticStruct.typeAt(_path(0, 1));
        vm.snapshotGasLastCall("Descriptor.typeAt", "depth2");
    }

    function test_Tuple10Last() public {
        descStaticTuple10.typeAt(_path(0, 9));
        vm.snapshotGasLastCall("Descriptor.typeAt", "tuple10_last");
    }

    function test_Tuple32Last() public {
        descStaticTuple32.typeAt(_path(0, 31));
        vm.snapshotGasLastCall("Descriptor.typeAt", "tuple32_last");
    }
}

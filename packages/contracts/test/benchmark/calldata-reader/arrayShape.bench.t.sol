// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

contract ArrayShapeBench is CalldataReaderBench {
    function test_DynArraySmall() public {
        harness.arrayShape(descDynArraySmall, callDataDynArraySmall, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.arrayShape", "dyn_array_small");
    }

    function test_DynArrayMedium() public {
        harness.arrayShape(descDynArrayMedium, callDataDynArrayMedium, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.arrayShape", "dyn_array_medium");
    }

    function test_DynArrayLarge() public {
        harness.arrayShape(descDynArrayLarge, callDataDynArrayLarge, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.arrayShape", "dyn_array_large");
    }

    function test_StaticArray() public {
        harness.arrayShape(descStaticArray, callDataStaticArray, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.arrayShape", "static_array");
    }

    function test_DynElemArray() public {
        harness.arrayShape(descBytesArray, callDataBytesArray, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.arrayShape", "dyn_elem_array");
    }
}

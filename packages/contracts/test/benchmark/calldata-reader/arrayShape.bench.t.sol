// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CalldataReader } from "src/CalldataReader.sol";

import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

contract ArrayShapeBench is CalldataReaderBench {
    function test_DynArraySmall() public {
        CalldataReader.ArrayShape memory shape = harness.arrayShape(descDynArray, callDataDynArraySmall, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.arrayShape", "dyn_array_small");
        assertEq(shape.length, 3);
    }

    function test_DynArrayMedium() public {
        CalldataReader.ArrayShape memory shape = harness.arrayShape(descDynArray, callDataDynArrayMedium, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.arrayShape", "dyn_array_medium");
        assertEq(shape.length, 10);
    }

    function test_DynArrayLarge() public {
        CalldataReader.ArrayShape memory shape = harness.arrayShape(descDynArray, callDataDynArrayLarge, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.arrayShape", "dyn_array_large");
        assertEq(shape.length, 100);
    }

    function test_StaticArray() public {
        CalldataReader.ArrayShape memory shape = harness.arrayShape(descStaticArray, callDataStaticArray, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.arrayShape", "static_array");
        assertEq(shape.length, 5);
    }

    function test_DynElemArray() public {
        CalldataReader.ArrayShape memory shape = harness.arrayShape(descBytesArray, callDataBytesArray, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.arrayShape", "dyn_elem_array");
        assertEq(shape.length, 3);
        assertTrue(shape.elementIsDynamic);
    }
}

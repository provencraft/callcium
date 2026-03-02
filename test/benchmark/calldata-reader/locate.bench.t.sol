// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

contract LocateBench is CalldataReaderBench {
    function test_ElementaryDepth1() public {
        harness.locate(descElementary, callDataElementary, _path(0), cfg);
        vm.snapshotGasLastCall("CalldataReader.locate", "elementary_depth1");
    }

    function test_StructFieldDepth2() public {
        harness.locate(descStaticStruct, callDataStaticStruct, _path(0, 1), cfg);
        vm.snapshotGasLastCall("CalldataReader.locate", "struct_field_depth2");
    }

    function test_DynStructFieldDepth2() public {
        harness.locate(descDynStruct, callDataDynStruct, _path(0, 1), cfg);
        vm.snapshotGasLastCall("CalldataReader.locate", "dyn_struct_field_depth2");
    }

    function test_ArrayElemDepth2() public {
        harness.locate(descDynArraySmall, callDataDynArraySmall, _path(0, 1), cfg);
        vm.snapshotGasLastCall("CalldataReader.locate", "array_elem_depth2");
    }

    function test_StaticArrayElemDepth2() public {
        harness.locate(descStaticArray, callDataStaticArray, _path(0, 2), cfg);
        vm.snapshotGasLastCall("CalldataReader.locate", "static_array_elem_depth2");
    }

    function test_NestedStructDepth3() public {
        harness.locate(descNested2, callDataNested2, _path(0, 0, 1), cfg);
        vm.snapshotGasLastCall("CalldataReader.locate", "nested_struct_depth3");
    }

    function test_DeepNestingDepth4() public {
        harness.locate(descNested4, callDataNested4, _path(0, 0, 0, 0), cfg);
        vm.snapshotGasLastCall("CalldataReader.locate", "deep_nesting_depth4");
    }

    function test_DeepNestingDepth8() public {
        uint16[] memory path = new uint16[](9);
        path[0] = 0;
        path[1] = 0;
        path[2] = 0;
        path[3] = 0;
        path[4] = 0;
        path[5] = 0;
        path[6] = 0;
        path[7] = 0;
        path[8] = 0;
        harness.locate(descNested8, callDataNested8, _path(path), cfg);
        vm.snapshotGasLastCall("CalldataReader.locate", "deep_nesting_depth8");
    }

    function test_LargeTuple10Last() public {
        harness.locate(descStaticTuple10, callDataStaticTuple10, _path(0, 9), cfg);
        vm.snapshotGasLastCall("CalldataReader.locate", "large_tuple10_last");
    }

    function test_LargeTuple32Last() public {
        harness.locate(descStaticTuple32, callDataStaticTuple32, _path(0, 31), cfg);
        vm.snapshotGasLastCall("CalldataReader.locate", "large_tuple32_last");
    }
}

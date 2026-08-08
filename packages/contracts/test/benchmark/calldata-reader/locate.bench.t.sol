// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

contract LocateBench is CalldataReaderBench {
    /// @dev Path length for the `descNested8` corpus: one step per nesting level plus the parameter.
    uint256 internal constant NESTED8_PATH_LENGTH = 9;

    function test_ElementaryDepth1() public {
        _benchLocation(
            harness.locate(descElementary, callDataElementary, _path(0), cfg),
            "CalldataReader.locate",
            "elementary_depth1"
        );
    }

    function test_StructFieldDepth2() public {
        _benchLocation(
            harness.locate(descStaticStruct, callDataStaticStruct, _path(0, 1), cfg),
            "CalldataReader.locate",
            "struct_field_depth2"
        );
    }

    function test_DynStructFieldDepth2() public {
        _benchLocation(
            harness.locate(descDynStruct, callDataDynStruct, _path(0, 1), cfg),
            "CalldataReader.locate",
            "dyn_struct_field_depth2"
        );
    }

    function test_ArrayElemDepth2() public {
        _benchLocation(
            harness.locate(descDynArray, callDataDynArraySmall, _path(0, 1), cfg),
            "CalldataReader.locate",
            "array_elem_depth2"
        );
    }

    function test_StaticArrayElemDepth2() public {
        _benchLocation(
            harness.locate(descStaticArray, callDataStaticArray, _path(0, 2), cfg),
            "CalldataReader.locate",
            "static_array_elem_depth2"
        );
    }

    function test_NestedStructDepth3() public {
        _benchLocation(
            harness.locate(descNested2, callDataNested2, _path(0, 0, 1), cfg),
            "CalldataReader.locate",
            "nested_struct_depth3"
        );
    }

    function test_DeepNestingDepth4() public {
        _benchLocation(
            harness.locate(descNested4, callDataNested4, _path(0, 0, 0, 0), cfg),
            "CalldataReader.locate",
            "deep_nesting_depth4"
        );
    }

    function test_DeepNestingDepth8() public {
        _benchLocation(
            harness.locate(descNested8, callDataNested8, _path(new uint16[](NESTED8_PATH_LENGTH)), cfg),
            "CalldataReader.locate",
            "deep_nesting_depth8"
        );
    }

    function test_LargeTuple10Last() public {
        _benchLocation(
            harness.locate(descStaticTuple10, callDataStaticTuple10, _path(0, 9), cfg),
            "CalldataReader.locate",
            "large_tuple10_last"
        );
    }

    function test_LargeTuple32Last() public {
        _benchLocation(
            harness.locate(descStaticTuple32, callDataStaticTuple32, _path(0, 31), cfg),
            "CalldataReader.locate",
            "large_tuple32_last"
        );
    }
}

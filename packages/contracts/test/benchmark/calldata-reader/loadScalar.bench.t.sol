// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CalldataReader } from "src/CalldataReader.sol";

import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

contract LoadScalarBench is CalldataReaderBench {
    CalldataReader.Location internal locElementary;
    CalldataReader.Location internal locStructField;
    CalldataReader.Location internal locArrayElem;

    function setUp() public override {
        super.setUp();
        locElementary = harness.locate(descElementary, callDataElementary, _path(0), cfg);
        locStructField = harness.locate(descStaticStruct, callDataStaticStruct, _path(0, 1), cfg);
        locArrayElem = harness.locate(descDynArray, callDataDynArraySmall, _path(0, 1), cfg);
    }

    function test_Elementary() public {
        bytes32 value = harness.loadScalar(locElementary, callDataElementary);
        vm.snapshotGasLastCall("CalldataReader.loadScalar", "elementary");
        assertEq(uint256(value), 42);
    }

    function test_StructField() public {
        bytes32 value = harness.loadScalar(locStructField, callDataStaticStruct);
        vm.snapshotGasLastCall("CalldataReader.loadScalar", "struct_field");
        assertEq(uint256(value), 42);
    }

    function test_ArrayElem() public {
        bytes32 value = harness.loadScalar(locArrayElem, callDataDynArraySmall);
        vm.snapshotGasLastCall("CalldataReader.loadScalar", "array_elem");
        assertEq(uint256(value), 2);
    }
}

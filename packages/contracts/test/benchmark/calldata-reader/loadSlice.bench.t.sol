// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CalldataReader } from "src/CalldataReader.sol";

import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

contract LoadSliceBench is CalldataReaderBench {
    CalldataReader.Location internal locSmall;
    CalldataReader.Location internal locMedium;
    CalldataReader.Location internal locLarge;
    CalldataReader.Location internal locEmpty;

    function setUp() public override {
        super.setUp();
        locSmall = harness.locate(descBytes, callDataBytesSmall, _path(0), cfg);
        locMedium = harness.locate(descBytes, callDataBytesMedium, _path(0), cfg);
        locLarge = harness.locate(descBytes, callDataBytesLarge, _path(0), cfg);
        locEmpty = harness.locate(descBytes, callDataBytesEmpty, _path(0), cfg);
    }

    function test_Small() public {
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(descBytes, locSmall, callDataBytesSmall);
        vm.snapshotGasLastCall("CalldataReader.loadSlice", "small");
        assertEq(slice.length, 32);
    }

    function test_Medium() public {
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(descBytes, locMedium, callDataBytesMedium);
        vm.snapshotGasLastCall("CalldataReader.loadSlice", "medium");
        assertEq(slice.length, 256);
    }

    function test_Large() public {
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(descBytes, locLarge, callDataBytesLarge);
        vm.snapshotGasLastCall("CalldataReader.loadSlice", "large");
        assertEq(slice.length, 1024);
    }

    function test_Empty() public {
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(descBytes, locEmpty, callDataBytesEmpty);
        vm.snapshotGasLastCall("CalldataReader.loadSlice", "empty");
        assertEq(slice.length, 0);
    }
}

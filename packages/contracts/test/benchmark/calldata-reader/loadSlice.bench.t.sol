// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

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
        harness.loadSlice(locSmall, callDataBytesSmall);
        vm.snapshotGasLastCall("CalldataReader.loadSlice", "small");
    }

    function test_Medium() public {
        harness.loadSlice(locMedium, callDataBytesMedium);
        vm.snapshotGasLastCall("CalldataReader.loadSlice", "medium");
    }

    function test_Large() public {
        harness.loadSlice(locLarge, callDataBytesLarge);
        vm.snapshotGasLastCall("CalldataReader.loadSlice", "large");
    }

    function test_Empty() public {
        harness.loadSlice(locEmpty, callDataBytesEmpty);
        vm.snapshotGasLastCall("CalldataReader.loadSlice", "empty");
    }
}

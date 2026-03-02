// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CalldataReader } from "src/CalldataReader.sol";

import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

contract TupleFieldBench is CalldataReaderBench {
    CalldataReader.Location internal locStatic2;
    CalldataReader.Location internal locStatic10;
    CalldataReader.Location internal locStatic32;
    CalldataReader.Location internal locDyn10;
    CalldataReader.Location internal locMixed10;

    function setUp() public override {
        super.setUp();
        locStatic2 = harness.locate(descStaticStruct, callDataStaticStruct, _path(0), cfg);
        locStatic10 = harness.locate(descStaticTuple10, callDataStaticTuple10, _path(0), cfg);
        locStatic32 = harness.locate(descStaticTuple32, callDataStaticTuple32, _path(0), cfg);
        locDyn10 = harness.locate(descDynTuple10, callDataDynTuple10, _path(0), cfg);
        locMixed10 = harness.locate(descMixedTuple10, callDataMixedTuple10, _path(0), cfg);
    }

    function test_Static2First() public {
        harness.tupleField(descStaticStruct, locStatic2, 0, callDataStaticStruct);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "static2_first");
    }

    function test_Static2Last() public {
        harness.tupleField(descStaticStruct, locStatic2, 1, callDataStaticStruct);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "static2_last");
    }

    function test_Static10First() public {
        harness.tupleField(descStaticTuple10, locStatic10, 0, callDataStaticTuple10);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "static10_first");
    }

    function test_Static10Middle() public {
        harness.tupleField(descStaticTuple10, locStatic10, 5, callDataStaticTuple10);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "static10_middle");
    }

    function test_Static10Last() public {
        harness.tupleField(descStaticTuple10, locStatic10, 9, callDataStaticTuple10);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "static10_last");
    }

    function test_Static32Last() public {
        harness.tupleField(descStaticTuple32, locStatic32, 31, callDataStaticTuple32);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "static32_last");
    }

    function test_Dyn10First() public {
        harness.tupleField(descDynTuple10, locDyn10, 0, callDataDynTuple10);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "dyn10_first");
    }

    function test_Dyn10Middle() public {
        harness.tupleField(descDynTuple10, locDyn10, 5, callDataDynTuple10);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "dyn10_middle");
    }

    function test_Dyn10Last() public {
        harness.tupleField(descDynTuple10, locDyn10, 9, callDataDynTuple10);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "dyn10_last");
    }

    function test_Mixed10StaticLate() public {
        harness.tupleField(descMixedTuple10, locMixed10, 7, callDataMixedTuple10);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "mixed10_static_late");
    }

    function test_Mixed10DynLate() public {
        harness.tupleField(descMixedTuple10, locMixed10, 8, callDataMixedTuple10);
        vm.snapshotGasLastCall("CalldataReader.tupleField", "mixed10_dyn_late");
    }
}

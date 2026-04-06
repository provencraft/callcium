// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CalldataReader } from "src/CalldataReader.sol";

import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

contract ArrayElementAtBench is CalldataReaderBench {
    CalldataReader.ArrayShape internal shapeDynLarge;
    CalldataReader.ArrayShape internal shapeStatic32;

    function setUp() public override {
        super.setUp();
        shapeDynLarge = harness.arrayShape(descDynArrayLarge, callDataDynArrayLarge, _path(0), cfg);
        shapeStatic32 = harness.arrayShape(descStaticArray32, callDataStaticArray32, _path(0), cfg);
    }

    function test_DynFirst() public {
        harness.arrayElementAt(shapeDynLarge, 0, callDataDynArrayLarge);
        vm.snapshotGasLastCall("CalldataReader.arrayElementAt", "dyn_first");
    }

    function test_DynMiddle() public {
        harness.arrayElementAt(shapeDynLarge, 50, callDataDynArrayLarge);
        vm.snapshotGasLastCall("CalldataReader.arrayElementAt", "dyn_middle");
    }

    function test_DynLast() public {
        harness.arrayElementAt(shapeDynLarge, 99, callDataDynArrayLarge);
        vm.snapshotGasLastCall("CalldataReader.arrayElementAt", "dyn_last");
    }

    function test_Static32Last() public {
        harness.arrayElementAt(shapeStatic32, 31, callDataStaticArray32);
        vm.snapshotGasLastCall("CalldataReader.arrayElementAt", "static32_last");
    }
}

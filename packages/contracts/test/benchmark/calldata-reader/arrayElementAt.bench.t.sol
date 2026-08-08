// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CalldataReader } from "src/CalldataReader.sol";

import { CalldataReaderBench } from "../CalldataReader.bench.t.sol";

contract ArrayElementAtBench is CalldataReaderBench {
    CalldataReader.ArrayShape internal shapeDynLarge;
    CalldataReader.ArrayShape internal shapeStatic32;
    CalldataReader.ArrayShape internal shapeDynElem;

    function setUp() public override {
        super.setUp();
        shapeDynLarge = harness.arrayShape(descDynArray, callDataDynArrayLarge, _path(0), cfg);
        shapeStatic32 = harness.arrayShape(descStaticArray32, callDataStaticArray32, _path(0), cfg);
        shapeDynElem = harness.arrayShape(descBytesArray, callDataBytesArray, _path(0), cfg);
    }

    function test_DynFirst() public {
        _benchLocation(
            harness.arrayElementAt(shapeDynLarge, 0, callDataDynArrayLarge),
            "CalldataReader.arrayElementAt",
            "dyn_first"
        );
    }

    function test_DynMiddle() public {
        _benchLocation(
            harness.arrayElementAt(shapeDynLarge, 50, callDataDynArrayLarge),
            "CalldataReader.arrayElementAt",
            "dyn_middle"
        );
    }

    function test_DynLast() public {
        _benchLocation(
            harness.arrayElementAt(shapeDynLarge, 99, callDataDynArrayLarge),
            "CalldataReader.arrayElementAt",
            "dyn_last"
        );
    }

    function test_Static32Last() public {
        _benchLocation(
            harness.arrayElementAt(shapeStatic32, 31, callDataStaticArray32),
            "CalldataReader.arrayElementAt",
            "static32_last"
        );
    }

    /// @dev The rows above all address static elements by stride alone. A dynamic element is
    /// reached through its own offset word instead, which is the other half of the function.
    function test_DynElemLast() public {
        _benchLocation(
            harness.arrayElementAt(shapeDynElem, 2, callDataBytesArray),
            "CalldataReader.arrayElementAt",
            "dyn_elem_last"
        );
    }
}

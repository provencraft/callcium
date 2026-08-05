// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { DescriptorTest } from "../Descriptor.t.sol";
import { Descriptor } from "src/Descriptor.sol";
import { DescriptorFormat as DF } from "src/DescriptorFormat.sol";
import { TypeCode } from "src/TypeCode.sol";

contract InspectTest is DescriptorTest {
    function test_ReturnsCorrectNextOffset_Elementary() public pure {
        bytes memory desc = hex"020141";
        (uint8 code,,, uint256 next) = Descriptor.inspect(desc, DF.HEADER_SIZE);
        assertEq(code, TypeCode.ADDRESS);
        assertEq(next, DF.HEADER_SIZE + DF.TYPECODE_SIZE);
    }

    function test_ReturnsCorrectNextOffset_DynamicArray() public pure {
        // Dynamic array of address: [code:81][meta:000005][elem:41].
        // meta: staticWords=0 (dynamic), nodeLength=5 (1+3+1).
        bytes memory desc = hex"02018100000541";
        (uint8 code,,, uint256 next) = Descriptor.inspect(desc, DF.HEADER_SIZE);
        assertEq(code, TypeCode.DYNAMIC_ARRAY);
        assertEq(
            next,
            DF.HEADER_SIZE + DF.ARRAY_HEADER_SIZE + DF.TYPECODE_SIZE /* elem code */
        );
    }

    function test_ReturnsCorrectNextOffset_StaticArray() public pure {
        // Static array of address[3]: [code:80][meta:003007][elem:41][length:0003].
        // meta: staticWords=3, nodeLength=7 (1+3+1+2).
        bytes memory desc = hex"020180003007410003";
        (uint8 code,,, uint256 next) = Descriptor.inspect(desc, DF.HEADER_SIZE);
        assertEq(code, TypeCode.STATIC_ARRAY);
        assertEq(next, DF.HEADER_SIZE + DF.ARRAY_HEADER_SIZE + DF.TYPECODE_SIZE /* elem code */ + DF.ARRAY_LENGTH_SIZE);
    }

    function test_ReturnsCorrectNextOffset_Tuple() public pure {
        // Tuple of (address, uint8): [code:90][meta:002008][fieldCount:0002][addr:41][uint8:01].
        // meta: staticWords=2, nodeLength=8 (1+3+2+1+1).
        bytes memory desc = hex"02019000200800024101";
        (uint8 code,,, uint256 next) = Descriptor.inspect(desc, DF.HEADER_SIZE);
        assertEq(code, TypeCode.TUPLE);
        assertEq(next, DF.HEADER_SIZE + DF.TUPLE_HEADER_SIZE + DF.TYPECODE_SIZE + DF.TYPECODE_SIZE);
    }

    function test_ReturnsCorrectNextOffset_NestedTuple() public pure {
        // Nested tuple: tuple(tuple(address)).
        // Inner: [90][001007][0001][41] = 7 bytes, staticWords=1, nodeLength=7.
        // Outer: [90][00100d][0001][inner] = 13 bytes, staticWords=1, nodeLength=13.
        bytes memory desc = hex"02019000100d000190001007000141";
        (uint8 code,,, uint256 next) = Descriptor.inspect(desc, DF.HEADER_SIZE);
        assertEq(code, TypeCode.TUPLE);
        // Outer tuple header + inner tuple nodeLength (DF.TUPLE_HEADER_SIZE + 1 for a single elementary field).
        assertEq(next, DF.HEADER_SIZE + DF.TUPLE_HEADER_SIZE + (DF.TUPLE_HEADER_SIZE + DF.TYPECODE_SIZE));
    }

    function test_RevertWhen_OffsetOutOfBounds() public {
        bytes memory desc = hex"020141";
        vm.expectRevert(Descriptor.UnexpectedEnd.selector);
        Descriptor.inspect(desc, 3);
    }
}

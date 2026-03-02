// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorTest } from "../Descriptor.t.sol";
import { Descriptor } from "src/Descriptor.sol";
import { DescriptorFormat as DF } from "src/DescriptorFormat.sol";
import { TypeCode } from "src/TypeCode.sol";

contract InspectTest is DescriptorTest {
    function test_ReturnsCorrectNextOffset_Elementary() public pure {
        bytes memory desc = hex"010140";
        (uint8 code,,, uint256 next) = Descriptor.inspect(desc, DF.HEADER_SIZE);
        assertEq(code, TypeCode.ADDRESS);
        assertEq(next, DF.HEADER_SIZE + DF.TYPECODE_SIZE);
    }

    function test_ReturnsCorrectNextOffset_DynamicArray() public pure {
        // Dynamic array of address: [code:81][meta:000005][elem:40].
        // meta: staticWords=0 (dynamic), nodeLength=5 (1+3+1).
        bytes memory desc = hex"01018100000540";
        (uint8 code,,, uint256 next) = Descriptor.inspect(desc, DF.HEADER_SIZE);
        assertEq(code, TypeCode.DYNAMIC_ARRAY);
        assertEq(
            next,
            DF.HEADER_SIZE + DF.ARRAY_HEADER_SIZE + DF.TYPECODE_SIZE /* elem code */
        );
    }

    function test_ReturnsCorrectNextOffset_StaticArray() public pure {
        // Static array of address[3]: [code:80][meta:003007][elem:40][length:0003].
        // meta: staticWords=3, nodeLength=7 (1+3+1+2).
        bytes memory desc = hex"010180003007400003";
        (uint8 code,,, uint256 next) = Descriptor.inspect(desc, DF.HEADER_SIZE);
        assertEq(code, TypeCode.STATIC_ARRAY);
        assertEq(next, DF.HEADER_SIZE + DF.ARRAY_HEADER_SIZE + DF.TYPECODE_SIZE /* elem code */ + DF.ARRAY_LENGTH_SIZE);
    }

    function test_ReturnsCorrectNextOffset_Tuple() public pure {
        // Tuple of (address, uint8): [code:90][meta:002008][fieldCount:0002][addr:40][uint8:00].
        // meta: staticWords=2, nodeLength=8 (1+3+2+1+1).
        bytes memory desc = hex"01019000200800024000";
        (uint8 code,,, uint256 next) = Descriptor.inspect(desc, DF.HEADER_SIZE);
        assertEq(code, TypeCode.TUPLE);
        assertEq(next, DF.HEADER_SIZE + DF.TUPLE_HEADER_SIZE + DF.TYPECODE_SIZE + DF.TYPECODE_SIZE);
    }

    function test_ReturnsCorrectNextOffset_NestedTuple() public pure {
        // Nested tuple: tuple(tuple(address)).
        // Inner: [90][001007][0001][40] = 7 bytes, staticWords=1, nodeLength=7.
        // Outer: [90][00100d][0001][inner] = 13 bytes, staticWords=1, nodeLength=13.
        bytes memory desc = hex"01019000100d000190001007000140";
        (uint8 code,,, uint256 next) = Descriptor.inspect(desc, DF.HEADER_SIZE);
        assertEq(code, TypeCode.TUPLE);
        // Outer tuple header + inner tuple nodeLength (DF.TUPLE_HEADER_SIZE + 1 for a single elementary field).
        assertEq(next, DF.HEADER_SIZE + DF.TUPLE_HEADER_SIZE + (DF.TUPLE_HEADER_SIZE + DF.TYPECODE_SIZE));
    }

    function test_RevertWhen_OffsetOutOfBounds() public {
        bytes memory desc = hex"010140";
        vm.expectRevert(Descriptor.UnexpectedEnd.selector);
        Descriptor.inspect(desc, 3);
    }
}

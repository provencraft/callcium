// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorTest } from "../Descriptor.t.sol";

import { Be24 } from "src/Be24.sol";
import { Descriptor } from "src/Descriptor.sol";
import { DescriptorFormat as DF } from "src/DescriptorFormat.sol";

contract DecodeMetaTest is DescriptorTest {
    function test_DynamicArray() public pure {
        // Dynamic array of address: [code:81][meta:000005][elem:40].
        // meta: staticWords=0 (dynamic), nodeLength=5 (1+3+1).
        bytes memory desc = hex"01018100000540";
        (uint16 staticWords, uint16 nodeLength) = Descriptor.decodeMeta(desc, DF.HEADER_SIZE + DF.TYPECODE_SIZE);
        assertEq(staticWords, 0);
        assertEq(nodeLength, 5);
    }

    function test_StaticArray() public pure {
        // Static array of address[3]: [code:80][meta:003007][elem:40][length:0003].
        // meta: staticWords=3, nodeLength=7 (1+3+1+2).
        bytes memory desc = hex"010180003007400003";
        (uint16 staticWords, uint16 nodeLength) = Descriptor.decodeMeta(desc, DF.HEADER_SIZE + DF.TYPECODE_SIZE);
        assertEq(staticWords, 3);
        assertEq(nodeLength, 7);
    }

    function test_Tuple() public pure {
        // Tuple(address,uint8): [code:90][meta:002008][fieldCount:0002][addr:40][uint8:00].
        // meta: staticWords=2, nodeLength=8 (1+3+2+1+1).
        bytes memory desc = hex"01019000200800024000";
        (uint16 staticWords, uint16 nodeLength) = Descriptor.decodeMeta(desc, DF.HEADER_SIZE + DF.TYPECODE_SIZE);
        assertEq(staticWords, 2);
        assertEq(nodeLength, 8);
    }

    function test_RevertWhen_OutOfBounds() public {
        // Descriptor too short to contain 3-byte meta at the requested offset.
        bytes memory desc = hex"010181"; // header + code only.
        vm.expectRevert(Be24.OutOfBounds.selector);
        Descriptor.decodeMeta(desc, DF.HEADER_SIZE + DF.TYPECODE_SIZE);
    }
}

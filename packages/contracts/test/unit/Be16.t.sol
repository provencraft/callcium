// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { Be16 } from "src/Be16.sol";

contract Be16Test is Test {
    /*/////////////////////////////////////////////////////////////////////////
                                READ & WRITE
    /////////////////////////////////////////////////////////////////////////*/

    function test_Read_ReturnsCorrectValue() public pure {
        bytes memory data = hex"010203";
        assertEq(Be16.read(data, 0), uint16(0x0102));
        assertEq(Be16.read(data, 1), uint16(0x0203));
    }

    function test_ReadUnchecked_ReturnsCorrectValue() public pure {
        bytes memory data = hex"0A0B0C";
        assertEq(Be16.readUnchecked(data, 0), uint16(0x0A0B));
        assertEq(Be16.readUnchecked(data, 1), uint16(0x0B0C));
    }

    function test_Write_StoresCorrectBytes() public pure {
        bytes memory data = new bytes(4);
        Be16.write(data, 1, uint16(0x0102));
        bytes memory expected = hex"00010200";
        assertEq(keccak256(data), keccak256(expected));
    }

    function test_WriteUnchecked_StoresCorrectBytes() public pure {
        bytes memory data = new bytes(4);
        Be16.writeUnchecked(data, 1, uint16(0x0102));
        bytes memory expected = hex"00010200";
        assertEq(keccak256(data), keccak256(expected));
    }

    /*/////////////////////////////////////////////////////////////////////////
                              BOUNDS CHECKING
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_Read_OutOfBounds() public {
        bytes memory data = new bytes(1);
        vm.expectRevert(Be16.OutOfBounds.selector);
        Be16.read(data, 0);

        data = new bytes(2);
        vm.expectRevert(Be16.OutOfBounds.selector);
        Be16.read(data, 1);
    }

    function test_RevertWhen_Write_OutOfBounds() public {
        bytes memory data = new bytes(1);
        vm.expectRevert(Be16.OutOfBounds.selector);
        Be16.write(data, 0, 1);

        data = new bytes(2);
        vm.expectRevert(Be16.OutOfBounds.selector);
        Be16.write(data, 1, 1);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 ROUND-TRIP
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_RoundTrip_RetainsValue(uint256 valueSeed, uint256 offsetSeed) public pure {
        uint16 value = uint16(bound(valueSeed, 0, type(uint16).max));
        uint256 offset = bound(offsetSeed, 0, 64);
        bytes memory data = new bytes(offset + 2);

        Be16.write(data, offset, value);
        assertEq(Be16.read(data, offset), value);
        assertEq(Be16.readUnchecked(data, offset), value);

        // Verify writeUnchecked produces the same result
        bytes memory data2 = new bytes(offset + 2);
        Be16.writeUnchecked(data2, offset, value);
        assertEq(Be16.readUnchecked(data2, offset), value);
    }
}

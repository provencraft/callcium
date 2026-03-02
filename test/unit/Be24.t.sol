// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { Be24 } from "src/Be24.sol";

contract Be24Test is Test {
    /*/////////////////////////////////////////////////////////////////////////
                                READ & WRITE
    /////////////////////////////////////////////////////////////////////////*/

    function test_Read_ReturnsCorrectValue() public pure {
        bytes memory data = hex"01020304";
        assertEq(Be24.read(data, 0), uint24(0x010203));
        assertEq(Be24.read(data, 1), uint24(0x020304));
    }

    function test_ReadUnchecked_ReturnsCorrectValue() public pure {
        bytes memory data = hex"0A0B0C0D";
        assertEq(Be24.readUnchecked(data, 0), uint24(0x0A0B0C));
        assertEq(Be24.readUnchecked(data, 1), uint24(0x0B0C0D));
    }

    function test_Write_StoresCorrectBytes() public pure {
        bytes memory data = new bytes(5);
        Be24.write(data, 1, uint24(0x010203));
        bytes memory expected = hex"0001020300";
        assertEq(keccak256(data), keccak256(expected));
    }

    function test_WriteUnchecked_StoresCorrectBytes() public pure {
        bytes memory data = new bytes(5);
        Be24.writeUnchecked(data, 1, uint24(0x010203));
        bytes memory expected = hex"0001020300";
        assertEq(keccak256(data), keccak256(expected));
    }

    /*/////////////////////////////////////////////////////////////////////////
                              BOUNDS CHECKING
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_Read_OutOfBounds() public {
        bytes memory data = new bytes(2);
        vm.expectRevert(Be24.OutOfBounds.selector);
        Be24.read(data, 0);

        data = new bytes(3);
        vm.expectRevert(Be24.OutOfBounds.selector);
        Be24.read(data, 1);
    }

    function test_RevertWhen_Write_OutOfBounds() public {
        bytes memory data = new bytes(2);
        vm.expectRevert(Be24.OutOfBounds.selector);
        Be24.write(data, 0, 1);

        data = new bytes(3);
        vm.expectRevert(Be24.OutOfBounds.selector);
        Be24.write(data, 1, 1);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 ROUND-TRIP
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_RoundTrip_RetainsValue(uint256 valueSeed, uint256 offsetSeed) public pure {
        uint24 value = uint24(bound(valueSeed, 0, type(uint24).max));
        uint256 offset = bound(offsetSeed, 0, 64);
        bytes memory data = new bytes(offset + 3);

        Be24.write(data, offset, value);
        assertEq(Be24.read(data, offset), value);
        assertEq(Be24.readUnchecked(data, offset), value);

        // Verify writeUnchecked produces the same result
        bytes memory data2 = new bytes(offset + 3);
        Be24.writeUnchecked(data2, offset, value);
        assertEq(Be24.readUnchecked(data2, offset), value);
    }
}

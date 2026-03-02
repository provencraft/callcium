// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorTest } from "../Descriptor.t.sol";

import { TypeCode } from "src/TypeCode.sol";
import { TypeDesc } from "src/TypeDesc.sol";

contract TypeDescEnumTest is DescriptorTest {
    function test_Enum_DefaultSize() public pure {
        bytes memory e = TypeDesc.enum_();
        assertEq(e.length, 1);
        assertEq(uint8(e[0]), TypeCode.UINT8);
    }

    function test_EnumN_ValidSizes() public pure {
        bytes memory e8 = TypeDesc.enum_(8);
        bytes memory e16 = TypeDesc.enum_(16);
        bytes memory e24 = TypeDesc.enum_(24);
        bytes memory e32 = TypeDesc.enum_(32);
        assertEq(uint8(e8[0]), TypeCode.UINT8);
        assertEq(uint8(e16[0]), TypeCode.UINT16);
        assertEq(uint8(e24[0]), TypeCode.UINT24);
        assertEq(uint8(e32[0]), TypeCode.UINT32);
    }

    function test_RevertWhen_EnumN_InvalidBits() public {
        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidUintBits.selector, uint16(0)));
        TypeDesc.enum_(0);

        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidUintBits.selector, uint16(7)));
        TypeDesc.enum_(7);

        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidUintBits.selector, uint16(9)));
        TypeDesc.enum_(9);

        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidUintBits.selector, uint16(257)));
        TypeDesc.enum_(257);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { TypeCode } from "src/TypeCode.sol";

contract TypeCodeUintNTest is Test {
    function test_ReturnsExpectedCode() public pure {
        for (uint16 bits = 8; bits <= 256; bits += 8) {
            uint8 expected = uint8(TypeCode.UINT8 + (bits / 8 - 1));
            assertEq(TypeCode.uintN(bits), expected);
        }
    }

    function test_RevertWhen_NotMultipleOf8() public {
        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidUintBits.selector, 9));
        TypeCode.uintN(9);
    }

    function test_RevertWhen_BelowMin() public {
        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidUintBits.selector, 0));
        TypeCode.uintN(0);
    }

    function test_RevertWhen_AboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidUintBits.selector, 264));
        TypeCode.uintN(264);
    }
}

contract TypeCodeIntNTest is Test {
    function test_ReturnsExpectedCode() public pure {
        for (uint16 bits = 8; bits <= 256; bits += 8) {
            uint8 expected = uint8(TypeCode.INT8 + (bits / 8 - 1));
            assertEq(TypeCode.intN(bits), expected);
        }
    }

    function test_RevertWhen_NotMultipleOf8() public {
        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidIntBits.selector, 15));
        TypeCode.intN(15);
    }

    function test_RevertWhen_BelowMin() public {
        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidIntBits.selector, 0));
        TypeCode.intN(0);
    }

    function test_RevertWhen_AboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidIntBits.selector, 264));
        TypeCode.intN(264);
    }
}

contract TypeCodeBytesNTest is Test {
    function test_ReturnsExpectedCode() public pure {
        for (uint8 n = 1; n <= 32; n++) {
            uint8 expected = TypeCode.BYTES1 + (n - 1);
            assertEq(TypeCode.bytesN(n), expected);
        }
    }

    function test_RevertWhen_BelowMin() public {
        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidBytesLength.selector, 0));
        TypeCode.bytesN(0);
    }

    function test_RevertWhen_AboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(TypeCode.InvalidBytesLength.selector, 33));
        TypeCode.bytesN(33);
    }
}

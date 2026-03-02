// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TypeCodeTest } from "../TypeCode.t.sol";
import { TypeCode } from "src/TypeCode.sol";

contract UintNTest is TypeCodeTest {
    function test_ReturnsExpectedCode() public pure {
        for (uint16 bits = 8; bits <= 256; bits += 8) {
            uint8 expected = uint8((bits / 8) - 1);
            assertEq(TypeCode.uintN(bits), expected);
        }
    }

    function testFuzz_Roundtrip(uint16 bits) public pure {
        vm.assume(bits % 8 == 0 && bits >= 8 && bits <= 256);
        uint8 code = TypeCode.uintN(bits);
        uint16 back = 8 + 8 * uint16(code - TypeCode.UINT8);
        assertEq(back, bits);
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

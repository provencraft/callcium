// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// forge-lint: disable-start(unsafe-typecast)

import { TypeCodeTest } from "../TypeCode.t.sol";
import { TypeCode } from "src/TypeCode.sol";

contract UintNTest is TypeCodeTest {
    function test_ReturnsExpectedCode() public pure {
        for (uint16 bits = 8; bits <= 256; bits += 8) {
            // forge-lint: disable-next-line(unsafe-typecast) bits <= 256 per the loop bound.
            uint8 expected = uint8(bits / 8);
            assertEq(TypeCode.uintN(bits), expected);
        }
    }

    function testFuzz_Roundtrip(uint16 bits) public pure {
        bits = uint16(bound(bits, 1, 32)) * 8;
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

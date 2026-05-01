// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TypeCodeTest } from "../TypeCode.t.sol";
import { TypeCode } from "src/TypeCode.sol";

contract BytesNTest is TypeCodeTest {
    function test_ReturnsExpectedCode() public pure {
        for (uint8 n = 1; n <= 32; n++) {
            uint8 expected = uint8(0x50 + (n - 1));
            assertEq(TypeCode.bytesN(n), expected);
        }
    }

    function testFuzz_Roundtrip(uint8 length) public pure {
        length = uint8(bound(length, 1, 32));
        uint8 code = TypeCode.bytesN(length);
        uint8 back = 1 + (code - TypeCode.BYTES1);
        assertEq(back, length);
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

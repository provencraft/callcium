// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { TypeRuleTest } from "../TypeRule.t.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

contract CanonicalizeTest is TypeRuleTest {
    /*/////////////////////////////////////////////////////////////////////////
                              CLEAN INPUT IS A NO-OP
    /////////////////////////////////////////////////////////////////////////*/

    // Honest, canonically-encoded values must pass through unchanged so normal
    // enforcement behaviour is identical before and after canonicalization.

    function testFuzz_CleanUintIsNoOp(uint256 widthIndex, uint256 value) public pure {
        uint8 code = uint8(bound(widthIndex, 0, 31)); // UINT8..UINT256
        uint256 bits = (uint256(code) + 1) * 8;
        uint256 clean = bits == 256 ? value : value & ((uint256(1) << bits) - 1);
        assertEq(uint256(TypeRule.canonicalize(bytes32(clean), code)), clean);
    }

    function testFuzz_CleanBytesNIsNoOp(uint256 lengthIndex, bytes32 value) public pure {
        uint8 n = uint8(bound(lengthIndex, 1, 32));
        uint8 code = uint8(0x4F + n); // BYTES1..BYTES32
        // Clean bytesN: only the high N bytes set.
        bytes32 clean = n == 32 ? value : bytes32(uint256(value) & ~((uint256(1) << ((32 - n) * 8)) - 1));
        assertEq(TypeRule.canonicalize(clean, code), clean);
    }

    function testFuzz_FullWidthIsIdentity(uint256 value) public pure {
        assertEq(TypeRule.canonicalize(bytes32(value), TypeCode.UINT256), bytes32(value));
        assertEq(TypeRule.canonicalize(bytes32(value), TypeCode.INT256), bytes32(value));
        assertEq(TypeRule.canonicalize(bytes32(value), TypeCode.BYTES32), bytes32(value));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                UNSIGNED MASKING
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_DirtyUintMaskedToWidth(uint256 widthIndex, uint256 value) public pure {
        uint8 code = uint8(bound(widthIndex, 0, 30)); // exclude UINT256 (no spare bits)
        uint256 bits = (uint256(code) + 1) * 8;
        bytes32 got = TypeRule.canonicalize(bytes32(value), code);
        assertEq(uint256(got), value & ((uint256(1) << bits) - 1), "low bits preserved");
        assertEq(uint256(got) >> bits, 0, "high bits cleared");
    }

    function test_UintDirtyHighBits() public pure {
        // uint64 with dirty bit above the width collapses to the low 64 bits.
        bytes32 got = TypeRule.canonicalize(bytes32((uint256(1) << 64) | 5), TypeCode.UINT64);
        assertEq(uint256(got), 5);
    }

    /*/////////////////////////////////////////////////////////////////////////
                               SIGNED EXTENSION
    /////////////////////////////////////////////////////////////////////////*/

    function test_Int8SignExtends() public pure {
        assertEq(int256(uint256(TypeRule.canonicalize(bytes32(uint256(0xFF)), TypeCode.INT8))), -1);
        assertEq(int256(uint256(TypeRule.canonicalize(bytes32(uint256(0x80)), TypeCode.INT8))), -128);
        assertEq(int256(uint256(TypeRule.canonicalize(bytes32(uint256(0x7F)), TypeCode.INT8))), 127);
    }

    function test_Int64SignExtendsNonExtendedWord() public pure {
        // Low 64 bits all set, high bits zero: canonical int64 value is -1.
        bytes32 got = TypeRule.canonicalize(bytes32(uint256(type(uint64).max)), TypeCode.INT64);
        assertEq(int256(uint256(got)), -1);
    }

    function testFuzz_SignedMatchesIntNCast(uint256 widthIndex, uint256 value) public pure {
        uint8 byteIndex = uint8(bound(widthIndex, 0, 30)); // INT8..INT248 (exclude INT256)
        uint8 code = uint8(TypeCode.INT8 + byteIndex);
        bytes32 got = TypeRule.canonicalize(bytes32(value), code);
        // Reference: sign-extend from the top byte of the type via the EVM opcode.
        bytes32 expected;
        assembly {
            expected := signextend(byteIndex, value)
        }
        assertEq(got, expected);
    }

    /*/////////////////////////////////////////////////////////////////////////
                            FIXED BYTES / ADDRESS / BOOL
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_BytesNClearsPadding(uint256 lengthIndex, bytes32 value) public pure {
        uint8 n = uint8(bound(lengthIndex, 1, 31)); // exclude bytes32 (no padding)
        uint8 code = uint8(0x4F + n);
        bytes32 got = TypeRule.canonicalize(value, code);
        uint256 padBits = (32 - n) * 8;
        assertEq(uint256(got) >> padBits, uint256(value) >> padBits, "high N bytes preserved");
        assertEq(uint256(got) & ((uint256(1) << padBits) - 1), 0, "padding cleared");
    }

    function test_AddressMasksHighBits() public pure {
        address a = address(0x00112233445566778899AaBBCCDdEefF01234567);
        uint256 dirty = (uint256(0x89ab) << 160) | uint256(uint160(a));
        bytes32 got = TypeRule.canonicalize(bytes32(dirty), TypeCode.ADDRESS);
        assertEq(address(uint160(uint256(got))), a);
        assertEq(uint256(got) >> 160, 0, "high bits cleared");
    }

    function test_BoolCollapsesToLowBit() public pure {
        assertEq(uint256(TypeRule.canonicalize(bytes32(uint256(1)), TypeCode.BOOL)), 1);
        assertEq(uint256(TypeRule.canonicalize(bytes32(uint256(0)), TypeCode.BOOL)), 0);
        // Dirty word with low bit set canonicalizes to true.
        assertEq(uint256(TypeRule.canonicalize(bytes32((uint256(1) << 200) | 1), TypeCode.BOOL)), 1);
        // Dirty word with low bit clear canonicalizes to false.
        assertEq(uint256(TypeRule.canonicalize(bytes32(uint256(1) << 200), TypeCode.BOOL)), 0);
    }

    function test_FunctionClearsLowPaddingBytes() public pure {
        // function is encoded identical to bytes24: the 24-byte value (20-byte address +
        // 4-byte selector) is left-aligned in the high 24 bytes; the low 8 bytes are padding.
        uint256 word = uint256(0x0102030405060708090a0b0c0d0e0f101112131415161718) << 64;
        bytes32 dirty = bytes32(word | uint256(0x0123456789abcdef));
        bytes32 got = TypeRule.canonicalize(dirty, TypeCode.FUNCTION);
        assertEq(uint256(got), word, "low 8 padding bytes cleared, high 24 bytes preserved");
        assertEq(uint256(got) & type(uint64).max, 0, "low 8 bytes cleared");
    }
}

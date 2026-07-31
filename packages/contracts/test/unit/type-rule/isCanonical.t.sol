// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { TypeRuleTest } from "../TypeRule.t.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

contract IsCanonicalTest is TypeRuleTest {
    /*/////////////////////////////////////////////////////////////////////////
                              AGREEMENT WITH CANONICALIZE
    /////////////////////////////////////////////////////////////////////////*/

    // The predicate is exactly the fixed-point test of the encoding table: a word is canonical
    // where normalizing it changes nothing. Pinning the equivalence keeps the two from drifting.

    function testFuzz_MatchesCanonicalizeFixedPoint(uint256 codeSeed, bytes32 value) public pure {
        uint8 code = uint8(bound(codeSeed, 0, type(uint8).max));
        vm.assume(TypeRule.isValid(code));
        assertEq(TypeRule.isCanonical(value, code), TypeRule.canonicalize(value, code) == value);
    }

    function testFuzz_CanonicalizeOutputIsAlwaysCanonical(uint256 codeSeed, bytes32 value) public pure {
        uint8 code = uint8(bound(codeSeed, 0, type(uint8).max));
        vm.assume(TypeRule.isValid(code));
        assertTrue(TypeRule.isCanonical(TypeRule.canonicalize(value, code), code));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    FULL WIDTH
    /////////////////////////////////////////////////////////////////////////*/

    // Types occupying the whole word constrain nothing, so every word is canonical.

    function testFuzz_FullWidthAcceptsAnyWord(bytes32 value) public pure {
        assertTrue(TypeRule.isCanonical(value, TypeCode.UINT256));
        assertTrue(TypeRule.isCanonical(value, TypeCode.INT256));
        assertTrue(TypeRule.isCanonical(value, TypeCode.BYTES32));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 NARROW ENCODINGS
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_UintRejectsBitsAboveWidth(uint256 widthIndex, uint256 value) public pure {
        uint8 code = uint8(bound(widthIndex, 0, 30)); // UINT8..UINT248, excluding the full word.
        uint256 bits = (uint256(code) + 1) * 8;
        uint256 clean = value & ((uint256(1) << bits) - 1);
        assertTrue(TypeRule.isCanonical(bytes32(clean), code));
        assertFalse(TypeRule.isCanonical(bytes32(clean | (uint256(1) << bits)), code));
    }

    function testFuzz_BytesNRejectsNonZeroPadding(uint256 lengthIndex, bytes32 value) public pure {
        uint8 n = uint8(bound(lengthIndex, 1, 31)); // BYTES1..BYTES31, excluding the full word.
        uint8 code = uint8(uint256(TypeCode.BYTES1) + n - 1);
        uint256 padBits = (32 - n) * 8;
        bytes32 clean = bytes32((uint256(value) >> padBits) << padBits);
        assertTrue(TypeRule.isCanonical(clean, code));
        assertFalse(TypeRule.isCanonical(bytes32(uint256(clean) | 1), code));
    }

    function test_SignedRequiresSignExtension() public pure {
        // Low 64 bits all set encodes -1, which is canonical only when the high bits repeat the sign.
        assertFalse(TypeRule.isCanonical(bytes32(uint256(type(uint64).max)), TypeCode.INT64));
        assertTrue(TypeRule.isCanonical(bytes32(type(uint256).max), TypeCode.INT64));
    }

    function test_AddressRejectsBitsAbove160() public pure {
        bytes32 clean = bytes32(uint256(uint160(address(1))));
        assertTrue(TypeRule.isCanonical(clean, TypeCode.ADDRESS));
        assertFalse(TypeRule.isCanonical(bytes32(uint256(clean) | (uint256(1) << 160)), TypeCode.ADDRESS));
    }

    function test_BoolAcceptsOnlyZeroAndOne() public pure {
        assertTrue(TypeRule.isCanonical(bytes32(uint256(0)), TypeCode.BOOL));
        assertTrue(TypeRule.isCanonical(bytes32(uint256(1)), TypeCode.BOOL));
        assertFalse(TypeRule.isCanonical(bytes32(uint256(2)), TypeCode.BOOL));
    }

    function test_FunctionRejectsNonZeroTrailingPadding() public pure {
        bytes32 clean = bytes32(uint256(0x0102030405060708090a0b0c0d0e0f101112131415161718) << 64);
        assertTrue(TypeRule.isCanonical(clean, TypeCode.FUNCTION));
        assertFalse(TypeRule.isCanonical(bytes32(uint256(clean) | 1), TypeCode.FUNCTION));
    }
}

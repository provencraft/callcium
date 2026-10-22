// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

/// @notice Reference readings of the static elementary types, stated as value ranges rather than the shifts and sign
/// extensions the library uses.
abstract contract TypeRuleTest is Test {
    /// @dev Type code ranges of the static elementary types: each 32-width class, then address, bool and function.
    function _typeClasses() internal pure returns (uint8[2][4] memory) {
        return [
            [TypeCode.UINT8, TypeCode.UINT256],
            [TypeCode.INT8, TypeCode.INT256],
            [TypeCode.BYTES1, TypeCode.BYTES32],
            [TypeCode.ADDRESS, TypeCode.FUNCTION]
        ];
    }

    /// @dev Returns the width of a value of the static elementary type `code` in bytes.
    function _width(uint8 code) internal pure returns (uint256) {
        if (code <= TypeCode.UINT256) return code;
        if (code <= TypeCode.INT256) return code - TypeCode.UINT256;
        if (code == TypeCode.ADDRESS) return 20;
        if (code == TypeCode.BOOL) return 1;
        if (code == TypeCode.FUNCTION) return 24;
        return code - TypeCode.BYTES1 + 1;
    }

    /// @dev Returns whether `word` is the ABI encoding of a value of the static elementary type `code`.
    function _isEncoding(uint8 code, bytes32 word) internal pure returns (bool) {
        uint256 value = uint256(word);
        uint256 bits = 8 * _width(code);
        if (code <= TypeCode.UINT256) return bits == 256 || value < 1 << bits;
        if (code <= TypeCode.INT256) {
            if (bits == 256) return true;
            int256 bound = int256(1 << (bits - 1));
            return int256(value) >= -bound && int256(value) < bound;
        }
        if (code == TypeCode.ADDRESS) return value < 1 << 160;
        if (code == TypeCode.BOOL) return value <= 1;
        // Fixed bytes and function pointers fill the high bytes; the bytes below them are zero.
        return bits == 256 || value & ((1 << (256 - bits)) - 1) == 0;
    }

    /// @dev Returns the operand the high `_width(code)` bytes of `raw` hold, as the word its type compares as.
    function _operand(uint8 code, bytes32 raw) internal pure returns (bytes32) {
        uint256 padding = 256 - 8 * _width(code);
        if (code >= TypeCode.INT8 && code <= TypeCode.INT256) return bytes32(uint256(int256(uint256(raw)) >> padding));
        if (code == TypeCode.FUNCTION || code >= TypeCode.BYTES1) {
            return bytes32(uint256(raw) & ~((1 << padding) - 1));
        }
        return bytes32(uint256(raw) >> padding);
    }
}

contract TypeRuleLoadOperandTest is TypeRuleTest {
    /// @dev For a type of the class, an operand loads to the word its type compares as, whatever bytes follow it.
    function _loadsTheOperandItsBytesHold(uint8[2] memory class, uint8 code, bytes32 raw) private pure {
        vm.assume(code >= class[0] && code <= class[1]);
        (uint8 mode,, uint256 width) = TypeRule.canonicalSpec(code);
        assertEq(TypeRule.loadOperand(raw, mode, width), _operand(code, raw));
    }

    /// @dev Every uint type loads the operand its bytes hold.
    function prove_LoadsUints(uint8 code, bytes32 raw) public pure {
        _loadsTheOperandItsBytesHold(_typeClasses()[0], code, raw);
    }

    /// @dev Every int type loads the operand its bytes hold, sign-extended.
    function prove_LoadsInts(uint8 code, bytes32 raw) public pure {
        _loadsTheOperandItsBytesHold(_typeClasses()[1], code, raw);
    }

    /// @dev Every fixed-bytes type loads the operand its bytes hold.
    function prove_LoadsFixedBytes(uint8 code, bytes32 raw) public pure {
        _loadsTheOperandItsBytesHold(_typeClasses()[2], code, raw);
    }

    /// @dev Address, bool and function load the operand their bytes hold.
    function prove_LoadsAddressBoolFunction(uint8 code, bytes32 raw) public pure {
        _loadsTheOperandItsBytesHold(_typeClasses()[3], code, raw);
    }
}

contract TypeRuleCanonicalSpecTest is TypeRuleTest {
    /// @dev For a type of the class, the spec's width is the operand width storage validation reads, and the spec
    /// accepts exactly the words that encode a value of the type.
    function _acceptsExactlyTheEncodings(uint8[2] memory class, uint8 code, bytes32 word) private pure {
        vm.assume(code >= class[0] && code <= class[1]);
        (uint8 mode, uint256 bits, uint256 width) = TypeRule.canonicalSpec(code);
        assertEq(width, TypeRule.operandWidth(code));
        assertEq(TypeRule.checkCanonical(mode, bits, word), _isEncoding(code, word));
    }

    /// @dev The spec of every uint type accepts exactly the words that encode a value of the type.
    function prove_AcceptsExactlyTheEncodingsOfUints(uint8 code, bytes32 word) public pure {
        _acceptsExactlyTheEncodings(_typeClasses()[0], code, word);
    }

    /// @dev The spec of every int type accepts exactly the words that encode a value of the type.
    function prove_AcceptsExactlyTheEncodingsOfInts(uint8 code, bytes32 word) public pure {
        _acceptsExactlyTheEncodings(_typeClasses()[1], code, word);
    }

    /// @dev The spec of every fixed-bytes type accepts exactly the words that encode a value of the type.
    function prove_AcceptsExactlyTheEncodingsOfFixedBytes(uint8 code, bytes32 word) public pure {
        _acceptsExactlyTheEncodings(_typeClasses()[2], code, word);
    }

    /// @dev The specs of address, bool and function accept exactly the words that encode a value of the type.
    function prove_AcceptsExactlyTheEncodingsOfAddressBoolFunction(uint8 code, bytes32 word) public pure {
        _acceptsExactlyTheEncodings(_typeClasses()[3], code, word);
    }
}

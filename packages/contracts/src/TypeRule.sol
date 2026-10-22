// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { TypeCode } from "./TypeCode.sol";

/// @title TypeRule
/// @notice Single source of truth for ABI type properties and validation rules.
library TypeRule {
    /// @dev Bitmap with bit `code` set for every elementary type code. Type codes fit in a uint8, so one word indexes
    /// the whole code space.
    uint256 private constant ELEMENTARY_MASK = ((1 << (uint256(TypeCode.FUNCTION) + 1)) - (1 << TypeCode.UINT8))
        | ((1 << (uint256(TypeCode.STRING) + 1)) - (1 << TypeCode.BYTES1));

    /// @dev Bitmap with bit `code` set for every composite type code.
    uint256 private constant COMPOSITE_MASK =
        (1 << TypeCode.STATIC_ARRAY) | (1 << TypeCode.DYNAMIC_ARRAY) | (1 << TypeCode.TUPLE);

    /// @dev Bitmap with bit `code` set for every type with a calldata-encoded length prefix.
    uint256 private constant CALLDATA_LENGTH_MASK =
        (1 << TypeCode.BYTES) | (1 << TypeCode.STRING) | (1 << TypeCode.DYNAMIC_ARRAY);

    /// @dev Type code of the type a length compares as.
    uint8 internal constant LENGTH_TYPE = TypeCode.UINT32;

    /// @dev Byte width of a value of `LENGTH_TYPE`.
    uint256 internal constant LENGTH_WIDTH = 4;

    /// @dev Canonicity mode: right-aligned value, canonical iff no bits above the width.
    uint8 internal constant CANON_RIGHT = 0;

    /// @dev Canonicity mode: left-aligned value, canonical iff no bits below the payload.
    uint8 internal constant CANON_LEFT = 1;

    /// @dev Canonicity mode: signed integer, canonical iff sign extension is the identity.
    uint8 internal constant CANON_SIGNED = 2;

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns true if `code` has its length encoded in calldata (bytes, string, or dynamic array).
    /// @param code The code to test.
    /// @return True if the type has a calldata-encoded length prefix.
    function hasCalldataLength(uint8 code) internal pure returns (bool) {
        return (CALLDATA_LENGTH_MASK >> code) & 1 != 0;
    }

    /// @notice Returns true if `code` is a composite type marker (array or tuple).
    /// @param code The code to test.
    /// @return True if the code is a composite type.
    function isComposite(uint8 code) internal pure returns (bool) {
        return (COMPOSITE_MASK >> code) & 1 != 0;
    }

    /// @notice Returns true if `code` is a single-byte elementary type (fully specified by one byte).
    /// @param code The code to test.
    /// @return True if the code is an elementary type.
    function isElementary(uint8 code) internal pure returns (bool) {
        return (ELEMENTARY_MASK >> code) & 1 != 0;
    }

    /// @notice Returns the byte width of a value of a static elementary type.
    /// @param code The type code.
    /// @return The width in bytes, or zero when `code` names no static elementary type.
    function operandWidth(uint8 code) internal pure returns (uint256) {
        if (code >= TypeCode.UINT8 && code <= TypeCode.UINT256) return uint256(code) - TypeCode.UINT8 + 1;
        if (code >= TypeCode.INT8 && code <= TypeCode.INT256) return uint256(code) - TypeCode.INT8 + 1;
        if (code == TypeCode.ADDRESS) return 20;
        if (code == TypeCode.BOOL) return 1;
        if (code == TypeCode.FUNCTION) return 24;
        if (code >= TypeCode.BYTES1 && code <= TypeCode.BYTES32) return uint256(code) - TypeCode.BYTES1 + 1;
        return 0;
    }

    /// @notice Returns the word an operand loads to: the high `width` bytes of `raw`, placed at the alignment `mode`
    /// states and sign-extended for a signed integer.
    /// @param raw The 32-byte word read at the operand.
    /// @param mode The alignment mode (CANON_RIGHT, CANON_LEFT, or CANON_SIGNED).
    /// @param width The operand width in bytes, from 1 to 32.
    /// @return operand The loaded operand.
    function loadOperand(bytes32 raw, uint8 mode, uint256 width) internal pure returns (bytes32 operand) {
        unchecked {
            uint256 shift = 256 - 8 * width;
            operand = bytes32(uint256(raw) >> shift);
            if (mode == CANON_LEFT) return bytes32(uint256(operand) << shift);
            if (mode == CANON_SIGNED) {
                assembly ("memory-safe") {
                    operand := signextend(sub(width, 1), operand)
                }
            }
        }
    }

    /// @notice Returns the canonical encoding spec of a static elementary type.
    /// @dev The (mode, bits) pair fully determines canonicity of any word of the type. A shift of 256 gives zero, so
    /// width-256 types and unrecognized codes resolve to a spec that accepts every word.
    /// @param typeCode The type code to resolve.
    /// @return mode The predicate mode (CANON_RIGHT, CANON_LEFT, or CANON_SIGNED).
    /// @return bits The shift width, or the sign byte index for CANON_SIGNED.
    /// @return width The width of a value of the type in bytes.
    function canonicalSpec(uint8 typeCode) internal pure returns (uint8 mode, uint256 bits, uint256 width) {
        unchecked {
            // Unsigned integers: right-aligned at the declared width.
            if (typeCode >= TypeCode.UINT8 && typeCode <= TypeCode.UINT256) {
                return (CANON_RIGHT, uint256(typeCode) << 3, typeCode);
            }

            // Signed integers: sign extension from the type's most significant byte.
            if (typeCode >= TypeCode.INT8 && typeCode <= TypeCode.INT256) {
                bits = uint256(typeCode - TypeCode.INT8);
                return (CANON_SIGNED, bits, bits + 1);
            }

            // Address: right-aligned at 160 bits. Boolean: right-aligned at 1 bit (zero or one), in one byte.
            if (typeCode == TypeCode.ADDRESS) return (CANON_RIGHT, 160, 20);
            if (typeCode == TypeCode.BOOL) return (CANON_RIGHT, 1, 1);

            // Function pointer: encoded identical to bytes24, left-aligned with 8 padding bytes.
            if (typeCode == TypeCode.FUNCTION) return (CANON_LEFT, 192, 24);

            // Fixed bytes: left-aligned at N payload bytes.
            if (typeCode >= TypeCode.BYTES1 && typeCode <= TypeCode.BYTES32) {
                width = uint256(typeCode) - uint256(TypeCode.BYTES1) + 1;
                return (CANON_LEFT, width << 3, width);
            }

            return (CANON_RIGHT, 256, 32);
        }
    }

    /// @notice Returns whether `value` satisfies the canonicity spec from `canonicalSpec`.
    /// @param mode The predicate mode (CANON_RIGHT, CANON_LEFT, or CANON_SIGNED).
    /// @param bits The shift width, or the sign byte index for CANON_SIGNED.
    /// @param value The raw 32-byte word.
    /// @return True if the word carries no bits outside the spec's declared encoding.
    function checkCanonical(uint8 mode, uint256 bits, bytes32 value) internal pure returns (bool) {
        // Right-aligned: no bits above the width. Left-aligned: no bits below the payload.
        if (mode == CANON_RIGHT) return uint256(value) >> bits == 0;
        if (mode == CANON_LEFT) return uint256(value) << bits == 0;

        // Signed: canonical words are fixed points of sign extension.
        bytes32 extended;
        assembly ("memory-safe") {
            extended := signextend(bits, value)
        }
        return extended == value;
    }

    /// @notice Returns the type code a context property carries.
    /// @dev CTX_MSG_SENDER and CTX_TX_ORIGIN are addresses. Every other ID, assigned or not, is UINT256.
    /// @param contextPropertyId The context property ID.
    /// @return The type code the property carries.
    function contextPropertyType(uint16 contextPropertyId) internal pure returns (uint8) {
        return contextPropertyId == PF.CTX_MSG_SENDER || contextPropertyId == PF.CTX_TX_ORIGIN
            ? TypeCode.ADDRESS
            : TypeCode.UINT256;
    }
}

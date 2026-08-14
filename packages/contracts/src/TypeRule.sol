// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { TypeCode } from "./TypeCode.sol";

/// @title TypeRule
/// @notice Single source of truth for ABI type properties and validation rules.
library TypeRule {
    /// @dev Bitmap with bit `code` set for every elementary type code.
    /// Type codes fit in a uint8, so one word indexes the whole code space.
    // forge-lint: disable-next-item(incorrect-shift) bit-index masks over the type code space
    uint256 private constant ELEMENTARY_MASK = ((1 << (uint256(TypeCode.FUNCTION) + 1)) - (1 << TypeCode.UINT8))
        | ((1 << (uint256(TypeCode.STRING) + 1)) - (1 << TypeCode.BYTES1));

    /// @dev Bitmap with bit `code` set for every composite type code.
    // forge-lint: disable-next-item(incorrect-shift) bit-index masks over the type code space
    uint256 private constant COMPOSITE_MASK =
        (1 << TypeCode.STATIC_ARRAY) | (1 << TypeCode.DYNAMIC_ARRAY) | (1 << TypeCode.TUPLE);

    /// @dev Bitmap with bit `code` set for every type with a calldata-encoded length prefix.
    // forge-lint: disable-next-item(incorrect-shift) bit-index masks over the type code space
    uint256 private constant CALLDATA_LENGTH_MASK =
        (1 << TypeCode.BYTES) | (1 << TypeCode.STRING) | (1 << TypeCode.DYNAMIC_ARRAY);

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

    /// @notice Returns true if `code` is any recognized type code byte (elementary or composite marker).
    /// @param code The code to test.
    /// @return True if the code is a valid type code.
    function isValid(uint8 code) internal pure returns (bool) {
        return ((ELEMENTARY_MASK | COMPOSITE_MASK) >> code) & 1 != 0;
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

    /// @notice Returns true if `code` is a signed integer type (int8 through int256).
    /// @param code The code to test.
    /// @return True if the code is a signed integer type.
    function isSigned(uint8 code) internal pure returns (bool) {
        return code >= TypeCode.INT8 && code <= TypeCode.INT256;
    }

    /// @notice Returns true if `code` is a left-aligned type (fixed bytes or function),
    /// whose value occupies the high bytes of the word with zero padding below.
    /// @param code The code to test.
    /// @return True if the code is a left-aligned type.
    function isLeftAligned(uint8 code) internal pure returns (bool) {
        (uint8 mode,) = canonicalSpec(code);
        return mode == CANON_LEFT;
    }

    /// @notice Canonicalizes a raw 32-byte calldata word to its ABI value for the given type.
    /// @dev A scalar loaded from untrusted calldata may carry dirty bits outside the declared
    /// type width. Masking unsigned/address/bool to width, clearing the trailing padding of
    /// left-aligned function/bytesN values, and sign-extending signed integers makes the
    /// comparison use the canonical ABI value, not the raw bytes.
    /// @param value The raw 32-byte word loaded from calldata.
    /// @param typeCode The type code of the value.
    /// @return The canonicalized value.
    function canonicalize(bytes32 value, uint8 typeCode) internal pure returns (bytes32) {
        (uint8 mode, uint256 bits) = canonicalSpec(typeCode);

        // Right-aligned: keep the low `bits`. Left-aligned: keep the high `bits`.
        if (mode == CANON_RIGHT) return bytes32(uint256(value) & (type(uint256).max >> (256 - bits)));
        if (mode == CANON_LEFT) {
            uint256 padBits = 256 - bits;
            return bytes32((uint256(value) >> padBits) << padBits);
        }

        // Signed: sign extension is idempotent, so extending yields the canonical word.
        bytes32 extended;
        assembly ("memory-safe") {
            extended := signextend(bits, value)
        }
        return extended;
    }

    /// @notice Returns the canonicity predicate parameters for a type.
    /// @dev The (mode, bits) pair fully determines canonicity of any word of the type. A shift
    /// of 256 yields zero, so width-256 types and unrecognized codes resolve to a spec that
    /// accepts every word.
    /// @param typeCode The type code to resolve.
    /// @return mode The predicate mode (CANON_RIGHT, CANON_LEFT, or CANON_SIGNED).
    /// @return bits The shift width, or the sign byte index for CANON_SIGNED.
    function canonicalSpec(uint8 typeCode) internal pure returns (uint8 mode, uint256 bits) {
        unchecked {
            // Unsigned integers: right-aligned at the declared width.
            if (typeCode >= TypeCode.UINT8 && typeCode <= TypeCode.UINT256) {
                return (CANON_RIGHT, uint256(typeCode) << 3);
            }

            // Signed integers: sign extension from the type's most significant byte.
            if (typeCode >= TypeCode.INT8 && typeCode <= TypeCode.INT256) {
                return (CANON_SIGNED, uint256(typeCode - TypeCode.INT8));
            }

            // Address: right-aligned at 160 bits. Boolean: right-aligned at 1 bit (zero or one).
            if (typeCode == TypeCode.ADDRESS) return (CANON_RIGHT, 160);
            if (typeCode == TypeCode.BOOL) return (CANON_RIGHT, 1);

            // Function pointer: encoded identical to bytes24, left-aligned with 8 padding bytes.
            if (typeCode == TypeCode.FUNCTION) return (CANON_LEFT, 192);

            // Fixed bytes: left-aligned at N payload bytes.
            if (typeCode >= TypeCode.BYTES1 && typeCode <= TypeCode.BYTES32) {
                return (CANON_LEFT, (uint256(typeCode) - uint256(TypeCode.BYTES1) + 1) << 3);
            }

            return (CANON_RIGHT, 256);
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

    /// @notice Returns whether a raw 32-byte word is the canonical encoding of the given type.
    /// @param value The raw 32-byte word.
    /// @param typeCode The type code of the value.
    /// @return True if the word carries no bits outside the type's declared encoding.
    function isCanonical(bytes32 value, uint8 typeCode) internal pure returns (bool) {
        (uint8 mode, uint256 bits) = canonicalSpec(typeCode);
        return checkCanonical(mode, bits, value);
    }

    /// @notice Returns the physical limits of a numeric type.
    /// @param typeCode The type code to check.
    /// @return min The minimum possible value (raw bits).
    /// @return max The maximum possible value (raw bits).
    function getDomainLimits(uint8 typeCode) internal pure returns (uint256 min, uint256 max) {
        if (typeCode >= TypeCode.UINT8 && typeCode <= TypeCode.UINT256) {
            uint256 bits = uint256(typeCode) * 8;
            min = 0;
            // forge-lint: disable-next-line(incorrect-shift) 2^bits bitmask
            max = bits == 256 ? type(uint256).max : (1 << bits) - 1;
        } else if (typeCode >= TypeCode.INT8 && typeCode <= TypeCode.INT256) {
            uint256 bits = (uint256(typeCode - TypeCode.INT8) + 1) * 8;
            if (bits == 256) {
                min = uint256(type(int256).min);
                max = uint256(type(int256).max);
            } else {
                // forge-lint: disable-next-line(incorrect-shift) 2^(bits-1) bitmask
                max = (1 << (bits - 1)) - 1;
                // forge-lint: disable-next-line(incorrect-shift) 2^(bits-1) bitmask
                min = uint256(-int256(1 << (bits - 1)));
            }
        } else if (typeCode == TypeCode.BOOL) {
            min = 0;
            max = 1;
        } else if (typeCode == TypeCode.ADDRESS) {
            min = 0;
            max = type(uint160).max;
        } else {
            min = 0;
            max = type(uint256).max;
        }
    }
}

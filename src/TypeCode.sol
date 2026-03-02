// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library TypeCode {
    /*/////////////////////////////////////////////////////////////////////////
                                     ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the requested unsigned integer bit width is invalid.
    /// @param bits The bit width requested. Must be a multiple of 8 in [8, 256].
    error InvalidUintBits(uint16 bits);

    /// @notice Thrown when the requested signed integer bit width is invalid.
    /// @param bits The bit width requested. Must be a multiple of 8 in [8, 256].
    error InvalidIntBits(uint16 bits);

    /// @notice Thrown when the requested fixed bytes length is invalid.
    /// @param length The bytes length requested. Must be in [1, 32].
    error InvalidBytesLength(uint8 length);

    /*/////////////////////////////////////////////////////////////////////////
                                      CODES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Unsigned Integers (0x00-0x1F).
    uint8 internal constant UINT8 = 0x00;
    uint8 internal constant UINT16 = 0x01;
    uint8 internal constant UINT24 = 0x02;
    uint8 internal constant UINT32 = 0x03;
    uint8 internal constant UINT40 = 0x04;
    uint8 internal constant UINT48 = 0x05;
    uint8 internal constant UINT56 = 0x06;
    uint8 internal constant UINT64 = 0x07;
    uint8 internal constant UINT72 = 0x08;
    uint8 internal constant UINT80 = 0x09;
    uint8 internal constant UINT88 = 0x0a;
    uint8 internal constant UINT96 = 0x0b;
    uint8 internal constant UINT104 = 0x0c;
    uint8 internal constant UINT112 = 0x0d;
    uint8 internal constant UINT120 = 0x0e;
    uint8 internal constant UINT128 = 0x0f;
    uint8 internal constant UINT136 = 0x10;
    uint8 internal constant UINT144 = 0x11;
    uint8 internal constant UINT152 = 0x12;
    uint8 internal constant UINT160 = 0x13;
    uint8 internal constant UINT168 = 0x14;
    uint8 internal constant UINT176 = 0x15;
    uint8 internal constant UINT184 = 0x16;
    uint8 internal constant UINT192 = 0x17;
    uint8 internal constant UINT200 = 0x18;
    uint8 internal constant UINT208 = 0x19;
    uint8 internal constant UINT216 = 0x1a;
    uint8 internal constant UINT224 = 0x1b;
    uint8 internal constant UINT232 = 0x1c;
    uint8 internal constant UINT240 = 0x1d;
    uint8 internal constant UINT248 = 0x1e;
    uint8 internal constant UINT256 = 0x1f;

    /// @dev Signed Integers (0x20-0x3F).
    uint8 internal constant INT8 = 0x20;
    uint8 internal constant INT16 = 0x21;
    uint8 internal constant INT24 = 0x22;
    uint8 internal constant INT32 = 0x23;
    uint8 internal constant INT40 = 0x24;
    uint8 internal constant INT48 = 0x25;
    uint8 internal constant INT56 = 0x26;
    uint8 internal constant INT64 = 0x27;
    uint8 internal constant INT72 = 0x28;
    uint8 internal constant INT80 = 0x29;
    uint8 internal constant INT88 = 0x2a;
    uint8 internal constant INT96 = 0x2b;
    uint8 internal constant INT104 = 0x2c;
    uint8 internal constant INT112 = 0x2d;
    uint8 internal constant INT120 = 0x2e;
    uint8 internal constant INT128 = 0x2f;
    uint8 internal constant INT136 = 0x30;
    uint8 internal constant INT144 = 0x31;
    uint8 internal constant INT152 = 0x32;
    uint8 internal constant INT160 = 0x33;
    uint8 internal constant INT168 = 0x34;
    uint8 internal constant INT176 = 0x35;
    uint8 internal constant INT184 = 0x36;
    uint8 internal constant INT192 = 0x37;
    uint8 internal constant INT200 = 0x38;
    uint8 internal constant INT208 = 0x39;
    uint8 internal constant INT216 = 0x3a;
    uint8 internal constant INT224 = 0x3b;
    uint8 internal constant INT232 = 0x3c;
    uint8 internal constant INT240 = 0x3d;
    uint8 internal constant INT248 = 0x3e;
    uint8 internal constant INT256 = 0x3f;

    /// @dev Fixed Types (0x40-0x4F).
    uint8 internal constant ADDRESS = 0x40;
    uint8 internal constant BOOL = 0x41;
    uint8 internal constant FUNCTION = 0x42;

    /// @dev Fixed Bytes (0x50-0x6F).
    uint8 internal constant BYTES1 = 0x50;
    uint8 internal constant BYTES2 = 0x51;
    uint8 internal constant BYTES3 = 0x52;
    uint8 internal constant BYTES4 = 0x53;
    uint8 internal constant BYTES5 = 0x54;
    uint8 internal constant BYTES6 = 0x55;
    uint8 internal constant BYTES7 = 0x56;
    uint8 internal constant BYTES8 = 0x57;
    uint8 internal constant BYTES9 = 0x58;
    uint8 internal constant BYTES10 = 0x59;
    uint8 internal constant BYTES11 = 0x5a;
    uint8 internal constant BYTES12 = 0x5b;
    uint8 internal constant BYTES13 = 0x5c;
    uint8 internal constant BYTES14 = 0x5d;
    uint8 internal constant BYTES15 = 0x5e;
    uint8 internal constant BYTES16 = 0x5f;
    uint8 internal constant BYTES17 = 0x60;
    uint8 internal constant BYTES18 = 0x61;
    uint8 internal constant BYTES19 = 0x62;
    uint8 internal constant BYTES20 = 0x63;
    uint8 internal constant BYTES21 = 0x64;
    uint8 internal constant BYTES22 = 0x65;
    uint8 internal constant BYTES23 = 0x66;
    uint8 internal constant BYTES24 = 0x67;
    uint8 internal constant BYTES25 = 0x68;
    uint8 internal constant BYTES26 = 0x69;
    uint8 internal constant BYTES27 = 0x6a;
    uint8 internal constant BYTES28 = 0x6b;
    uint8 internal constant BYTES29 = 0x6c;
    uint8 internal constant BYTES30 = 0x6d;
    uint8 internal constant BYTES31 = 0x6e;
    uint8 internal constant BYTES32 = 0x6f;

    /// @dev Dynamic Elementary Types (0x70-0x7F).
    uint8 internal constant BYTES = 0x70;
    uint8 internal constant STRING = 0x71;

    /// @dev Arrays (0x80-0x8F).
    uint8 internal constant STATIC_ARRAY = 0x80;
    uint8 internal constant DYNAMIC_ARRAY = 0x81;

    /// @dev Tuples (0x90-0x9F).
    uint8 internal constant TUPLE = 0x90;

    /*/////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Computes the type code for an unsigned integer of the given bit width.
    /// @dev Valid widths are multiples of 8 in the inclusive range [8, 256].
    /// @param bits The bit width of the unsigned integer (e.g., 8, 16, 24, …, 256).
    /// @return code The uint8 type code corresponding to the requested width.
    function uintN(uint16 bits) internal pure returns (uint8) {
        require(bits % 8 == 0 && bits >= 8 && bits <= 256, InvalidUintBits(bits));
        unchecked {
            return uint8((bits / 8) - 1);
        }
    }

    /// @notice Computes the type code for a signed integer of the given bit width.
    /// @dev Valid widths are multiples of 8 in the inclusive range [8, 256].
    /// @param bits The bit width of the signed integer (e.g., 8, 16, 24, …, 256).
    /// @return code The uint8 type code corresponding to the requested width.
    function intN(uint16 bits) internal pure returns (uint8) {
        require(bits % 8 == 0 && bits >= 8 && bits <= 256, InvalidIntBits(bits));
        unchecked {
            return uint8(0x20 + (bits / 8) - 1);
        }
    }

    /// @notice Computes the type code for a fixed-size bytes type of the given length.
    /// @dev Valid lengths are in the inclusive range [1, 32], mapping to bytes1…bytes32.
    /// @param length The byte length N for bytesN.
    /// @return code The uint8 type code for bytesN.
    function bytesN(uint8 length) internal pure returns (uint8) {
        require(length >= 1 && length <= 32, InvalidBytesLength(length));
        unchecked {
            return uint8(0x50 + (length - 1));
        }
    }
}

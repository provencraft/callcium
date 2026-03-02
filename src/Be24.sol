// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Be24
/// @notice Helpers for reading and writing big-endian uint24 values.
library Be24 {
    /// @notice Thrown when attempting to read past the end of the buffer.
    error OutOfBounds();

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Reads a big-endian uint24 from memory at the given offset.
    /// @param data The byte buffer to read from.
    /// @param offset The byte offset to start reading.
    /// @return value The decoded uint24.
    function read(bytes memory data, uint256 offset) internal pure returns (uint24) {
        require(offset + 3 <= data.length, OutOfBounds());
        return readUnchecked(data, offset);
    }

    /// @notice Reads a big-endian uint24 without bounds checks.
    /// @dev Caller must ensure `offset + 3 <= data.length`.
    /// @param data The byte buffer to read from.
    /// @param offset The byte offset to start reading.
    /// @return value The decoded uint24.
    function readUnchecked(bytes memory data, uint256 offset) internal pure returns (uint24 value) {
        assembly {
            let ptr := add(add(data, 32), offset)
            value := shr(232, mload(ptr))
        }
    }

    /// @notice Writes a big-endian uint24 to memory at the given offset.
    /// @param data The byte buffer to write to.
    /// @param offset The byte offset to start writing.
    /// @param value The uint24 value to encode.
    function write(bytes memory data, uint256 offset, uint24 value) internal pure {
        require(offset + 3 <= data.length, OutOfBounds());
        assembly ("memory-safe") {
            let ptr := add(add(data, 32), offset)
            mstore8(ptr, shr(16, value))
            mstore8(add(ptr, 1), shr(8, value))
            mstore8(add(ptr, 2), and(value, 0xff))
        }
    }

    /// @notice Writes a big-endian uint24 without bounds checks.
    /// @dev Caller must ensure `offset + 3 <= data.length`.
    /// @param data The byte buffer to write to.
    /// @param offset The byte offset to start writing.
    /// @param value The uint24 value to encode.
    function writeUnchecked(bytes memory data, uint256 offset, uint24 value) internal pure {
        assembly ("memory-safe") {
            let ptr := add(add(data, 32), offset)
            mstore8(ptr, shr(16, value))
            mstore8(add(ptr, 1), shr(8, value))
            mstore8(add(ptr, 2), and(value, 0xff))
        }
    }
}

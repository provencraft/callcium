// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Be16
/// @notice Helpers for reading and writing big-endian uint16 values.
library Be16 {
    /// @notice Thrown when attempting to read past the end of the buffer.
    error OutOfBounds();

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Reads a big-endian uint16 from memory at the given offset.
    /// @param data The byte buffer to read from.
    /// @param offset The byte offset to start reading.
    /// @return value The decoded uint16.
    function read(bytes memory data, uint256 offset) internal pure returns (uint16) {
        require(offset + 2 <= data.length, OutOfBounds());
        return readUnchecked(data, offset);
    }

    /// @notice Reads a big-endian uint16 without bounds checks.
    /// @dev Caller must ensure `offset + 2 <= data.length`.
    /// @param data The byte buffer to read from.
    /// @param offset The byte offset to start reading.
    /// @return value The decoded uint16.
    function readUnchecked(bytes memory data, uint256 offset) internal pure returns (uint16 value) {
        assembly {
            let ptr := add(add(data, 32), offset)
            value := shr(240, mload(ptr))
        }
    }

    /// @notice Writes a big-endian uint16 to memory at the given offset.
    /// @param data The byte buffer to write to.
    /// @param offset The byte offset to start writing.
    /// @param value The uint16 value to encode.
    function write(bytes memory data, uint256 offset, uint16 value) internal pure {
        require(offset + 2 <= data.length, OutOfBounds());
        assembly {
            let ptr := add(add(data, 32), offset)
            mstore8(ptr, shr(8, value))
            mstore8(add(ptr, 1), and(value, 0xff))
        }
    }

    /// @notice Writes a big-endian uint16 without bounds checks.
    /// @dev Caller must ensure `offset + 2 <= data.length`.
    /// @param data The byte buffer to write to.
    /// @param offset The byte offset to start writing.
    /// @param value The uint16 value to encode.
    function writeUnchecked(bytes memory data, uint256 offset, uint16 value) internal pure {
        assembly {
            let ptr := add(add(data, 32), offset)
            mstore8(ptr, shr(8, value))
            mstore8(add(ptr, 1), and(value, 0xff))
        }
    }
}

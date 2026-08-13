// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LibBytes } from "solady/utils/LibBytes.sol";

/// @title CalldataReader
/// @notice Bounds-checked word reads over an ABI-encoded calldata buffer.
library CalldataReader {
    /*/////////////////////////////////////////////////////////////////////////
                                       ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the array index is out of bounds.
    /// @param elementIndex The provided array element index.
    /// @param length The array length.
    error ArrayIndexOutOfBounds(uint256 elementIndex, uint256 length);

    /// @notice Thrown on generic bounds failures.
    error CalldataOutOfBounds();

    /*/////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Loads the 32-byte word at `offset` in calldata.
    /// @param callData The calldata buffer.
    /// @param offset Byte offset of the word.
    /// @return The 32-byte word.
    function loadWord(bytes calldata callData, uint256 offset) internal pure returns (bytes32) {
        return _calldataload(callData, offset);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Loads 32 bytes from calldata with bounds check.
    /// @dev Every offset reaching this bound is derived from a buffer length and wire fields whose
    /// widths keep it far below the top of the range, so the sum cannot wrap.
    function _calldataload(bytes calldata data, uint256 offset) private pure returns (bytes32 word) {
        unchecked {
            require(offset + 32 <= data.length, CalldataOutOfBounds());
        }
        word = LibBytes.loadCalldata(data, offset);
    }
}

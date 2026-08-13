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
    /// @dev Every offset reaching this bound is derived from a buffer length and wire fields whose
    /// widths keep it far below the top of the range, so the sum cannot wrap.
    /// @param callData The calldata buffer.
    /// @param offset Byte offset of the word.
    /// @return The 32-byte word.
    function loadWord(bytes calldata callData, uint256 offset) internal pure returns (bytes32) {
        unchecked {
            require(offset + 32 <= callData.length, CalldataOutOfBounds());
        }
        return LibBytes.loadCalldata(callData, offset);
    }
}

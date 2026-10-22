// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LibBytes } from "./vendor/solady/utils/LibBytes.sol";

/// @title CalldataReader
/// @notice Reader for 32-byte words in a calldata buffer.
library CalldataReader {
    /*/////////////////////////////////////////////////////////////////////////
                                       ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the requested word lies outside the calldata buffer.
    error CalldataOutOfBounds();

    /*/////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Loads the 32-byte word at `offset` in calldata.
    /// @dev Subtracting a word from the length keeps the bound clear of a sum that wraps. Folding both comparisons into
    /// one condition leaves a single branch on the load path.
    /// @param callData The calldata buffer.
    /// @param offset Byte offset of the word.
    /// @return The 32-byte word.
    function loadWord(bytes calldata callData, uint256 offset) internal pure returns (bytes32) {
        uint256 length = callData.length;
        bool inBounds;
        assembly ("memory-safe") {
            inBounds := iszero(or(lt(length, 32), gt(offset, sub(length, 32))))
        }
        require(inBounds, CalldataOutOfBounds());
        return LibBytes.loadCalldata(callData, offset);
    }
}

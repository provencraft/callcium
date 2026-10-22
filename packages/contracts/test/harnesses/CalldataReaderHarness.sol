// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CalldataReader } from "src/CalldataReader.sol";

/// @notice Harness contract to expose CalldataReader internal functions for testing.
contract CalldataReaderHarness {
    /// @dev Loads from the first `length` bytes of `callData`.
    function loadWordWithin(bytes calldata callData, uint256 length, uint256 offset) external pure returns (bytes32) {
        return CalldataReader.loadWord(callData[:length], offset);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CalldataReader } from "src/CalldataReader.sol";

/// @notice Harness contract to expose CalldataReader internal functions for testing.
contract CalldataReaderHarness {
    function loadWord(bytes calldata callData, uint256 offset) external pure returns (bytes32) {
        return CalldataReader.loadWord(callData, offset);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for DescriptorBuilder unit tests.
abstract contract DescriptorBuilderTest is BaseTest {
    /// @dev Returns `uint256` wrapped in `levels` dynamic array suffixes.
    function _nestedArrays(uint256 levels) internal pure returns (string memory types) {
        types = "uint256";
        for (uint256 i = 0; i < levels; ++i) {
            types = string.concat(types, "[]");
        }
    }
}

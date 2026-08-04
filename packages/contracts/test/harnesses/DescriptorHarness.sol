// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Descriptor } from "src/Descriptor.sol";

/// @notice Harness contract to expose Descriptor internal functions for testing.
contract DescriptorHarness {
    function typeAt(bytes memory desc, bytes memory path) external pure returns (Descriptor.TypeInfo memory) {
        return Descriptor.typeAt(desc, path);
    }
}

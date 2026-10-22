// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyCoder } from "src/PolicyCoder.sol";

/// @notice Harness contract to expose PolicyCoder internal functions for testing.
contract PolicyCoderHarness {
    /// @dev Decodes `policy` and encodes the result.
    function reencode(bytes memory policy) external pure returns (bytes memory) {
        return PolicyCoder.encode(PolicyCoder.decode(policy));
    }
}

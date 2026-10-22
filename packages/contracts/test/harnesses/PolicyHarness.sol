// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Policy } from "src/Policy.sol";

/// @notice Harness contract to expose Policy internal functions for testing.
contract PolicyHarness {
    /// @dev Exposes `Policy.validate`.
    function validate(bytes memory policy) external pure {
        Policy.validate(policy);
    }

    /// @dev Exposes `Policy.selector`.
    function selector(bytes memory policy) external pure returns (bytes4) {
        return Policy.selector(policy);
    }
}

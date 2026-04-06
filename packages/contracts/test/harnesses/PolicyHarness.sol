// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Policy } from "src/Policy.sol";

/// @notice Harness contract to expose Policy internal functions for testing.
contract PolicyHarness {
    function validate(bytes memory policy) external pure {
        Policy.validate(policy);
    }

    function version(bytes memory policy) external pure returns (uint8) {
        return Policy.version(policy);
    }

    function selector(bytes memory policy) external pure returns (bytes4) {
        return Policy.selector(policy);
    }

    function isSelectorless(bytes memory policy) external pure returns (bool) {
        return Policy.isSelectorless(policy);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

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

    function hintView(bytes memory policy, uint256 ruleOffset) external pure returns (uint256, uint256) {
        return Policy.hintView(policy, ruleOffset);
    }

    function compileHint(bytes memory desc, bytes memory path) external pure returns (bytes memory) {
        return Policy.compileHint(desc, path);
    }
}

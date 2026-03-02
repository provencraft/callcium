// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Policy } from "src/Policy.sol";

/// @notice Harness contract to expose Policy internal functions for testing.
contract PolicyHarness {
    function validate(bytes memory policyBlob) external pure {
        Policy.validate(policyBlob);
    }

    function version(bytes memory policyBlob) external pure returns (uint8) {
        return Policy.version(policyBlob);
    }

    function selector(bytes memory policyBlob) external pure returns (bytes4) {
        return Policy.selector(policyBlob);
    }

    function isSelectorless(bytes memory policyBlob) external pure returns (bool) {
        return Policy.isSelectorless(policyBlob);
    }
}

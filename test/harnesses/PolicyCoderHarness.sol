// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyCoder, PolicyData } from "src/PolicyCoder.sol";

/// @notice Harness contract to expose PolicyCoder internal functions for testing.
contract PolicyCoderHarness {
    function encode(
        PolicyCoder.Group[] memory groups,
        bytes4 selector,
        bytes memory desc
    )
        external
        pure
        returns (bytes memory)
    {
        return PolicyCoder.encode(groups, selector, desc);
    }

    function encode(PolicyData memory data) external pure returns (bytes memory) {
        return PolicyCoder.encode(data);
    }

    function decode(bytes memory policy) external pure returns (PolicyData memory) {
        return PolicyCoder.decode(policy);
    }
}

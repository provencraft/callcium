// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyEnforcer } from "src/PolicyEnforcer.sol";

/// @notice Harness contract to expose PolicyEnforcer internal functions for testing.
contract PolicyEnforcerHarness {
    function check(bytes memory policy, bytes calldata callData) external view returns (bool) {
        return PolicyEnforcer.check(policy, callData);
    }

    function enforce(bytes memory policy, bytes calldata callData) external view {
        PolicyEnforcer.enforce(policy, callData);
    }
}

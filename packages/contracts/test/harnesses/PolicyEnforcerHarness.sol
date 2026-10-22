// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyEnforcer } from "src/PolicyEnforcer.sol";

/// @notice Harness contract to expose PolicyEnforcer internal functions for testing.
contract PolicyEnforcerHarness {
    /// @dev Exposes `PolicyEnforcer.check`.
    function check(bytes memory policy, bytes calldata callData) external view returns (bool) {
        return PolicyEnforcer.check(policy, callData);
    }

    /// @dev Exposes `PolicyEnforcer.enforce`.
    function enforce(bytes memory policy, bytes calldata callData) external view {
        PolicyEnforcer.enforce(policy, callData);
    }

    /// @dev Payable entry point, for exercising policies that read the call value.
    function checkPayable(bytes memory policy, bytes calldata callData) external payable returns (bool) {
        return PolicyEnforcer.check(policy, callData);
    }
}

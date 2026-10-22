// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManager } from "src/PolicyManager.sol";

/// @notice Harness contract to expose PolicyManager internal functions for testing.
contract PolicyManagerHarness is PolicyManager {
    /// @dev Exposes `_storePolicy`.
    function store(bytes memory policy) external returns (bytes32 policyHash, address pointer) {
        return _storePolicy(policy);
    }

    /// @dev Exposes `_bindPolicy`.
    function bind(address target, bytes32 policyHash) external {
        _bindPolicy(target, policyHash);
    }

    /// @dev Exposes `_unbindPolicy`.
    function unbind(address target, bytes4 selector) external {
        _unbindPolicy(target, selector);
    }

    /// @dev Exposes `_storeAndBindPolicy` over a target list.
    function storeAndBind(address[] calldata targets, bytes memory policy) external returns (bytes32 policyHash) {
        return _storeAndBindPolicy(targets, policy);
    }

    /// @dev Exposes `_storeAndBindPolicy` for one target.
    function storeAndBind(address target, bytes memory policy) external returns (bytes32 policyHash) {
        return _storeAndBindPolicy(target, policy);
    }

    /// @dev Exposes `_resolvePolicy`.
    function resolve(address target, bytes4 selector) external view returns (bytes memory policy) {
        return _resolvePolicy(target, selector);
    }

    /// @dev Exposes `_policyHashFor`.
    function hashFor(address target, bytes4 selector) external view returns (bytes32) {
        return _policyHashFor(target, selector);
    }

    /// @dev Exposes `_loadPolicy`.
    function load(bytes32 policyHash) external view returns (bytes memory policy) {
        return _loadPolicy(policyHash);
    }

    /// @dev Exposes `_policyExists`.
    function exists(bytes32 policyHash) external view returns (bool) {
        return _policyExists(policyHash);
    }

    /// @dev Exposes `_policyPointerOf`.
    function pointerOf(bytes32 policyHash) external view returns (address) {
        return _policyPointerOf(policyHash);
    }
}

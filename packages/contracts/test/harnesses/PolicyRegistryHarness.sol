// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyManager } from "src/PolicyManager.sol";

contract PolicyRegistryHarness is PolicyManager {
    function store(bytes memory policy) external returns (bytes32 policyHash, address pointer) {
        return _storePolicy(policy);
    }

    function bind(address target, bytes4 selector, bytes32 policyHash) external {
        _bindPolicy(target, selector, policyHash);
    }

    function unbind(address target, bytes4 selector) external {
        _unbindPolicy(target, selector);
    }

    function storeAndBind(address[] calldata targets, bytes memory policy) external returns (bytes32 policyHash) {
        return _storeAndBindPolicy(targets, policy);
    }

    function storeAndBind(address target, bytes memory policy) external returns (bytes32 policyHash) {
        return _storeAndBindPolicy(target, policy);
    }

    function resolve(address target, bytes4 selector) external view returns (bytes memory policy) {
        return _resolvePolicy(target, selector);
    }

    function hashFor(address target, bytes4 selector) external view returns (bytes32) {
        return _policyHashFor(target, selector);
    }

    function load(bytes32 policyHash) external view returns (bytes memory policy) {
        return _loadPolicy(policyHash);
    }

    function exists(bytes32 policyHash) external view returns (bool) {
        return _policyExists(policyHash);
    }

    function pointerOf(bytes32 policyHash) external view returns (address) {
        return _policyPointerOf(policyHash);
    }
}

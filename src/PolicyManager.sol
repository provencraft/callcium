// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { PolicyRegistry } from "./PolicyRegistry.sol";

/// @title PolicyManager
/// @notice Abstract contract providing EIP-7201 namespaced policy storage.
abstract contract PolicyManager {
    using PolicyRegistry for PolicyRegistry.Store;

    /// @dev EIP-7201 storage slot for PolicyManager.
    /// keccak256(abi.encode(uint256(keccak256("callcium.storage.PolicyManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant POLICY_STORE_SLOT = 0x8aa465d0fd610b7d06ba8430304aa155d63c58ad6e68cf8241a8a9f56215da00;

    /// @dev Returns the namespaced policy store.
    function _policyStore() private pure returns (PolicyRegistry.Store storage $) {
        bytes32 slot = POLICY_STORE_SLOT;
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Stores a policy blob via SSTORE2.
    /// @dev Stored policies are trusted at enforcement time without semantic validation.
    /// Access to this function is the primary security boundary for enforcement integrity.
    /// @param policy The encoded policy blob.
    /// @return policyHash The keccak256 hash of the policy.
    /// @return pointer The SSTORE2 pointer address.
    function _storePolicy(bytes memory policy) internal returns (bytes32 policyHash, address pointer) {
        return _policyStore().store(policy);
    }

    /// @notice Binds a policy to a (target, selector) pair.
    /// @dev Binding a policy activates it for enforcement on the given target.
    /// Restrict access as tightly as policy storage itself.
    /// @param target The contract address to bind the policy to.
    /// @param selector The function selector.
    /// @param policyHash The policy hash (must already be stored).
    function _bindPolicy(address target, bytes4 selector, bytes32 policyHash) internal {
        _policyStore().bind(target, selector, policyHash);
    }

    /// @notice Unbinds a policy from a (target, selector) pair.
    /// @param target The contract address.
    /// @param selector The function selector.
    function _unbindPolicy(address target, bytes4 selector) internal {
        _policyStore().unbind(target, selector);
    }

    /// @notice Stores a policy and binds it to targets in one call.
    /// @dev Stored policies are trusted at enforcement time without semantic validation,
    /// and binding activates them immediately. Access to this function is the primary security boundary.
    /// @param targets Target addresses to bind to. Use `address(0)` for default.
    /// @param policy The encoded policy blob.
    /// @return policyHash The policy hash.
    function _storeAndBindPolicy(address[] calldata targets, bytes memory policy)
        internal
        returns (bytes32 policyHash)
    {
        return _policyStore().storeAndBind(targets, policy);
    }

    /// @notice Stores a policy and binds it to a single target.
    /// @dev Stored policies are trusted at enforcement time without semantic validation,
    /// and binding activates them immediately. Access to this function is the primary security boundary.
    /// @param target The target address. Use `address(0)` for default.
    /// @param policy The encoded policy blob.
    /// @return policyHash The policy hash.
    function _storeAndBindPolicy(address target, bytes memory policy) internal returns (bytes32 policyHash) {
        return _policyStore().storeAndBind(target, policy);
    }

    /// @notice Resolves and loads the policy for a (target, selector) pair.
    /// @param target The contract address.
    /// @param selector The function selector.
    /// @return The policy blob, or empty bytes if none bound.
    function _resolvePolicy(address target, bytes4 selector) internal view returns (bytes memory) {
        return _policyStore().resolve(target, selector);
    }

    /// @notice Returns the policy hash for a (target, selector) pair.
    /// @param target The contract address.
    /// @param selector The function selector.
    /// @return The policy hash, or bytes32(0) if none bound.
    function _policyHashFor(address target, bytes4 selector) internal view returns (bytes32) {
        return _policyStore().hashFor(target, selector);
    }

    /// @notice Loads a policy blob by its hash.
    /// @param policyHash The policy hash.
    /// @return The policy blob, or empty bytes if not found.
    function _loadPolicy(bytes32 policyHash) internal view returns (bytes memory) {
        return _policyStore().load(policyHash);
    }

    /// @notice Checks if a policy exists in storage.
    /// @param policyHash The policy hash to check.
    /// @return True if the policy exists.
    function _policyExists(bytes32 policyHash) internal view returns (bool) {
        return _policyStore().exists(policyHash);
    }

    /// @notice Returns the SSTORE2 pointer for a policy hash.
    /// @param policyHash The policy hash.
    /// @return The pointer address, or address(0) if not found.
    function _policyPointerOf(bytes32 policyHash) internal view returns (address) {
        return _policyStore().pointerOf(policyHash);
    }
}

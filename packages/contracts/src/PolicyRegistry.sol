// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { SSTORE2 } from "solady/utils/SSTORE2.sol";

import { Policy } from "./Policy.sol";

/// @title PolicyRegistry
/// @notice Library for policy storage and lookup operations.
library PolicyRegistry {
    using EfficientHashLib for bytes;

    /// @dev Maximum policy size (SSTORE2 contract code limit minus overhead).
    uint256 private constant MAX_POLICY_SIZE = 24_575;

    /// @dev Policy store data structure.
    struct Store {
        /// @dev Maps policy hash to SSTORE2 pointer.
        mapping(bytes32 policyHash => address pointer) policyOf;
        /// @dev Maps (target, selector) to policy hash. Use `address(0)` for default policies.
        mapping(address target => mapping(bytes4 selector => bytes32 policyHash)) policyFor;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                     ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when attempting to bind a policy that does not exist.
    error PolicyNotFound(bytes32 policyHash);

    /// @notice Thrown when attempting to bind a zero policy hash.
    error InvalidPolicyHash();

    /// @notice Thrown when policy blob exceeds SSTORE2 size limit.
    error PolicyTooLarge(uint256 size);

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Stores a policy blob via SSTORE2, deduplicating by hash.
    /// @dev Validates the policy structure for new policies.
    /// @param self The policy store.
    /// @param policy The encoded policy blob.
    /// @return policyHash The keccak256 hash of the policy.
    /// @return pointer The SSTORE2 pointer address.
    function store(Store storage self, bytes memory policy) internal returns (bytes32 policyHash, address pointer) {
        require(policy.length <= MAX_POLICY_SIZE, PolicyTooLarge(policy.length));

        policyHash = policy.hash();
        pointer = self.policyOf[policyHash];

        if (pointer == address(0)) {
            Policy.validate(policy);
            pointer = SSTORE2.write(policy);
            self.policyOf[policyHash] = pointer;
        }
    }

    /// @notice Binds a policy to a (target, selector) pair.
    /// @param self The policy store.
    /// @param target The contract address to bind the policy to.
    /// @param selector The function selector.
    /// @param policyHash The policy hash (must already be stored).
    function bind(Store storage self, address target, bytes4 selector, bytes32 policyHash) internal {
        require(policyHash != bytes32(0), InvalidPolicyHash());
        require(self.policyOf[policyHash] != address(0), PolicyNotFound(policyHash));

        self.policyFor[target][selector] = policyHash;
    }

    /// @notice Unbinds a policy from a (target, selector) pair.
    /// @param self The policy store.
    /// @param target The contract address.
    /// @param selector The function selector.
    function unbind(Store storage self, address target, bytes4 selector) internal {
        delete self.policyFor[target][selector];
    }

    /// @notice Stores a policy and binds it to targets in one call.
    /// @param self The policy store.
    /// @param targets Target addresses to bind to. Use `address(0)` for default.
    /// @param policy The encoded policy blob.
    /// @return policyHash The policy hash.
    function storeAndBind(
        Store storage self,
        address[] calldata targets,
        bytes memory policy
    )
        internal
        returns (bytes32 policyHash)
    {
        (policyHash,) = store(self, policy);

        bytes4 selector = Policy.isSelectorless(policy) ? bytes4(0) : Policy.selector(policy);

        uint256 targetCount = targets.length;
        for (uint256 i; i < targetCount; ++i) {
            self.policyFor[targets[i]][selector] = policyHash;
        }
    }

    /// @notice Stores a policy and binds it to a single target.
    /// @param self The policy store.
    /// @param target The target address. Use `address(0)` for default.
    /// @param policy The encoded policy blob.
    /// @return policyHash The policy hash.
    function storeAndBind(
        Store storage self,
        address target,
        bytes memory policy
    )
        internal
        returns (bytes32 policyHash)
    {
        (policyHash,) = store(self, policy);

        bytes4 selector = Policy.isSelectorless(policy) ? bytes4(0) : Policy.selector(policy);

        self.policyFor[target][selector] = policyHash;
    }

    /// @notice Resolves and loads the policy blob for a (target, selector) pair.
    /// @dev Resolution priority: target-specific binding > default > empty.
    /// @param self The policy store.
    /// @param target The contract address.
    /// @param selector The function selector.
    /// @return policy The policy blob, or empty bytes if none bound.
    function resolve(Store storage self, address target, bytes4 selector) internal view returns (bytes memory policy) {
        bytes32 policyHash = self.policyFor[target][selector];
        if (policyHash == bytes32(0)) policyHash = self.policyFor[address(0)][selector];
        if (policyHash == bytes32(0)) return policy;

        return SSTORE2.read(self.policyOf[policyHash]);
    }

    /// @notice Returns the policy hash for a (target, selector) pair without loading the blob.
    /// @param self The policy store.
    /// @param target The contract address.
    /// @param selector The function selector.
    /// @return The policy hash, or bytes32(0) if none bound.
    function hashFor(Store storage self, address target, bytes4 selector) internal view returns (bytes32) {
        bytes32 policyHash = self.policyFor[target][selector];
        return policyHash != bytes32(0) ? policyHash : self.policyFor[address(0)][selector];
    }

    /// @notice Loads a policy blob by its hash.
    /// @param self The policy store.
    /// @param policyHash The policy hash.
    /// @return policy The policy blob, or empty bytes if not found.
    function load(Store storage self, bytes32 policyHash) internal view returns (bytes memory policy) {
        address pointer = self.policyOf[policyHash];
        return pointer == address(0) ? policy : SSTORE2.read(pointer);
    }

    /// @notice Checks if a policy exists in storage.
    /// @param self The policy store.
    /// @param policyHash The policy hash to check.
    /// @return True if the policy exists.
    function exists(Store storage self, bytes32 policyHash) internal view returns (bool) {
        return self.policyOf[policyHash] != address(0);
    }

    /// @notice Returns the SSTORE2 pointer for a policy hash.
    /// @param self The policy store.
    /// @param policyHash The policy hash.
    /// @return The pointer address, or address(0) if not found.
    function pointerOf(Store storage self, bytes32 policyHash) internal view returns (address) {
        return self.policyOf[policyHash];
    }
}

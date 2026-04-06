// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyRegistry } from "src/PolicyRegistry.sol";

import { PolicyRegistryTest } from "../PolicyRegistry.t.sol";

contract BindTest is PolicyRegistryTest {
    address internal constant TARGET = address(1);

    function test_ValidPolicy() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        harness.bind(TARGET, SELECTOR, hash);

        assertEq(harness.hashFor(TARGET, SELECTOR), hash);
        assertEq(harness.resolve(TARGET, SELECTOR), policy);
    }

    function test_OverwritesExisting() public {
        bytes memory policy1 = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        bytes memory policy2 = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(43))).buildUnsafe();
        (bytes32 hash1,) = harness.store(policy1);
        (bytes32 hash2,) = harness.store(policy2);

        harness.bind(TARGET, SELECTOR, hash1);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash1);

        harness.bind(TARGET, SELECTOR, hash2);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash2);
        assertEq(harness.resolve(TARGET, SELECTOR), policy2);
    }

    function test_RevertWhen_PolicyNotFound() public {
        bytes32 nonExistentHash = keccak256("nonexistent");

        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.PolicyNotFound.selector, nonExistentHash));
        harness.bind(TARGET, SELECTOR, nonExistentHash);
    }

    function test_RevertWhen_ZeroHash() public {
        vm.expectRevert(PolicyRegistry.InvalidPolicyHash.selector);
        harness.bind(TARGET, SELECTOR, bytes32(0));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyManager } from "src/PolicyManager.sol";
import { PolicyRegistry } from "src/PolicyRegistry.sol";

import { PolicyManagerTest } from "../PolicyManager.t.sol";

contract BindTest is PolicyManagerTest {
    address internal constant TARGET = address(1);

    function test_ValidPolicy() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBound(TARGET, SELECTOR, hash);
        harness.bind(TARGET, hash);

        assertEq(harness.hashFor(TARGET, SELECTOR), hash);
        assertEq(harness.resolve(TARGET, SELECTOR), policy);
    }

    function test_SelectorlessBindsUnderZeroSelector() public {
        bytes memory policy = PolicyBuilder.createRaw("uint256").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBound(TARGET, bytes4(0), hash);
        harness.bind(TARGET, hash);

        assertEq(harness.resolve(TARGET, bytes4(0)), policy);
    }

    function test_OverwritesExisting() public {
        bytes memory policy1 = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        bytes memory policy2 = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(43))).buildUnsafe();
        (bytes32 hash1,) = harness.store(policy1);
        (bytes32 hash2,) = harness.store(policy2);

        harness.bind(TARGET, hash1);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash1);

        harness.bind(TARGET, hash2);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash2);
        assertEq(harness.resolve(TARGET, SELECTOR), policy2);
    }

    function test_RevertWhen_PolicyNotFound() public {
        bytes32 nonExistentHash = keccak256("nonexistent");

        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.PolicyNotFound.selector, nonExistentHash));
        harness.bind(TARGET, nonExistentHash);
    }

    function test_RevertWhen_ZeroHash() public {
        vm.expectRevert(PolicyRegistry.InvalidPolicyHash.selector);
        harness.bind(TARGET, bytes32(0));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyRegistryTest } from "../PolicyRegistry.t.sol";

contract ResolveTest is PolicyRegistryTest {
    address internal constant TARGET = address(1);

    function test_ReturnsEmptyWhenNoneBound() public view {
        bytes memory resolved = harness.resolve(TARGET, SELECTOR);
        assertEq(resolved.length, 0);
    }

    function test_TargetSpecificBinding() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        harness.bind(TARGET, SELECTOR, hash);

        bytes memory resolved = harness.resolve(TARGET, SELECTOR);
        assertEq(resolved, policy);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash);
    }

    function test_DefaultFallback() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        harness.bind(address(0), SELECTOR, hash);

        bytes memory resolved = harness.resolve(TARGET, SELECTOR);
        assertEq(resolved, policy);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash);
    }

    function test_PriorityTargetOverDefault() public {
        bytes memory defaultPolicy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        bytes memory targetPolicy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(43))).buildUnsafe();

        (bytes32 defaultHash,) = harness.store(defaultPolicy);
        (bytes32 targetHash,) = harness.store(targetPolicy);

        harness.bind(address(0), SELECTOR, defaultHash);
        harness.bind(TARGET, SELECTOR, targetHash);

        bytes memory resolved = harness.resolve(TARGET, SELECTOR);
        assertEq(resolved, targetPolicy);
        assertEq(harness.hashFor(TARGET, SELECTOR), targetHash);
    }
}

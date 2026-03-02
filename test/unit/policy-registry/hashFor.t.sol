// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyRegistryTest } from "../PolicyRegistry.t.sol";

contract HashForTest is PolicyRegistryTest {
    address internal constant TARGET = address(1);
    address internal constant OTHER_TARGET = address(2);

    function test_ReturnsTargetBinding() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        harness.bind(TARGET, SELECTOR, hash);

        assertEq(harness.hashFor(TARGET, SELECTOR), hash);
    }

    function test_FallsBackToDefault() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        harness.bind(address(0), SELECTOR, hash);

        // Target without specific binding should return default
        assertEq(harness.hashFor(TARGET, SELECTOR), hash);
        assertEq(harness.hashFor(OTHER_TARGET, SELECTOR), hash);
    }

    function test_ReturnsZeroWhenNone() public view {
        assertEq(harness.hashFor(TARGET, SELECTOR), bytes32(0));
    }
}

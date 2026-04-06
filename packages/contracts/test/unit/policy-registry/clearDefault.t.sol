// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyRegistryTest } from "../PolicyRegistry.t.sol";

contract UnbindDefaultTest is PolicyRegistryTest {
    address internal constant TARGET = address(1);

    function test_RemovesDefault() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        harness.bind(address(0), SELECTOR, hash);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash);

        harness.unbind(address(0), SELECTOR);
        assertEq(harness.hashFor(TARGET, SELECTOR), bytes32(0));
    }

    function test_NoOpWhenNotSet() public {
        // Should not revert when clearing non-existent default.
        harness.unbind(address(0), SELECTOR);
        assertEq(harness.hashFor(TARGET, SELECTOR), bytes32(0));
    }
}

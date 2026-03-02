// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyRegistryTest } from "../PolicyRegistry.t.sol";

contract UnbindTest is PolicyRegistryTest {
    address internal constant TARGET = address(1);

    function test_RemovesBinding() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        harness.bind(TARGET, SELECTOR, hash);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash);

        harness.unbind(TARGET, SELECTOR);
        assertEq(harness.hashFor(TARGET, SELECTOR), bytes32(0));
    }

    function test_NoOpWhenNotBound() public {
        // Should not revert when unbinding non-existent binding
        harness.unbind(TARGET, SELECTOR);
        assertEq(harness.hashFor(TARGET, SELECTOR), bytes32(0));
    }
}

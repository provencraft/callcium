// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// forge-lint: disable-start(reentrancy-events, unused-return)

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyManager } from "src/PolicyManager.sol";
import { PolicyRegistry } from "src/PolicyRegistry.sol";

import { PolicyManagerTest } from "../PolicyManager.t.sol";

contract UnbindTest is PolicyManagerTest {
    address internal constant TARGET = address(1);

    function test_RemovesBinding() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        harness.bind(TARGET, hash);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash);

        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBindingChanged(TARGET, SELECTOR, hash, bytes32(0));
        harness.unbind(TARGET, SELECTOR);
        assertEq(harness.hashFor(TARGET, SELECTOR), bytes32(0));
    }

    function test_RevertWhen_NotBound() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.BindingNotFound.selector, TARGET, SELECTOR));
        harness.unbind(TARGET, SELECTOR);
    }
}

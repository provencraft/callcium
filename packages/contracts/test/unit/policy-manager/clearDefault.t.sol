// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// forge-lint: disable-start(unused-return)

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyRegistry } from "src/PolicyRegistry.sol";

import { PolicyManagerTest } from "../PolicyManager.t.sol";

contract UnbindDefaultTest is PolicyManagerTest {
    address internal constant TARGET = address(1);

    function test_RemovesDefault() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        harness.bind(address(0), hash);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash);

        harness.unbind(address(0), SELECTOR);
        assertEq(harness.hashFor(TARGET, SELECTOR), bytes32(0));
    }

    function test_RevertWhen_NotSet() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.BindingNotFound.selector, address(0), SELECTOR));
        harness.unbind(address(0), SELECTOR);
    }
}

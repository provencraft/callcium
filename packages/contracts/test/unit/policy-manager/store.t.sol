// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyManager } from "src/PolicyManager.sol";

import { PolicyManagerTest } from "../PolicyManager.t.sol";

contract StoreTest is PolicyManagerTest {
    function test_NewPolicy() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();

        vm.expectEmit(true, false, false, false);
        emit PolicyManager.PolicyStored(keccak256(policy), address(0));
        (bytes32 hash, address pointer) = harness.store(policy);

        assertTrue(harness.exists(hash));
        assertEq(harness.pointerOf(hash), pointer);
        assertEq(harness.load(hash), policy);
    }

    function test_Deduplicates() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash1, address pointer1) = harness.store(policy);

        // Deduplicated store still emits, with the existing pointer.
        vm.expectEmit(true, false, false, true);
        emit PolicyManager.PolicyStored(hash1, pointer1);
        (bytes32 hash2, address pointer2) = harness.store(policy);

        assertEq(hash1, hash2);
        assertEq(pointer1, pointer2);
    }

    function test_RevertWhen_PolicyTooLarge() public {
        bytes memory largePolicy = new bytes(24576);
        vm.expectRevert();
        harness.store(largePolicy);
    }
}

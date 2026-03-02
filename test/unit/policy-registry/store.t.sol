// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyRegistryTest } from "../PolicyRegistry.t.sol";

contract StoreTest is PolicyRegistryTest {
    function test_NewPolicy() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash, address pointer) = harness.store(policy);

        assertTrue(harness.exists(hash));
        assertEq(harness.pointerOf(hash), pointer);
        assertEq(harness.load(hash), policy);
    }

    function test_Deduplicates() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash1, address pointer1) = harness.store(policy);
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyRegistryTest } from "../PolicyRegistry.t.sol";

contract StoreAndBindTest is PolicyRegistryTest {
    address internal constant TARGET1 = address(1);
    address internal constant TARGET2 = address(2);
    address internal constant TARGET3 = address(3);

    function test_SingleTarget() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        address[] memory targets = new address[](1);
        targets[0] = TARGET1;

        bytes32 hash = harness.storeAndBind(targets, policy);

        assertTrue(harness.exists(hash));
        assertEq(harness.hashFor(TARGET1, SELECTOR), hash);
        assertEq(harness.resolve(TARGET1, SELECTOR), policy);
    }

    function test_MultipleTargets() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        address[] memory targets = new address[](3);
        targets[0] = TARGET1;
        targets[1] = TARGET2;
        targets[2] = TARGET3;

        bytes32 hash = harness.storeAndBind(targets, policy);

        assertTrue(harness.exists(hash));
        assertEq(harness.hashFor(TARGET1, SELECTOR), hash);
        assertEq(harness.hashFor(TARGET2, SELECTOR), hash);
        assertEq(harness.hashFor(TARGET3, SELECTOR), hash);
    }

    function test_DefaultViaAddressZero() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        address[] memory targets = new address[](1);
        targets[0] = address(0);

        bytes32 hash = harness.storeAndBind(targets, policy);

        assertTrue(harness.exists(hash));
        // Any target should resolve to the default.
        assertEq(harness.hashFor(TARGET1, SELECTOR), hash);
        assertEq(harness.resolve(TARGET1, SELECTOR), policy);
    }

    function test_DeduplicatesPolicy() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();

        address[] memory targets1 = new address[](1);
        targets1[0] = TARGET1;
        bytes32 hash1 = harness.storeAndBind(targets1, policy);

        address[] memory targets2 = new address[](1);
        targets2[0] = TARGET2;
        bytes32 hash2 = harness.storeAndBind(targets2, policy);

        assertEq(hash1, hash2);
        assertEq(harness.pointerOf(hash1), harness.pointerOf(hash2));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 SELECTORLESS
    /////////////////////////////////////////////////////////////////////////*/

    function test_Selectorless_SingleTarget() public {
        bytes memory policy = PolicyBuilder.createRaw("uint256").add(arg(0).eq(uint256(42))).buildUnsafe();
        address[] memory targets = new address[](1);
        targets[0] = TARGET1;

        bytes32 hash = harness.storeAndBind(targets, policy);

        assertTrue(harness.exists(hash));
        assertEq(harness.hashFor(TARGET1, bytes4(0)), hash);
        assertEq(harness.resolve(TARGET1, bytes4(0)), policy);
    }

    function test_Selectorless_DefaultViaAddressZero() public {
        bytes memory policy = PolicyBuilder.createRaw("uint256").add(arg(0).eq(uint256(42))).buildUnsafe();

        bytes32 hash = harness.storeAndBind(address(0), policy);

        assertTrue(harness.exists(hash));
        assertEq(harness.hashFor(TARGET1, bytes4(0)), hash);
        assertEq(harness.resolve(TARGET1, bytes4(0)), policy);
    }

    function test_Selectorless_DoesNotCollideWithSelectorPolicy() public {
        bytes memory selectorless = PolicyBuilder.createRaw("uint256").add(arg(0).eq(uint256(42))).buildUnsafe();
        bytes memory withSelector = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();

        address[] memory targets = new address[](1);
        targets[0] = TARGET1;

        bytes32 hashRaw = harness.storeAndBind(targets, selectorless);
        bytes32 hashSel = harness.storeAndBind(targets, withSelector);

        // Different policies, different hashes.
        assertTrue(hashRaw != hashSel);
        // Resolve under different keys.
        assertEq(harness.resolve(TARGET1, bytes4(0)), selectorless);
        assertEq(harness.resolve(TARGET1, Policy.selector(withSelector)), withSelector);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 SINGLE-TARGET OVERLOAD
    /////////////////////////////////////////////////////////////////////////*/

    function test_SingleTargetOverload() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();

        bytes32 hash = harness.storeAndBind(TARGET1, policy);

        assertTrue(harness.exists(hash));
        assertEq(harness.hashFor(TARGET1, SELECTOR), hash);
        assertEq(harness.resolve(TARGET1, SELECTOR), policy);
    }

    function test_SingleTargetOverload_Default() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();

        bytes32 hash = harness.storeAndBind(address(0), policy);

        assertTrue(harness.exists(hash));
        // Any target should resolve to the default.
        assertEq(harness.hashFor(TARGET1, SELECTOR), hash);
        assertEq(harness.resolve(TARGET1, SELECTOR), policy);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 SELECTOR EXTRACTION
    /////////////////////////////////////////////////////////////////////////*/

    function test_ExtractsSelectorFromPolicy() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        address[] memory targets = new address[](1);
        targets[0] = TARGET1;

        harness.storeAndBind(targets, policy);

        // Selector should be extracted from policy signature.
        bytes4 expectedSelector = bytes4(keccak256("foo(uint256)"));
        assertTrue(harness.hashFor(TARGET1, expectedSelector) != bytes32(0));

        // Different selector should not be bound.
        bytes4 otherSelector = bytes4(keccak256("bar(uint256)"));
        assertEq(harness.hashFor(TARGET1, otherSelector), bytes32(0));
    }
}

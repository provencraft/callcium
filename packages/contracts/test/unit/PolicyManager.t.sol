// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Policy } from "src/Policy.sol";
import { PolicyManager } from "src/PolicyManager.sol";
import { PolicyRegistry } from "src/PolicyRegistry.sol";

import { PolicyManagerHarness } from "test/harnesses/PolicyManagerHarness.sol";

abstract contract PolicyManagerTest is Test {
    address internal constant TARGET = address(1);

    bytes4 internal constant SELECTOR = bytes4(keccak256("foo(uint256)"));

    bytes32 internal constant UNKNOWN_HASH = bytes32(uint256(1));

    /// @dev Storage vector `calldata-eq-uint256`: `foo(uint256)` with arg(0) EQ 42.
    bytes internal constant SELECTOR_BLOB =
        hex"602fbebd380003020120010001000000310031010100000000000000000020010020000000000000000000000000000000000000000000000000000000000000002a";

    /// @dev Storage vector `calldata-not-eq`: `foo(uint256)` with arg(0) NOT EQ 42.
    bytes internal constant OTHER_BLOB =
        hex"602fbebd380003020120010001000000310031010100000000000000000020810020000000000000000000000000000000000000000000000000000000000000002a";

    /// @dev Storage vector `selectorless`: the `SELECTOR_BLOB` rule, flagged selectorless, selector slot zero.
    bytes internal constant SELECTORLESS_BLOB =
        hex"61000000000003020120010001000000310031010100000000000000000020010020000000000000000000000000000000000000000000000000000000000000002a";

    /// @dev Storage vector `empty-policy`: a header and descriptor with no groups.
    bytes internal constant EMPTY_POLICY_BLOB = hex"602fbebd38000302012000";

    PolicyManagerHarness internal harness;

    function setUp() public virtual {
        harness = new PolicyManagerHarness();
    }
}

contract PolicyManagerStoreTest is PolicyManagerTest {
    function test_NamespacedSlot() public {
        (bytes32 hash, address pointer) = harness.store(SELECTOR_BLOB);

        bytes32 location =
            keccak256(abi.encode(uint256(keccak256("callcium.storage.PolicyManager")) - 1)) & ~bytes32(uint256(0xff));
        bytes32 policyOfSlot = keccak256(abi.encode(hash, location));
        assertEq(vm.load(address(harness), policyOfSlot), bytes32(uint256(uint160(pointer))));
    }

    function test_Deduplicates() public {
        (bytes32 hash1, address pointer1) = harness.store(SELECTOR_BLOB);

        // A deduplicated store emits with the existing pointer.
        vm.expectEmit(true, false, false, true);
        emit PolicyManager.PolicyStored(keccak256(SELECTOR_BLOB), pointer1);
        (bytes32 hash2, address pointer2) = harness.store(SELECTOR_BLOB);

        assertEq(hash1, hash2);
        assertEq(pointer1, pointer2);
    }

    function test_RevertWhen_PolicyTooLarge() public {
        bytes memory largePolicy = new bytes(24576);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.PolicyTooLarge.selector, largePolicy.length));
        harness.store(largePolicy);
    }

    function test_RevertWhen_PolicyMalformed() public {
        vm.expectRevert(Policy.EmptyPolicy.selector);
        harness.store(EMPTY_POLICY_BLOB);
    }
}

contract PolicyManagerBindTest is PolicyManagerTest {
    function test_SelectorlessBindsUnderZeroSelector() public {
        (bytes32 hash,) = harness.store(SELECTORLESS_BLOB);

        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBindingChanged(TARGET, bytes4(0), bytes32(0), hash);
        harness.bind(TARGET, hash);

        assertEq(harness.resolve(TARGET, bytes4(0)), SELECTORLESS_BLOB);
    }

    function test_OverwritesExisting() public {
        (bytes32 hash1,) = harness.store(SELECTOR_BLOB);
        (bytes32 hash2,) = harness.store(OTHER_BLOB);

        harness.bind(TARGET, hash1);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash1);

        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBindingChanged(TARGET, SELECTOR, hash1, hash2);
        harness.bind(TARGET, hash2);
        assertEq(harness.hashFor(TARGET, SELECTOR), hash2);
        assertEq(harness.resolve(TARGET, SELECTOR), OTHER_BLOB);
    }

    function test_RevertWhen_PolicyNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.PolicyNotFound.selector, UNKNOWN_HASH));
        harness.bind(TARGET, UNKNOWN_HASH);
    }

    function test_RevertWhen_ZeroHash() public {
        vm.expectRevert(PolicyRegistry.InvalidPolicyHash.selector);
        harness.bind(TARGET, bytes32(0));
    }
}

contract PolicyManagerUnbindTest is PolicyManagerTest {
    function test_RemovesBinding() public {
        (bytes32 hash,) = harness.store(SELECTOR_BLOB);

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

contract PolicyManagerStoreAndBindTest is PolicyManagerTest {
    address internal constant TARGET1 = address(1);
    address internal constant TARGET2 = address(2);
    address internal constant TARGET3 = address(3);

    function test_MultipleTargets() public {
        address[] memory targets = new address[](3);
        targets[0] = TARGET1;
        targets[1] = TARGET2;
        targets[2] = TARGET3;

        vm.expectEmit(true, false, false, false);
        emit PolicyManager.PolicyStored(keccak256(SELECTOR_BLOB), address(0));
        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBindingChanged(TARGET1, SELECTOR, bytes32(0), keccak256(SELECTOR_BLOB));
        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBindingChanged(TARGET2, SELECTOR, bytes32(0), keccak256(SELECTOR_BLOB));
        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBindingChanged(TARGET3, SELECTOR, bytes32(0), keccak256(SELECTOR_BLOB));
        bytes32 hash = harness.storeAndBind(targets, SELECTOR_BLOB);

        assertEq(harness.hashFor(TARGET1, SELECTOR), hash);
        assertEq(harness.hashFor(TARGET2, SELECTOR), hash);
        assertEq(harness.hashFor(TARGET3, SELECTOR), hash);
    }

    function test_RebindEmitsPreviousHash() public {
        address[] memory targets = new address[](2);
        targets[0] = TARGET1;
        targets[1] = TARGET2;

        bytes32 hash1 = harness.storeAndBind(targets, SELECTOR_BLOB);

        // TARGET2 unbound between the two calls: the second call rebinds TARGET1 and freshly binds TARGET2.
        harness.unbind(TARGET2, SELECTOR);

        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBindingChanged(TARGET1, SELECTOR, hash1, keccak256(OTHER_BLOB));
        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBindingChanged(TARGET2, SELECTOR, bytes32(0), keccak256(OTHER_BLOB));
        harness.storeAndBind(targets, OTHER_BLOB);
    }

    function test_SingleTargetOverload() public {
        vm.expectEmit(true, false, false, false);
        emit PolicyManager.PolicyStored(keccak256(SELECTOR_BLOB), address(0));
        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBindingChanged(TARGET1, SELECTOR, bytes32(0), keccak256(SELECTOR_BLOB));
        bytes32 hash = harness.storeAndBind(TARGET1, SELECTOR_BLOB);

        assertEq(harness.hashFor(TARGET1, SELECTOR), hash);
        assertEq(harness.resolve(TARGET1, SELECTOR), SELECTOR_BLOB);
    }

    function test_SingleTargetOverload_RebindEmitsPreviousHash() public {
        bytes32 hash1 = harness.storeAndBind(TARGET1, SELECTOR_BLOB);

        vm.expectEmit(true, true, true, true);
        emit PolicyManager.PolicyBindingChanged(TARGET1, SELECTOR, hash1, keccak256(OTHER_BLOB));
        harness.storeAndBind(TARGET1, OTHER_BLOB);
    }

    function test_RevertWhen_EmptyTargets() public {
        address[] memory targets = new address[](0);

        vm.expectRevert(PolicyRegistry.EmptyTargets.selector);
        harness.storeAndBind(targets, SELECTOR_BLOB);
    }
}

contract PolicyManagerResolveTest is PolicyManagerTest {
    function test_ReturnsEmptyWhenNoneBound() public view {
        bytes memory resolved = harness.resolve(TARGET, SELECTOR);
        assertEq(resolved.length, 0);
    }

    function test_DefaultFallback() public {
        (bytes32 hash,) = harness.store(SELECTOR_BLOB);

        harness.bind(address(0), hash);

        bytes memory resolved = harness.resolve(TARGET, SELECTOR);
        assertEq(resolved, SELECTOR_BLOB);
    }

    function test_PriorityTargetOverDefault() public {
        (bytes32 defaultHash,) = harness.store(SELECTOR_BLOB);
        (bytes32 targetHash,) = harness.store(OTHER_BLOB);

        harness.bind(address(0), defaultHash);
        harness.bind(TARGET, targetHash);

        bytes memory resolved = harness.resolve(TARGET, SELECTOR);
        assertEq(resolved, OTHER_BLOB);
    }
}

contract PolicyManagerLoadTest is PolicyManagerTest {
    function test_ReturnsStoredPolicy() public {
        (bytes32 hash,) = harness.store(SELECTOR_BLOB);

        bytes memory loaded = harness.load(hash);
        assertEq(loaded, SELECTOR_BLOB);
    }

    function test_ReturnsEmptyForNonExistent() public view {
        bytes memory loaded = harness.load(UNKNOWN_HASH);
        assertEq(loaded.length, 0);
    }
}

contract PolicyManagerExistsTest is PolicyManagerTest {
    function test_TrueForStoredPolicy() public {
        (bytes32 hash,) = harness.store(SELECTOR_BLOB);

        assertTrue(harness.exists(hash));
    }

    function test_FalseForNonExistent() public view {
        assertFalse(harness.exists(UNKNOWN_HASH));
    }
}

contract PolicyManagerPointerOfTest is PolicyManagerTest {
    function test_ReturnsAddress() public {
        (bytes32 hash, address pointer) = harness.store(SELECTOR_BLOB);

        assertEq(harness.pointerOf(hash), pointer);
        assertTrue(pointer != address(0));
    }
}

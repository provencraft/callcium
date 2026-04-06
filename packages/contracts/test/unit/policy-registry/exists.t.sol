// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyRegistryTest } from "../PolicyRegistry.t.sol";

contract ExistsTest is PolicyRegistryTest {
    function test_TrueForStoredPolicy() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        assertTrue(harness.exists(hash));
    }

    function test_FalseForNonExistent() public view {
        bytes32 nonExistentHash = keccak256("nonexistent");
        assertFalse(harness.exists(nonExistentHash));
    }
}

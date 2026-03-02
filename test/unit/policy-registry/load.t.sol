// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyRegistryTest } from "../PolicyRegistry.t.sol";

contract LoadTest is PolicyRegistryTest {
    function test_ReturnsStoredPolicy() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
        (bytes32 hash,) = harness.store(policy);

        bytes memory loaded = harness.load(hash);
        assertEq(loaded, policy);
    }

    function test_ReturnsEmptyForNonExistent() public view {
        bytes32 nonExistentHash = keccak256("nonexistent");
        bytes memory loaded = harness.load(nonExistentHash);
        assertEq(loaded.length, 0);
    }
}

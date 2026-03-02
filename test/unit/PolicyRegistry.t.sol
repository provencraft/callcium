// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyRegistryHarness } from "test/harnesses/PolicyRegistryHarness.sol";
import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for PolicyRegistry unit tests.
abstract contract PolicyRegistryTest is BaseTest {
    bytes4 internal constant SELECTOR = bytes4(keccak256("foo(uint256)"));

    PolicyRegistryHarness internal harness;

    function setUp() public virtual {
        harness = new PolicyRegistryHarness();
    }
}

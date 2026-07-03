// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerHarness } from "test/harnesses/PolicyManagerHarness.sol";
import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for PolicyRegistry unit tests.
abstract contract PolicyManagerTest is BaseTest {
    bytes4 internal constant SELECTOR = bytes4(keccak256("foo(uint256)"));

    PolicyManagerHarness internal harness;

    function setUp() public virtual {
        harness = new PolicyManagerHarness();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyDraft } from "src/PolicyBuilder.sol";

import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for PolicyBuilder unit tests.
abstract contract PolicyBuilderTest is BaseTest {
    /// @dev Asserts that exactly one constraint was added to the given group.
    function assertConstraintAdded(PolicyDraft memory draft, uint256 groupIndex) internal pure {
        assertEq(draft.data.groups[groupIndex].length, 1);
        assertEq(draft.usedPathHashes[groupIndex].length, 1);
    }
}

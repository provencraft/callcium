// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Operator, arg } from "src/Constraint.sol";

import { ConstraintTest } from "test/unit/Constraint.t.sol";

contract ConstraintBetweenTest is ConstraintTest {
    function test_RevertWhen_MinExceedsMax() public {
        vm.expectRevert(Operator.InvalidRange.selector);
        arg(0).between(uint256(100), uint256(10));
    }

    function test_RevertWhen_SignedMinExceedsMax() public {
        vm.expectRevert(Operator.InvalidRange.selector);
        arg(0).between(int256(5), int256(-1));
    }

    function test_EqualBoundsAccepted() public pure {
        assertEq(arg(0).between(uint256(42), uint256(42)).operators.length, 1);
    }

    function test_SignedEqualBoundsAccepted() public pure {
        assertEq(arg(0).between(int256(-42), int256(-42)).operators.length, 1);
    }
}

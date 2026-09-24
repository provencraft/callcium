// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Operator, arg } from "src/Constraint.sol";

import { ConstraintTest } from "test/unit/Constraint.t.sol";

contract ConstraintLengthBetweenTest is ConstraintTest {
    function test_RevertWhen_MinExceedsMax() public {
        vm.expectRevert(Operator.InvalidRange.selector);
        arg(0).lengthBetween(100, 1);
    }

    function test_EqualBoundsAccepted() public pure {
        assertEq(arg(0).lengthBetween(5, 5).operators.length, 1);
    }
}

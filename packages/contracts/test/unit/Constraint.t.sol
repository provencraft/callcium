// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Constraint, Operator, arg } from "src/Constraint.sol";
import { OpCode } from "src/OpCode.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

contract ConstraintBetweenTest is Test {
    function test_EqualBoundsAccepted() public pure {
        arg(0).between(uint256(5), uint256(5));
    }

    function test_RevertWhen_MinExceedsMax() public {
        vm.expectRevert(Operator.InvalidRange.selector);
        arg(0).between(uint256(2), uint256(1));
    }

    function test_RevertWhen_SignedMinExceedsMax() public {
        vm.expectRevert(Operator.InvalidRange.selector);
        arg(0).between(int256(1), int256(-1));
    }
}

contract ConstraintIsInTest is Test {
    function test_RevertWhen_EmptySet() public {
        vm.expectRevert(Operator.EmptySet.selector);
        arg(0).isIn(new uint256[](0));
    }
}

contract ConstraintLengthBetweenTest is Test {
    function test_RevertWhen_MinExceedsMax() public {
        vm.expectRevert(Operator.InvalidRange.selector);
        arg(0).lengthBetween(2, 1);
    }
}

contract ConstraintEqCtxTest is Test {
    function test_CarriesTheContextSourceAndPropertyId() public pure {
        Constraint memory constraint = arg(0).eqCtx(PF.CTX_MSG_VALUE);

        uint8 contextEq = OpCode.EQ | (OpCode.SOURCE_CONTEXT << OpCode.SOURCE_SHIFT);
        assertEq(constraint.operators[0], abi.encodePacked(contextEq, uint256(PF.CTX_MSG_VALUE)));
    }

    function test_RevertWhen_UnknownProperty() public {
        vm.expectRevert(abi.encodeWithSelector(Operator.UnknownContextProperty.selector, PF.CTX_MAX + 1));
        arg(0).eqCtx(PF.CTX_MAX + 1);
    }
}

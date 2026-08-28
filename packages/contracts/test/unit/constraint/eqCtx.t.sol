// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Operator, arg } from "src/Constraint.sol";
import { OpCode } from "src/OpCode.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

import { LibBytes } from "solady/utils/LibBytes.sol";

import { ConstraintTest } from "test/unit/Constraint.t.sol";

contract ConstraintEqCtxTest is ConstraintTest {
    function test_EncodesOpCodeAndPropertyId() public pure {
        bytes memory op = arg(0).eqCtx(PF.CTX_TX_ORIGIN).operators[0];
        assertEq(op.length, 33);
        assertEq(uint8(op[0]), OpCode.EQ_CTX);
        assertEq(uint256(LibBytes.load(op, 1)), uint256(PF.CTX_TX_ORIGIN));
    }

    function test_NegatedEncodesNotFlag() public pure {
        bytes memory op = arg(0).neqCtx(PF.CTX_MSG_SENDER).operators[0];
        assertEq(uint8(op[0]), OpCode.EQ_CTX | OpCode.NOT);
    }

    function test_PropertyIdAtMax() public pure {
        bytes memory op = arg(0).eqCtx(PF.CTX_MAX).operators[0];
        assertEq(uint256(LibBytes.load(op, 1)), uint256(PF.CTX_MAX));
    }

    function test_RevertWhen_UnknownProperty() public {
        vm.expectRevert(abi.encodeWithSelector(Operator.UnknownContextProperty.selector, PF.CTX_MAX + 1));
        arg(0).eqCtx(PF.CTX_MAX + 1);
    }

    function test_RevertWhen_NegatedUnknownProperty() public {
        vm.expectRevert(abi.encodeWithSelector(Operator.UnknownContextProperty.selector, PF.CTX_MAX + 1));
        arg(0).neqCtx(PF.CTX_MAX + 1);
    }
}

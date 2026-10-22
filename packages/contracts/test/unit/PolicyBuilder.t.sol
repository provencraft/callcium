// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Constraint, Operator, arg, msgSender, msgValue } from "src/Constraint.sol";
import { Descriptor } from "src/Descriptor.sol";
import { Hint } from "src/Hint.sol";
import { IssueCode } from "src/IssueCode.sol";
import { OpCode } from "src/OpCode.sol";
import { Path } from "src/Path.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";
import { PolicyCoder } from "src/PolicyCoder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";
import { PolicyValidator } from "src/PolicyValidator.sol";
import { TypeCode } from "src/TypeCode.sol";
import { Issue } from "src/ValidationIssue.sol";
import { LibBytes } from "src/vendor/solady/utils/LibBytes.sol";

contract PolicyBuilderCreateRawTest is Test {
    function test_SetsSelectorlessFlagWithZeroSlot() public pure {
        bytes memory policy = PolicyBuilder.createRaw("uint256").add(arg(0).eq(uint256(1))).build();

        assertTrue(Policy.isSelectorless(policy));
        assertEq(bytes4(LibBytes.load(policy, PF.POLICY_SELECTOR_OFFSET)), bytes4(0));
    }
}

contract PolicyBuilderAddTest is Test {
    /// @dev Returns a calldata constraint at `path` carrying one equality, its path taken as given.
    function _constraintAt(bytes memory path) private pure returns (Constraint memory constraint) {
        constraint = Constraint({
            scope: PF.SCOPE_CALLDATA, path: path, operators: new bytes[](0), leastNegativeOperand: 0, greatestOperand: 0
        });
        constraint = constraint.eq(uint256(1));
    }

    /// @dev Returns `count` distinct ascending values.
    function _values(uint256 count) private pure returns (uint256[] memory values) {
        values = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            values[i] = i;
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  PATH FAULTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_ArgIndexOutOfBounds() public {
        PolicyDraft memory draft = PolicyBuilder.create("bar(address,uint256)");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.ParamIndexOutOfBounds.selector, 2, 2));
        draft.add(arg(2).eq(uint256(1)));
    }

    function test_RevertWhen_StaticArrayIndexOutOfBounds() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(address[3])");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.StaticArrayIndexOutOfBounds.selector, 3, 3));
        draft.add(arg(0, 3).eq(address(1)));
    }

    function test_RevertWhen_NonCompositeDescent() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.NotComposite.selector, TypeCode.UINT256));
        draft.add(arg(0, 0).eq(uint256(1)));
    }

    function test_RevertWhen_QuantifierOnNonArray() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo((address,uint256))");

        vm.expectRevert(abi.encodeWithSelector(Hint.QuantifierOnNonArray.selector, Path.encode(0, Path.ALL), 1));
        draft.add(arg(0, Path.ALL).eq(uint256(1)));
    }

    function test_RevertWhen_BodyStepOutOfBoundsNamesItsStepInThePath() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo((uint256,uint256)[])");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.TupleFieldOutOfBounds.selector, 2, 2));
        draft.add(arg(0, Path.ALL, 2).eq(uint256(1)));
    }

    function test_RevertWhen_NestedQuantifier() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256[][])");
        bytes memory path = Path.encode(0, Path.ALL, Path.ANY);

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.InvalidNestedLoop.selector, path, 2));
        draft.add(_constraintAt(path));
    }

    function test_RevertWhen_ReservedPathStep() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256[])");
        bytes memory path = Path.encode(0, PF.PATH_MARKER_BASE);

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.UnknownPathStep.selector, path, 1));
        draft.add(_constraintAt(path));
    }

    function test_RevertWhen_MalformedPath() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(Path.MalformedPath.selector);
        draft.add(_constraintAt(hex"000000"));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  INTAKE ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_NoConstraintOperators() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(PolicyBuilder.NoConstraintOperators.selector);
        draft.add(arg(0));
    }

    function test_RevertWhen_ContextPathOutOfBounds() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo()");
        Constraint memory constraint = msgSender().eq(address(1));
        constraint.path = Path.encode(PF.CTX_MAX + 1);

        vm.expectRevert(abi.encodeWithSelector(Operator.UnknownContextProperty.selector, PF.CTX_MAX + 1));
        draft.add(constraint);
    }

    function test_ContextPropertyAtMax() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo()");
        Constraint memory constraint = msgValue().eq(uint256(1));
        constraint.path = Path.encode(PF.CTX_MAX);

        draft = draft.add(constraint);
        assertEq(draft.data.groups[0].length, 1);
    }

    function test_RevertWhen_ContextPathDepthGreaterThanOne() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo()");
        Constraint memory constraint = msgSender().eq(address(1));
        constraint.path = Path.encode(PF.CTX_MSG_SENDER, 0);

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.InvalidContextPath.selector, 2));
        draft.add(constraint);
    }

    function test_RevertWhen_UnknownScope() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");
        Constraint memory constraint = arg(0).eq(uint256(42));
        constraint.scope = PF.SCOPE_LOOP;

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.UnknownScope.selector, PF.SCOPE_LOOP));
        draft.add(constraint);
    }

    function test_RevertWhen_ComparisonDoesNotApplyToTarget() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(PolicyCoder.OperatorTargetMismatch.selector, OpCode.LENGTH_EQ, TypeCode.UINT256)
        );
        draft.add(arg(0).lengthEq(1));
    }

    function test_RevertWhen_ContextComparisonDoesNotApplyToTarget() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(bytes)");
        uint8 opCode = OpCode.GT | (OpCode.SOURCE_CONTEXT << OpCode.SOURCE_SHIFT);

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.OperatorTargetMismatch.selector, opCode, TypeCode.BYTES));
        draft.add(arg(0).gtCtx(PF.CTX_BLOCK_TIMESTAMP));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 OPERAND DOMAIN
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_OperandAboveSignedTargetMaximum() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(int256)");

        uint256 aboveMax = 2 ** 255;
        vm.expectRevert(
            abi.encodeWithSelector(PolicyCoder.OutOfPhysicalBounds.selector, bytes32(aboveMax), TypeCode.INT256)
        );
        draft.add(arg(0).gt(aboveMax));
    }

    function test_RevertWhen_RangeEndpointFoldsIntoDomain() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyCoder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
            )
        );
        draft.add(arg(0).between(int256(-1), int256(5)));
    }

    function test_RevertWhen_SetMemberFoldsIntoDomain() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");
        int256[] memory values = new int256[](2);
        values[0] = 5;
        values[1] = -1;

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyCoder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
            )
        );
        draft.add(arg(0).isIn(values));
    }

    function test_RevertWhen_NegativeOperandOnUnsignedContextProperty() public {
        PolicyDraft memory draft = PolicyBuilder.create("transfer(address,uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyCoder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
            )
        );
        draft.add(msgValue().lt(int256(-1)));
    }

    function test_RevertWhen_OperandFoldsIntoTheElementTypeUnderAQuantifier() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256[])");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyCoder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
            )
        );
        draft.add(arg(0, Path.ALL).lte(int256(-1)));
    }

    function test_RevertWhen_FoldedOperandUnderNegatedOperator() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyCoder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
            )
        );
        draft.add(arg(0).neq(int256(-1)));
    }

    function test_RevertWhen_TwoOperandsFoldAndNamesTheFurthest() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyCoder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max - 4), TypeCode.UINT256
            )
        );
        draft.add(arg(0).lte(int256(-5)).gt(int256(-1)));
    }

    function test_RevertWhen_OperandOutsideTheTargetWidth() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint8)");

        vm.expectRevert(
            abi.encodeWithSelector(PolicyCoder.OutOfPhysicalBounds.selector, bytes32(uint256(256)), TypeCode.UINT8)
        );
        draft.add(arg(0).eq(uint256(256)));
    }

    function test_RevertWhen_MaskWiderThanTheTarget() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint8)");

        vm.expectRevert(
            abi.encodeWithSelector(PolicyCoder.OutOfPhysicalBounds.selector, bytes32(uint256(0x100)), TypeCode.UINT8)
        );
        draft.add(arg(0).bitmaskAll(0x100));
    }

    function test_AllOnesMaskFitsANarrowTarget() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint8)").add(arg(0).bitmaskAll(type(uint256).max));

        draft.build();
    }

    function test_RevertWhen_SetExceedsTheDataLengthAtTheTargetWidth() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");
        Constraint memory constraint = arg(0).isIn(_values(type(uint16).max / 32 + 1));

        vm.expectRevert(PolicyBuilder.SetTooLarge.selector);
        draft.add(constraint);
    }

    function test_SetFillsTheDataLengthAfterDeduplication() public pure {
        uint256[] memory values = _values(type(uint16).max / 32 + 1);
        values[values.length - 1] = 0;

        PolicyBuilder.create("foo(uint256)").add(arg(0).isIn(values)).build();
    }

    function test_RevertWhen_OperatorHoldsNoWholeWord() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint8)").add(arg(0).addOp(OpCode.BITMASK_ALL, hex"01"));

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.InvalidOperatorBytes.selector, 0, 0));
        draft.build();
    }

    /*/////////////////////////////////////////////////////////////////////////
                                     LOOPS
    /////////////////////////////////////////////////////////////////////////*/

    function test_JoinsOneQuantifierOverOneArrayIntoOneLoop() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo((address,uint256)[])")
            .add(arg(0, Path.ANY, 0).eq(address(1)))
            .add(arg(0, Path.ANY, 1).gte(uint256(1000)))
            .add(arg(0, Path.ALL, 1).lte(uint256(5000)));

        assertEq(draft.data.groups[0].length, 2);
        assertEq(draft.data.groups[0][0].quantifier, PF.QUANTIFIER_ANY);
        assertEq(draft.data.groups[0][0].body.length, 2);
        assertEq(draft.data.groups[0][1].quantifier, PF.QUANTIFIER_ALL);
    }
}

contract PolicyBuilderOrTest is Test {
    function test_RevertWhen_EmptyGroup() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.EmptyGroup.selector, 0));
        draft.or();
    }
}

contract PolicyBuilderBuildTest is Test {
    function test_RevertWhen_BlobFailsStorageValidation() public {
        uint8 contextBetween = OpCode.BETWEEN | (OpCode.SOURCE_CONTEXT << OpCode.SOURCE_SHIFT);
        PolicyDraft memory draft =
            PolicyBuilder.create("foo(uint256)").add(arg(0).addOp(contextBetween, abi.encode(PF.CTX_MSG_VALUE)));
        draft.buildUnsafe();

        vm.expectPartialRevert(Policy.InvalidContextOperand.selector);
        draft.build();
    }

    function test_RevertWhen_ValidationReportsIssuesWithEveryIssue() public {
        PolicyDraft memory draft =
            PolicyBuilder.create("foo(address,bool)").add(arg(0).gt(uint256(1))).add(arg(1).bitmaskAll(uint256(1)));
        Issue[] memory issues = draft.validate();
        assertEq(issues.length, 2);
        assertEq(issues[0].code, IssueCode.NUMERIC_OP_ON_NON_NUMERIC);
        assertEq(issues[1].code, IssueCode.BITMASK_ON_INVALID);

        vm.expectRevert(abi.encodeWithSelector(PolicyValidator.ValidationError.selector, issues));
        draft.build();
    }

    function test_OperatorsOnOnePathEncodeAlikeAcrossAdds() public pure {
        bytes memory separate =
            PolicyBuilder.create("foo(uint256)").add(arg(0).gt(uint256(1))).add(arg(0).lt(uint256(9))).build();
        bytes memory joint = PolicyBuilder.create("foo(uint256)").add(arg(0).gt(uint256(1)).lt(uint256(9))).build();

        assertEq(separate, joint);
    }
}

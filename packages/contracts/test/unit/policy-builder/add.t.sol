// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg, msgSender, msgValue } from "src/Constraint.sol";
import { Constraint } from "src/Constraint.sol";
import { Descriptor } from "src/Descriptor.sol";
import { IssueCode } from "src/IssueCode.sol";
import { OpCode } from "src/OpCode.sol";
import { Path } from "src/Path.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";
import { PolicyValidator } from "src/PolicyValidator.sol";
import { TypeCode } from "src/TypeCode.sol";
import { Issue } from "src/ValidationIssue.sol";

import { PolicyBuilderTest } from "test/unit/PolicyBuilder.t.sol";

contract PolicyBuilderAddTest is PolicyBuilderTest {
    /*/////////////////////////////////////////////////////////////////////////
                              CONSTRAINT ADDITION
    /////////////////////////////////////////////////////////////////////////*/

    function test_AppendsConstraintToGroup() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");
        draft = draft.add(arg(0).eq(uint256(42)));

        assertEq(draft.data.groups.length, 1);
        assertEq(draft.data.groups[0].length, 1);
    }

    function test_ContextPathSingleStep() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo()");
        draft = draft.add(msgSender().eq(address(1)));

        assertConstraintAdded(draft, 0);
    }

    function test_CalldataArgIndexInBounds() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("bar(address,uint256)");
        draft = draft.add(arg(1).eq(uint256(1)));

        assertConstraintAdded(draft, 0);
    }

    function test_TupleFieldNavigation() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo((address,uint256))");
        draft = draft.add(arg(0, 1).eq(uint256(42)));
        assertConstraintAdded(draft, 0);
    }

    function test_StaticArrayElement() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(address[3])");
        draft = draft.add(arg(0, 2).eq(address(1)));
        assertConstraintAdded(draft, 0);
    }

    function test_DynamicArrayElement() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(address[])");
        draft = draft.add(arg(0, 5).eq(address(1)));
        assertConstraintAdded(draft, 0);
    }

    function test_QuantifierOnArray() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256[])");
        draft = draft.add(arg(0, Path.ALL).eq(uint256(42)));
        assertConstraintAdded(draft, 0);
    }

    /*/////////////////////////////////////////////////////////////////////////
                               VALIDATION ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_NoConstraintOperators() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(PolicyBuilder.NoConstraintOperators.selector);
        draft.add(arg(0));
    }

    function test_RevertWhen_DuplicatePathInGroup() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");
        draft = draft.add(arg(0).eq(uint256(42)));

        Constraint memory duplicate = arg(0).gt(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(PolicyBuilder.DuplicatePathInGroup.selector, PF.SCOPE_CALLDATA, Path.encode(0))
        );
        draft.add(duplicate);
    }

    function test_RevertWhen_ContextPathOutOfBounds() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo()");

        Constraint memory c = msgSender().eq(address(1));
        c.path = Path.encode(PF.CTX_MAX + 1);

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.UnknownContextProperty.selector, PF.CTX_MAX + 1));
        draft.add(c);
    }

    function test_RevertWhen_ContextPathDepthGreaterThanOne() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo()");

        Constraint memory c = msgSender().eq(address(1));
        c.path = Path.encode(PF.CTX_MSG_SENDER, 0);

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.InvalidContextPath.selector, 2));
        draft.add(c);
    }

    function test_RevertWhen_InvalidScope() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        Constraint memory c = arg(0).eq(uint256(42));
        c.scope = 0x02;

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.InvalidScope.selector, 0x02));
        draft.add(c);
    }

    function test_RevertWhen_ArgIndexOutOfBounds() public {
        PolicyDraft memory draft = PolicyBuilder.create("bar(address,uint256)");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.ParamIndexOutOfBounds.selector, 2, 2));
        draft.add(arg(2).eq(uint256(1)));
    }

    function test_RevertWhen_TupleFieldOutOfBounds() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo((address,uint256))");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.TupleFieldOutOfBounds.selector, 2, 2));
        draft.add(arg(0, 2).eq(uint256(1)));
    }

    function test_RevertWhen_QuantifierOnNonArray_Tuple() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo((address,uint256))");

        vm.expectRevert(
            abi.encodeWithSelector(PolicyBuilder.QuantifierOnNonArray.selector, Path.encode(0, Path.ALL), 1)
        );
        draft.add(arg(0, Path.ALL).eq(uint256(1)));
    }

    function test_RevertWhen_QuantifierOnNonArray_Elementary() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(PolicyBuilder.QuantifierOnNonArray.selector, Path.encode(0, Path.ANY), 1)
        );
        draft.add(arg(0, Path.ANY).eq(uint256(1)));
    }

    function test_RevertWhen_NonCompositeDescent() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.NotComposite.selector, TypeCode.UINT256));
        draft.add(arg(0, 0).eq(uint256(1)));
    }

    function test_RevertWhen_StaticArrayIndexOutOfBounds() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(address[3])");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.StaticArrayIndexOutOfBounds.selector, 3, 3));
        draft.add(arg(0, 3).eq(address(1)));
    }

    function test_RevertWhen_NestedQuantifier() public {
        // uint256[][] — two levels of dynamic arrays.
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256[][])");

        bytes memory path = Path.encode(0, Path.ALL, Path.ANY);
        Constraint memory c = Constraint({
            scope: PF.SCOPE_CALLDATA,
            path: path,
            operators: new bytes[](0),
            leastNegativeOperand: 0,
            greatestOperand: 0,
            hint: ""
        });
        c = c.eq(uint256(1));

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.NestedQuantifier.selector, path, 2));
        draft.add(c);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 OPERAND DOMAIN
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_NegativeOperandOnUnsignedTarget() public {
        PolicyDraft memory draft = PolicyBuilder.create("transfer(address,uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max - 4), TypeCode.UINT256
            )
        );
        draft.add(arg(1).lte(int256(-5)));
    }

    function test_RevertWhen_OperandAboveSignedTargetMaximum() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(int256)");

        uint256 aboveMax = 2 ** 255;
        vm.expectRevert(
            abi.encodeWithSelector(PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(aboveMax), TypeCode.INT256)
        );
        draft.add(arg(0).gt(aboveMax));
    }

    function test_RevertWhen_RangeEndpointFoldsIntoDomain() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
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
                PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
            )
        );
        draft.add(arg(0).isIn(values));
    }

    function test_RevertWhen_NegativeOperandOnUnsignedContextProperty() public {
        PolicyDraft memory draft = PolicyBuilder.create("transfer(address,uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
            )
        );
        draft.add(msgValue().lt(int256(-1)));
    }

    function test_RevertWhen_OperandFoldsIntoTheElementTypeUnderAQuantifier() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256[])");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
            )
        );
        draft.add(arg(0, Path.ALL).lte(int256(-1)));
    }

    function test_NegativeOperandOnSignedTarget() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(int256)");
        draft = draft.add(arg(0).between(int256(-5), int256(5)));

        assertConstraintAdded(draft, 0);
    }

    function test_NearMaximumBoundTheAliasWouldCollideWith() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");
        draft = draft.add(arg(0).lte(type(uint256).max - 4));

        assertConstraintAdded(draft, 0);
    }

    function test_ReadsOneLiteralAgainstTheTarget() public {
        uint256 aboveSignedMax = 2 ** 255;

        PolicyDraft memory unsignedTarget = PolicyBuilder.create("foo(uint256)");
        unsignedTarget = unsignedTarget.add(arg(0).gt(aboveSignedMax));
        assertConstraintAdded(unsignedTarget, 0);

        PolicyDraft memory signedTarget = PolicyBuilder.create("foo(int256)");
        vm.expectRevert(
            abi.encodeWithSelector(PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(aboveSignedMax), TypeCode.INT256)
        );
        signedTarget.add(arg(0).gt(aboveSignedMax));
    }

    function test_RevertWhen_HighLiteralReadsAsSmallNegativeOnNarrowSignedTarget() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(int8)");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.INT8
            )
        );
        draft.add(arg(0).eq(type(uint256).max));
    }

    function test_RevertWhen_FoldedOperandUnderNegatedOperator() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
            )
        );
        draft.add(arg(0).neq(int256(-1)));
    }

    function test_RevertWhen_ExcludedSetMemberFolds() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        int256[] memory values = new int256[](1);
        values[0] = -1;

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max), TypeCode.UINT256
            )
        );
        draft.add(arg(0).notIn(values));
    }

    function test_RevertWhen_OperatorsAreReorderedAfterRecording() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        Constraint memory c = arg(0).lte(int256(-5)).gt(uint256(0));
        (c.operators[0], c.operators[1]) = (c.operators[1], c.operators[0]);

        vm.expectPartialRevert(PolicyBuilder.OutOfPhysicalBounds.selector);
        draft.add(c);
    }

    function test_RevertWhen_FluentOperandFollowsARawOperator() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        bytes[] memory raw = new bytes[](1);
        raw[0] = abi.encodePacked(OpCode.GT, bytes32(0));
        Constraint memory c = Constraint({
            scope: PF.SCOPE_CALLDATA,
            path: Path.encode(0),
            operators: raw,
            leastNegativeOperand: 0,
            greatestOperand: 0,
            hint: ""
        });
        c = c.lte(int256(-5));

        vm.expectPartialRevert(PolicyBuilder.OutOfPhysicalBounds.selector);
        draft.add(c);
    }

    function test_RevertWhen_AnOperatorIsRemovedAfterRecording() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        Constraint memory c = arg(0).lte(int256(-5));
        c.operators = new bytes[](0);
        c = c.lte(type(uint256).max - 4);

        vm.expectPartialRevert(PolicyBuilder.OutOfPhysicalBounds.selector);
        draft.add(c);
    }

    function test_RawOperatorCarriesNoWrittenOperand() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(int256)");
        draft = draft.add(arg(0).addOp(OpCode.EQ, abi.encodePacked(type(uint256).max)));

        assertConstraintAdded(draft, 0);
    }

    function test_RevertWhen_TwoOperandsFoldAndNamesTheFurthest() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyBuilder.OutOfPhysicalBounds.selector, bytes32(type(uint256).max - 4), TypeCode.UINT256
            )
        );
        draft.add(arg(0).gt(int256(-1)).lte(int256(-5)));
    }

    function test_OperandTheTargetCannotEncodeIsLeftToTheValidator() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint8)");
        draft = draft.add(arg(0).eq(uint256(256)));

        Issue[] memory issues = PolicyValidator.validate(draft.data);
        assertEq(issues[0].code, IssueCode.OUT_OF_PHYSICAL_BOUNDS);
    }

    function test_BitmaskOperandIsLeftToTheValidator() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(int256)");
        draft = draft.add(arg(0).bitmaskAll(2 ** 255));

        Issue[] memory issues = PolicyValidator.validate(draft.data);
        assertEq(issues[0].code, IssueCode.BITMASK_ON_INVALID);
    }

    function test_ConstraintCarryingNoRecordIsLeftToTheValidator() public pure {
        bytes[] memory operators = new bytes[](1);
        operators[0] = abi.encodePacked(OpCode.LTE, bytes32(type(uint256).max - 4));
        Constraint memory encoded = Constraint({
            scope: PF.SCOPE_CALLDATA,
            path: Path.encode(0),
            operators: operators,
            leastNegativeOperand: 0,
            greatestOperand: 0,
            hint: ""
        });

        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");
        draft = draft.add(encoded);

        assertConstraintAdded(draft, 0);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg, msgSender } from "src/Constraint.sol";
import { Constraint } from "src/Constraint.sol";
import { Path } from "src/Path.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

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
        assertEq(draft.usedPathHashes.length, 1);
        assertEq(draft.usedPathHashes[0].length, 1);
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
        draft = draft.add(arg(0, Path.ALL_OR_EMPTY).eq(uint256(42)));
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
        c.path = Path.encode(PF.CTX_TX_ORIGIN + 1);

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.InvalidPathNavigation.selector, c.path, 0));
        draft.add(c);
    }

    function test_RevertWhen_ContextPathDepthGreaterThanOne() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo()");

        Constraint memory c = msgSender().eq(address(1));
        c.path = Path.encode(PF.CTX_MSG_SENDER, 0);

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.InvalidPathNavigation.selector, c.path, 0));
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

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.ArgIndexOutOfBounds.selector, 2, 2));
        draft.add(arg(2).eq(uint256(1)));
    }

    function test_RevertWhen_TupleFieldOutOfBounds() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo((address,uint256))");

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.TupleFieldOutOfBounds.selector, 2, 2));
        draft.add(arg(0, 2).eq(uint256(1)));
    }

    function test_RevertWhen_QuantifierOnNonArray_Tuple() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo((address,uint256))");

        vm.expectRevert(
            abi.encodeWithSelector(PolicyBuilder.QuantifierOnNonArray.selector, Path.encode(0, Path.ALL_OR_EMPTY), 1)
        );
        draft.add(arg(0, Path.ALL_OR_EMPTY).eq(uint256(1)));
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

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.InvalidPathNavigation.selector, Path.encode(0, 0), 1));
        draft.add(arg(0, 0).eq(uint256(1)));
    }

    function test_RevertWhen_StaticArrayIndexOutOfBounds() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(address[3])");

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.InvalidPathNavigation.selector, Path.encode(0, 3), 1));
        draft.add(arg(0, 3).eq(address(1)));
    }

    function test_RevertWhen_NestedQuantifier() public {
        // uint256[][] — two levels of dynamic arrays.
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256[][])");

        bytes memory path = Path.encode(0, Path.ALL_OR_EMPTY, Path.ANY);
        Constraint memory c = Constraint({ scope: PF.SCOPE_CALLDATA, path: path, operators: new bytes[](0) });
        c = c.eq(uint256(1));

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.NestedQuantifier.selector, path, 2));
        draft.add(c);
    }
}

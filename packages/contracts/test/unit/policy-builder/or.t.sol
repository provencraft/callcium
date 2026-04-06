// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";

import { PolicyBuilderTest } from "test/unit/PolicyBuilder.t.sol";

contract PolicyBuilderOrTest is PolicyBuilderTest {
    /*/////////////////////////////////////////////////////////////////////////
                                GROUP CREATION
    /////////////////////////////////////////////////////////////////////////*/

    function test_StartsNewGroup() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        draft = draft.add(arg(0).eq(uint256(42)));
        draft = draft.or();

        assertEq(draft.data.groups.length, 2);
        assertEq(draft.data.groups[0].length, 1);
        assertEq(draft.data.groups[1].length, 0);
        assertEq(draft.usedPathHashes[0].length, 1);
        assertEq(draft.usedPathHashes[1].length, 0);
    }

    function test_SubsequentAddGoesToNewGroup() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        draft = draft.add(arg(0).eq(uint256(42)));
        draft = draft.or();
        draft = draft.add(arg(0).gt(uint256(100)));

        assertEq(draft.data.groups.length, 2);
        assertEq(draft.data.groups[0].length, 1);
        assertEq(draft.data.groups[1].length, 1);
    }

    function test_MultipleOrCalls() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        draft = draft.add(arg(0).eq(uint256(1)));
        draft = draft.or();
        draft = draft.add(arg(0).eq(uint256(2)));
        draft = draft.or();
        draft = draft.add(arg(0).eq(uint256(3)));

        assertEq(draft.data.groups.length, 3);
        assertEq(draft.data.groups[0].length, 1);
        assertEq(draft.data.groups[1].length, 1);
        assertEq(draft.data.groups[2].length, 1);
    }

    function test_SamePathAllowedInDifferentGroups() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        draft = draft.add(arg(0).eq(uint256(42)));
        draft = draft.or();
        draft = draft.add(arg(0).eq(uint256(100)));

        assertEq(draft.data.groups.length, 2);
        assertEq(draft.data.groups[0].length, 1);
        assertEq(draft.data.groups[1].length, 1);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  EMPTY GROUPS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_EmptyGroup() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.EmptyGroup.selector, 0));
        draft.or();
    }

    function test_RevertWhen_SecondGroupEmpty() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        draft = draft.add(arg(0).eq(uint256(42)));
        draft = draft.or();

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.EmptyGroup.selector, 1));
        draft.or();
    }
}

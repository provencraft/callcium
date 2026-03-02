// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Constraint, arg } from "src/Constraint.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";
import { PolicyCoder, PolicyData } from "src/PolicyCoder.sol";

import { PolicyBuilderTest } from "test/unit/PolicyBuilder.t.sol";

contract PolicyBuilderBuildTest is PolicyBuilderTest {
    /*/////////////////////////////////////////////////////////////////////////
                                 BUILD OUTPUT
    /////////////////////////////////////////////////////////////////////////*/

    function test_ReturnsCorrectSelector() public pure {
        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();

        assertEq(Policy.selector(policy), bytes4(keccak256("foo(uint256)")));
    }

    function test_FlattensMultipleOperatorsPerConstraint() public pure {
        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gt(uint256(10)).lt(uint256(100)))
            .buildUnsafe();

        uint256 groupStart = Policy.groupAt(policy, 0);
        uint256 ruleCount = Policy.ruleCount(policy, groupStart);
        assertEq(ruleCount, 2);
    }

    function test_FlattensMultipleConstraintsPerGroup() public pure {
        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.create("foo(uint256,address)")
            .add(arg(0).eq(uint256(42)))
            .add(arg(1).eq(address(1)))
            .buildUnsafe();

        uint256 groupStart = Policy.groupAt(policy, 0);
        uint256 ruleCount = Policy.ruleCount(policy, groupStart);
        assertEq(ruleCount, 2);
    }

    function test_FlattensMultipleGroups() public pure {
        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(1)))
            .or()
            .add(arg(0).eq(uint256(2)))
            .buildUnsafe();

        uint256 groupCount = Policy.groupCount(policy);
        assertEq(groupCount, 2);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  EMPTY GROUPS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_EmptyDraft() public {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.EmptyGroup.selector, 0));
        draft.buildUnsafe();
    }

    function test_RevertWhen_LastGroupEmpty() public {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .or();

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.EmptyGroup.selector, 1));
        draft.buildUnsafe();
    }

    function test_RevertWhen_MiddleGroupEmpty() public {
        // Build a draft with 3 groups where the middle one is empty.
        // Group 0: has constraint. Group 1: empty. Group 2: has constraint.
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(1))).or();

        // Manually inject group 2 with a constraint while leaving group 1 empty.
        Constraint[][] memory groups = new Constraint[][](3);
        groups[0] = draft.data.groups[0];
        groups[1] = new Constraint[](0);
        groups[2] = new Constraint[](1);
        groups[2][0] = arg(0).eq(uint256(2));
        draft.data.groups = groups;

        vm.expectRevert(abi.encodeWithSelector(PolicyBuilder.EmptyGroup.selector, 1));
        draft.buildUnsafe();
    }

    /*/////////////////////////////////////////////////////////////////////////
                         SET CANONICALIZATION (HASH STABILITY)
    /////////////////////////////////////////////////////////////////////////*/

    function test_PolicyHash_Uint256Set_PermutationInvariant() public pure {
        uint256[] memory a = new uint256[](5);
        a[0] = 300;
        a[1] = 100;
        a[2] = 200;
        a[3] = 100;
        a[4] = 300;

        uint256[] memory b = new uint256[](5);
        b[0] = 100;
        b[1] = 300;
        b[2] = 100;
        b[3] = 200;
        b[4] = 300;

        bytes memory policyA = PolicyBuilder.create("foo(uint256)").add(arg(0).isIn(a)).buildUnsafe();
        bytes memory policyB = PolicyBuilder.create("foo(uint256)").add(arg(0).isIn(b)).buildUnsafe();

        assertEq(policyA, policyB);
        assertEq(keccak256(policyA), keccak256(policyB));
    }

    function test_PolicyHash_Int256Set_PermutationInvariant() public pure {
        int256[] memory a = new int256[](5);
        a[0] = -1;
        a[1] = 0;
        a[2] = 1;
        a[3] = -1;
        a[4] = 1;

        int256[] memory b = new int256[](5);
        b[0] = 1;
        b[1] = -1;
        b[2] = 0;
        b[3] = 1;
        b[4] = -1;

        bytes memory policyA = PolicyBuilder.create("foo(int256)").add(arg(0).isIn(a)).buildUnsafe();
        bytes memory policyB = PolicyBuilder.create("foo(int256)").add(arg(0).isIn(b)).buildUnsafe();

        assertEq(policyA, policyB);
        assertEq(keccak256(policyA), keccak256(policyB));
    }

    function test_PolicyHash_AddressSet_PermutationInvariant() public pure {
        address[] memory a = new address[](4);
        a[0] = address(0x3);
        a[1] = address(0x1);
        a[2] = address(0x2);
        a[3] = address(0x1);

        address[] memory b = new address[](4);
        b[0] = address(0x2);
        b[1] = address(0x1);
        b[2] = address(0x3);
        b[3] = address(0x1);

        bytes memory policyA = PolicyBuilder.create("foo(address)").add(arg(0).isIn(a)).buildUnsafe();
        bytes memory policyB = PolicyBuilder.create("foo(address)").add(arg(0).isIn(b)).buildUnsafe();

        assertEq(policyA, policyB);
        assertEq(keccak256(policyA), keccak256(policyB));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 SELECTORLESS (createRaw)
    /////////////////////////////////////////////////////////////////////////*/

    function test_CreateRaw_SetsSelectorlessFlag() public pure {
        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.createRaw("uint256")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();

        assertTrue(Policy.isSelectorless(policy));
    }

    function test_CreateRaw_ZeroedSelectorSlot() public pure {
        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.createRaw("uint256")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();

        // Decode and verify selector is bytes4(0).
        PolicyData memory data = PolicyCoder.decode(policy);
        assertEq(data.selector, bytes4(0));
    }

    function test_CreateRaw_RoundTrip() public pure {
        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.createRaw("uint256,address")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);
        assertTrue(data.isSelectorless);
        assertEq(data.selector, bytes4(0));

        // Re-encode and compare.
        bytes memory reencoded = PolicyCoder.encode(data);
        assertEq(keccak256(policy), keccak256(reencoded));
    }

    function test_CreateRaw_MultipleTypes() public pure {
        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.createRaw("uint256,address,bool")
            .add(arg(0).eq(uint256(1)))
            .buildUnsafe();

        assertTrue(Policy.isSelectorless(policy));
    }

    function test_PolicyHash_Bytes32Set_PermutationInvariant() public pure {
        bytes32[] memory a = new bytes32[](4);
        a[0] = bytes32(uint256(0x0300));
        a[1] = bytes32(uint256(0x0100));
        a[2] = bytes32(uint256(0x0200));
        a[3] = bytes32(uint256(0x0100));

        bytes32[] memory b = new bytes32[](4);
        b[0] = bytes32(uint256(0x0200));
        b[1] = bytes32(uint256(0x0100));
        b[2] = bytes32(uint256(0x0300));
        b[3] = bytes32(uint256(0x0100));

        bytes memory policyA = PolicyBuilder.create("foo(bytes32)").add(arg(0).isIn(a)).buildUnsafe();
        bytes memory policyB = PolicyBuilder.create("foo(bytes32)").add(arg(0).isIn(b)).buildUnsafe();

        assertEq(policyA, policyB);
        assertEq(keccak256(policyA), keccak256(policyB));
    }
}

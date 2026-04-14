// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Be16 } from "src/Be16.sol";
import {
    Constraint,
    arg,
    blockNumber,
    blockTimestamp,
    chainId,
    msgSender,
    msgValue,
    txOrigin
} from "src/Constraint.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { OpCode } from "src/OpCode.sol";
import { Path } from "src/Path.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyCoder, PolicyData } from "src/PolicyCoder.sol";
import { PolicyEnforcer } from "src/PolicyEnforcer.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

import { PolicyEnforcerTest } from "../PolicyEnforcer.t.sol";

/// @dev Tests for value and length operators (eq, gt, lt, between, bitmask, length, etc.)
// forgefmt: disable-next-item
contract EnforceOperatorTest is PolicyEnforcerTest {
    /// @dev Returns the default 4-element set [10, 20, 30, 40].
    function _defaultSet() private pure returns (uint256[] memory set) {
        set = new uint256[](4);
        set[0] = 10;
        set[1] = 20;
        set[2] = 30;
        set[3] = 40;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  VALUE OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_Eq() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_Gt() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gt(uint256(40)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_Lt() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).lt(uint256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_Gte_WhenGreater() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gte(uint256(40)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_Gte_WhenEqual() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gte(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_Lte_WhenLesser() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).lte(uint256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_Lte_WhenEqual() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).lte(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_Between_InRange() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).between(uint256(40), uint256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(45));
        harness.enforce(policy, callData);
    }

    function test_Between_AtLowerBound() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).between(uint256(40), uint256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(40));
        harness.enforce(policy, callData);
    }

    function test_Between_AtUpperBound() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).between(uint256(40), uint256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(50));
        harness.enforce(policy, callData);
    }

    function test_In_WhenValueInSet() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).isIn(_defaultSet()))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(30));
        harness.enforce(policy, callData);
    }

    function test_In_FirstElement() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).isIn(_defaultSet()))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(10));
        harness.enforce(policy, callData);
    }

    function test_In_LastElement() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).isIn(_defaultSet()))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(40));
        harness.enforce(policy, callData);
    }

    function test_In_With2Elements() public view {
        uint256[] memory set = new uint256[](2);
        set[0] = 10;
        set[1] = 20;

        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).isIn(set))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(10));
        harness.enforce(policy, callData);
    }

    function test_In_With4Elements() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).isIn(_defaultSet()))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(40));
        harness.enforce(policy, callData);
    }

    function test_In_With8Elements() public view {
        uint256[] memory set = new uint256[](8);
        for (uint256 i; i < 8; ++i) {
            set[i] = (i + 1) * 10;
        }

        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).isIn(set))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(80));
        harness.enforce(policy, callData);
    }

    function test_BitmaskAll_AllBitsSet() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskAll(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0xFF));
        harness.enforce(policy, callData);
    }

    function test_BitmaskAll_ExactMask() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskAll(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x0F));
        harness.enforce(policy, callData);
    }

    function test_BitmaskAny_AnyBitSet() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskAny(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x01));
        harness.enforce(policy, callData);
    }

    function test_BitmaskAny_SingleBit() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskAny(0x08))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x08));
        harness.enforce(policy, callData);
    }

    function test_BitmaskNone_NoBitsSet() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskNone(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0xF0));
        harness.enforce(policy, callData);
    }

    function test_BitmaskNone_DisjointBits() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskNone(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x10));
        harness.enforce(policy, callData);
    }

    function test_LengthEq_DynamicArray() public view {
        uint256[] memory arr = _uintArray(10);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthEq(10))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_LengthEq_Bytes() public view {
        bytes memory data = new bytes(10);
        bytes memory policy = PolicyBuilder.create("foo(bytes)")
            .add(arg(0).lengthEq(10))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(bytes)", data);
        harness.enforce(policy, callData);
    }

    function test_LengthGt() public view {
        uint256[] memory arr = _uintArray(10);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthGt(5))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_LengthLt() public view {
        uint256[] memory arr = _uintArray(5);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthLt(10))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_LengthGte_WhenEqual() public view {
        uint256[] memory arr = _uintArray(10);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthGte(10))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_LengthGte_WhenGreater() public view {
        uint256[] memory arr = _uintArray(15);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthGte(10))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_LengthLte_WhenEqual() public view {
        uint256[] memory arr = _uintArray(10);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthLte(10))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_LengthLte_WhenLesser() public view {
        uint256[] memory arr = _uintArray(5);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthLte(10))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_LengthBetween_InRange() public view {
        uint256[] memory arr = _uintArray(15);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthBetween(10, 20))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_LengthBetween_AtBounds() public view {
        uint256[] memory arr = _uintArray(10);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthBetween(10, 20))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_NotFlag_NegatesEq() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).neq(uint256(100)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_NotFlag_NegatesIn() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).notIn(_defaultSet()))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(100));
        harness.enforce(policy, callData);
    }

    // Signed integer tests.
    function test_Lt_SignedNegativeLessThanPositive() public view {
        bytes memory policy = PolicyBuilder.create("foo(int256)")
            .add(arg(0).lt(int256(1)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(-1));
        harness.enforce(policy, callData);
    }

    function test_Gt_SignedLessNegativeGreaterThanMoreNegative() public view {
        bytes memory policy = PolicyBuilder.create("foo(int256)")
            .add(arg(0).gt(int256(-200)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(-100));
        harness.enforce(policy, callData);
    }

    function test_Gte_SignedNegativeEqual() public view {
        bytes memory policy = PolicyBuilder.create("foo(int256)")
            .add(arg(0).gte(int256(-42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(-42));
        harness.enforce(policy, callData);
    }

    function test_Lte_SignedNegativeEqual() public view {
        bytes memory policy = PolicyBuilder.create("foo(int256)")
            .add(arg(0).lte(int256(-42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(-42));
        harness.enforce(policy, callData);
    }

    function test_Between_SignedNegativeRange() public view {
        bytes memory policy = PolicyBuilder.create("foo(int256)")
            .add(arg(0).between(int256(-100), int256(-50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(-75));
        harness.enforce(policy, callData);
    }

    function test_Between_SignedCrossZeroRange() public view {
        bytes memory policy = PolicyBuilder.create("foo(int256)")
            .add(arg(0).between(int256(-50), int256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(0));
        harness.enforce(policy, callData);
    }

    /*/////////////////////////////////////////////////////////////////////////
                               OPERATOR REJECTIONS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_Eq_NotEqual() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(100));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_Gt_NotGreater() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gt(uint256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_Gt_Equal() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gt(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_Lt_NotLesser() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).lt(uint256(30)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_Lt_Equal() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).lt(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_Gte_Lesser() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gte(uint256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_Lte_Greater() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).lte(uint256(30)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_Between_BelowRange() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).between(uint256(40), uint256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(30));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_Between_AboveRange() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).between(uint256(40), uint256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(60));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_In_ValueNotInSet() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).isIn(_defaultSet()))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(25));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_BitmaskAll_BitsMissing() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskAll(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x07));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_BitmaskAny_NoBitsSet() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskAny(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0xF0));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_BitmaskNone_AnyBitSet() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskNone(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x01));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_LengthEq_LengthDiffers() public {
        uint256[] memory arr = _uintArray(5);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthEq(10))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_LengthGt_Equal() public {
        uint256[] memory arr = _uintArray(10);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthGt(10))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_LengthLt_Equal() public {
        uint256[] memory arr = _uintArray(10);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthLt(10))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_LengthBetween_OutOfRange() public {
        uint256[] memory arr = _uintArray(5);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthBetween(10, 20))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_NotFlag_NegatesEq_Equal() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).neq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_NotFlag_NegatesIn_InSet() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).notIn(_defaultSet()))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(30));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }
}

/// @dev Tests for context constraints (msg.sender, msg.value, block.*, etc.)
// forgefmt: disable-next-item
contract EnforceContextTest is PolicyEnforcerTest {
    /*/////////////////////////////////////////////////////////////////////////
                                CONTEXT PROPERTIES
    /////////////////////////////////////////////////////////////////////////*/

    function test_MsgSender() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgSender().eq(address(this)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_MsgValue() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgValue().eq(uint256(0)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_BlockTimestamp() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(blockTimestamp().gt(uint256(0)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_BlockNumber() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(blockNumber().gte(uint256(0)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_ChainId() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(chainId().gt(uint256(0)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_TxOrigin() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(txOrigin().eq(tx.origin))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  CONTEXT ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_MsgSender_Different() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgSender().eq(address(1)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_MsgValue_Different() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgValue().eq(uint256(1 ether)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_TxOrigin_Different() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(txOrigin().eq(address(1)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_UnknownContextProperty() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgSender().eq(address(1)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        uint256 contextPropertyOffset = 18 + Policy.descriptorLength(policy);
        Be16.write(policy, contextPropertyOffset, 0xFFFF);

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.UnknownContextProperty.selector, 0xFFFF));
        harness.enforce(policy, callData);
    }
}

/// @dev Tests for path navigation (depth, structs, arrays)
// forgefmt: disable-next-item
contract EnforcePathTest is PolicyEnforcerTest {
    function test_Depth1_Elementary() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_Depth2_StructField() public view {
        bytes memory policy = PolicyBuilder.create("foo((address,uint256))")
            .add(arg(0, 1).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = _encodeStruct2(address(1), 42);
        harness.enforce(policy, callData);
    }

    function test_Depth2_ArrayElement() public view {
        uint256[] memory arr = _uintArray(10);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, 5).eq(uint256(6)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_Depth3_NestedStruct() public view {
        bytes memory policy = PolicyBuilder.create("foo(((address,uint256),uint256))")
            .add(arg(0, 0, 1).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = _encodeNestedStruct3(address(1), 42, 100);
        harness.enforce(policy, callData);
    }
}

/// @dev Tests for group semantics (OR between groups, AND within rules)
// forgefmt: disable-next-item
contract EnforceGroupTest is PolicyEnforcerTest {
    /*/////////////////////////////////////////////////////////////////////////
                                 GROUP SEMANTICS
    /////////////////////////////////////////////////////////////////////////*/

    function test_SingleGroup() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_MultipleGroups_FirstPasses() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .or()
            .add(arg(0).eq(uint256(100)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_MultipleGroups_LastPasses() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(100)))
            .or()
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_MultipleRules_AllPass() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gte(uint256(40)).lte(uint256(50)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   GROUP ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_CalldataTooShort() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = hex"010203";

        vm.expectRevert(PolicyEnforcer.MissingSelector.selector);
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_SingleGroupFails() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(100)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_MultipleGroupsAllFail() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(100)))
            .or()
            .add(arg(0).eq(uint256(200)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 1, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_MultipleRules_FirstFails() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gte(uint256(50)).lte(uint256(100)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_MultipleRules_LastFails() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gte(uint256(40)).lte(uint256(41)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 1));
        harness.enforce(policy, callData);
    }
}

/// @dev Tests for array quantifiers (ALL, ANY, ALL_OR_EMPTY)
// forgefmt: disable-next-item
contract EnforceQuantifierTest is PolicyEnforcerTest {
    /*/////////////////////////////////////////////////////////////////////////
                              QUANTIFIER SEMANTICS
    /////////////////////////////////////////////////////////////////////////*/

    function test_AllOrEmpty_WhenAllElementsMatch() public view {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL_OR_EMPTY).lte(uint256(3)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_AllOrEmpty_OnEmptyArray() public view {
        uint256[] memory arr = new uint256[](0);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL_OR_EMPTY).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_All_WhenAllElementsMatch() public view {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).lte(uint256(3)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_Any_WhenOneElementMatches() public view {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ANY).eq(uint256(2)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_AllOrEmptyWithSuffix() public view {
        TwoUints[] memory arr = new TwoUints[](2);
        arr[0] = TwoUints({ a: 1, b: 10 });
        arr[1] = TwoUints({ a: 2, b: 20 });
        bytes memory policy = PolicyBuilder.create("foo((uint256,uint256)[])")
            .add(arg(0, Path.ALL_OR_EMPTY, 1).lte(uint256(20)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo((uint256,uint256)[])", arr);
        harness.enforce(policy, callData);
    }

    function test_AnyWithSuffix() public view {
        TwoUints[] memory arr = new TwoUints[](2);
        arr[0] = TwoUints({ a: 1, b: 10 });
        arr[1] = TwoUints({ a: 2, b: 20 });
        bytes memory policy = PolicyBuilder.create("foo((uint256,uint256)[])")
            .add(arg(0, Path.ANY, 1).eq(uint256(20)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo((uint256,uint256)[])", arr);
        harness.enforce(policy, callData);
    }

    function test_QuantifierOnStaticArray() public view {
        uint256[3] memory arr = [uint256(1), 2, 3];
        bytes memory policy = PolicyBuilder.create("foo(uint256[3])")
            .add(arg(0, Path.ALL).lte(uint256(3)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[3])", arr);
        harness.enforce(policy, callData);
    }

    function test_QuantifierBoundary_MaxArrayLength() public view {
        uint256[] memory arr = _uintArray(256);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).lte(uint256(256)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    function test_QuantifierWithOrGroups() public view {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).gt(uint256(10)))
            .or()
            .add(arg(0, Path.ANY).eq(uint256(2)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        harness.enforce(policy, callData);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                QUANTIFIER ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_AllOrEmpty_OneElementFails() public {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL_OR_EMPTY).lte(uint256(2)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_EmptyArray() public {
        uint256[] memory arr = new uint256[](0);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_Any_NoElementPasses() public {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ANY).eq(uint256(4)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_Any_EmptyArray() public {
        uint256[] memory arr = new uint256[](0);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ANY).eq(uint256(42)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_AllWithSuffix_ElementFails() public {
        TwoUints[] memory arr = new TwoUints[](2);
        arr[0] = TwoUints({ a: 1, b: 10 });
        arr[1] = TwoUints({ a: 2, b: 30 });
        bytes memory policy = PolicyBuilder.create("foo((uint256,uint256)[])")
            .add(arg(0, Path.ALL, 1).lte(uint256(20)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo((uint256,uint256)[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_AnyWithSuffix_NoElementMatches() public {
        TwoUints[] memory arr = new TwoUints[](2);
        arr[0] = TwoUints({ a: 1, b: 10 });
        arr[1] = TwoUints({ a: 2, b: 20 });
        bytes memory policy = PolicyBuilder.create("foo((uint256,uint256)[])")
            .add(arg(0, Path.ANY, 1).eq(uint256(30)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo((uint256,uint256)[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_QuantifierLimitExceeded() public {
        uint256[] memory arr = _uintArray(257);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).lte(uint256(257)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.QuantifierLimitExceeded.selector, 257, 256));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_NestedQuantifiers() public {
        uint256[][] memory arr = new uint256[][](2);
        arr[0] = _uintArray(3);
        arr[1] = _uintArray(2);

        // Build a valid single-quantifier policy, then tamper path to create nested quantifiers.
        // arg(0, 0, Path.ANY) = concrete outer index, quantifier on inner array.
        bytes memory policy = PolicyBuilder.create("foo(uint256[][])")
            .add(arg(0, 0, Path.ANY).eq(uint256(1)))
            .buildUnsafe();

        // Tamper path step 1 (the concrete `0`) to ALL_OR_EMPTY, creating two quantifiers.
        uint16 descLen = Be16.readUnchecked(policy, PF.POLICY_DESC_LENGTH_OFFSET);
        uint256 ruleOffset = PF.POLICY_HEADER_PREFIX + descLen + PF.POLICY_GROUP_COUNT_SIZE + PF.GROUP_HEADER_SIZE;
        uint256 pathStep1Offset = ruleOffset + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE;
        Be16.write(policy, pathStep1Offset, Path.ALL_OR_EMPTY);

        bytes memory callData = abi.encodeWithSignature("foo(uint256[][])", arr);
        vm.expectRevert(PolicyEnforcer.NestedQuantifiersUnsupported.selector);
        harness.enforce(policy, callData);
    }
}

/// @dev Fuzz tests for policy enforcement
// forgefmt: disable-next-item
contract EnforceFuzzTest is PolicyEnforcerTest {
    function testFuzz_Eq(uint256 expected, uint256 actual) public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(expected))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", actual);

        assertEq(harness.check(policy, callData), expected == actual);
    }

    function testFuzz_Gt(uint256 threshold, uint256 value) public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gt(threshold))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", value);

        assertEq(harness.check(policy, callData), value > threshold);
    }

    function testFuzz_Lt(uint256 threshold, uint256 value) public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).lt(threshold))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", value);

        assertEq(harness.check(policy, callData), value < threshold);
    }

    function testFuzz_Between(uint256 lower, uint256 upper, uint256 value) public view {
        lower = bound(lower, 0, type(uint128).max);
        upper = bound(upper, lower, type(uint256).max);

        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).between(lower, upper))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", value);

        assertEq(harness.check(policy, callData), value >= lower && value <= upper);
    }

    function testFuzz_BitmaskAll(uint256 mask, uint256 value) public view {
        vm.assume(mask != 0);

        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskAll(mask))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", value);

        assertEq(harness.check(policy, callData), (value & mask) == mask);
    }

    function testFuzz_BitmaskAny(uint256 mask, uint256 value) public view {
        vm.assume(mask != 0);

        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskAny(mask))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", value);

        assertEq(harness.check(policy, callData), (value & mask) != 0);
    }

    function testFuzz_BitmaskNone(uint256 mask, uint256 value) public view {
        vm.assume(mask != 0);

        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).bitmaskNone(mask))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", value);

        assertEq(harness.check(policy, callData), (value & mask) == 0);
    }

    function testFuzz_AddressEq(address expected, address actual) public view {
        bytes memory policy = PolicyBuilder.create("foo(address)")
            .add(arg(0).eq(expected))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(address)", actual);

        assertEq(harness.check(policy, callData), expected == actual);
    }

    function testFuzz_Bytes32Eq(bytes32 expected, bytes32 actual) public view {
        bytes memory policy = PolicyBuilder.create("foo(bytes32)")
            .add(arg(0).eq(expected))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(bytes32)", actual);

        assertEq(harness.check(policy, callData), expected == actual);
    }

    function testFuzz_AllOrEmpty_Semantics(uint8 length, uint256 threshold) public view {
        length = uint8(bound(length, 0, 50));
        threshold = bound(threshold, 0, type(uint128).max);

        uint256[] memory arr = _uintArray(length);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL_OR_EMPTY).lte(threshold))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);

        bool expected = length == 0 || length <= threshold;
        assertEq(harness.check(policy, callData), expected);
    }

    function testFuzz_All_Semantics(uint8 length, uint256 threshold) public view {
        length = uint8(bound(length, 0, 50));
        threshold = bound(threshold, 0, type(uint128).max);

        uint256[] memory arr = _uintArray(length);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).lte(threshold))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);

        bool expected = length > 0 && length <= threshold;
        assertEq(harness.check(policy, callData), expected);
    }

    function testFuzz_Any_Semantics(uint8 length, uint256 target) public view {
        length = uint8(bound(length, 1, 50));
        target = bound(target, 1, type(uint128).max);

        uint256[] memory arr = _uintArray(length);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ANY).eq(target))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);

        bool expected = target >= 1 && target <= length;
        assertEq(harness.check(policy, callData), expected);
    }
}

/// @dev Tests for selectorless policy enforcement.
contract EnforceSelectorlessTest is PolicyEnforcerTest {
    /// @dev Builds a selectorless policy: single uint256 arg, eq(42).
    function _selectorlessPolicy() internal pure returns (bytes memory) {
        PolicyData memory data;
        data.isSelectorless = true;
        data.selector = bytes4(0);
        data.descriptor = DescriptorBuilder.fromTypes("uint256");
        data.groups = new Constraint[][](1);
        data.groups[0] = new Constraint[](1);
        bytes[] memory operators = new bytes[](1);
        operators[0] = abi.encodePacked(OpCode.EQ, bytes32(uint256(42)));
        data.groups[0][0] = Constraint({ scope: PF.SCOPE_CALLDATA, path: hex"0000", operators: operators });
        return PolicyCoder.encode(data);
    }

    /*/////////////////////////////////////////////////////////////////////////
                           SELECTORLESS ENFORCEMENT
    /////////////////////////////////////////////////////////////////////////*/

    function test_SelectorlessEnforce_PassesWithRawAbi() public view {
        bytes memory policy = _selectorlessPolicy();
        // Raw ABI: just the uint256 value, no selector prefix.
        bytes memory callData = abi.encode(uint256(42));
        harness.enforce(policy, callData);
    }

    function test_SelectorlessCheck_ReturnsTrueWithRawAbi() public view {
        bytes memory policy = _selectorlessPolicy();
        bytes memory callData = abi.encode(uint256(42));
        assertTrue(harness.check(policy, callData));
    }

    function test_SelectorlessEnforce_RejectsWrongValue() public {
        bytes memory policy = _selectorlessPolicy();
        bytes memory callData = abi.encode(uint256(99));
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_SelectorlessCheck_ReturnsFalseForWrongValue() public view {
        bytes memory policy = _selectorlessPolicy();
        bytes memory callData = abi.encode(uint256(99));
        assertFalse(harness.check(policy, callData));
    }
}

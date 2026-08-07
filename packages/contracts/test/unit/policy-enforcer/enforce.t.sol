// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Be16 } from "src/Be16.sol";
import { CalldataReader } from "src/CalldataReader.sol";
import {
    Constraint,
    arg,
    baseFee,
    blockNumber,
    blockTimestamp,
    chainId,
    gasPrice,
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
import { TypeCode } from "src/TypeCode.sol";

import { LibBytes } from "solady/utils/LibBytes.sol";

import { PolicyEnforcerTest } from "../PolicyEnforcer.t.sol";

/// @dev Tests for value and length operators (eq, gt, lt, between, bitmask, length, etc.)
// forgefmt: disable-next-item
contract EnforceOperatorTest is PolicyEnforcerTest {
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

    /// @dev A value equal to the 32-byte policy word immediately preceding the operand
    /// payload, and strictly below the set minimum, is not a member of the set and must be
    /// rejected. The set has 8 elements so membership resolves via the binary-search path.
    function test_In_HeaderWordBelowMinIsNotMember() public view {
        // The 8 largest possible values, so the small header word is trivially below the set.
        uint256 setMin = type(uint256).max - 7;
        uint256[] memory set = new uint256[](8);
        for (uint256 i; i < 8; ++i) {
            set[i] = setMin + i;
        }

        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).isIn(set))
            .buildUnsafe();

        // At mid == 0 the search reads the word just before the operand payload, not a set
        // element. Operands begin at dataOffset, so that word is the one ending at dataOffset.
        // `dataOffset - 32` underflows when dataOffset < 32, but the wrap cancels in load's
        // pointer addition (mod 2^256), so it still resolves to that word.
        uint256 ruleOffset = Policy.ruleAt(policy, Policy.groupAt(policy, 0), 0);
        (uint256 dataOffset,) = Policy.dataView(policy, ruleOffset);
        uint256 headerWord;
        unchecked {
            headerWord = uint256(LibBytes.load(policy, dataOffset - 32));
        }

        assertLt(headerWord, setMin, "header word must be below the set minimum");

        bytes memory callData = abi.encodeWithSignature("foo(uint256)", headerWord);
        assertFalse(harness.check(policy, callData), "header word wrongly reported as a set member");
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

    function test_RevertWhen_ArrayLengthInflated() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthGte(10))
            .buildUnsafe();
        // Length word claims 10 elements while only 2 element words follow; the inflated
        // count must revert instead of satisfying the length constraint.
        bytes memory callData = abi.encodePacked(
            bytes4(keccak256("foo(uint256[])")), uint256(0x20), uint256(10), uint256(1), uint256(2)
        );

        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
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

    function test_RevertWhen_ValueOpOnDynamicTarget() public {
        bytes memory policy = PolicyBuilder.create("foo(bytes)").add(arg(0).eq(uint256(0))).buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(bytes)", bytes(hex"1122"));

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NotScalar.selector, TypeCode.BYTES));
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

    function test_BaseFee() public {
        vm.fee(10 gwei);
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(baseFee().lte(uint256(10 gwei)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        harness.enforce(policy, callData);
    }

    function test_GasPrice() public {
        vm.txGasPrice(20 gwei);
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(gasPrice().lt(uint256(30 gwei)))
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

    function test_RevertWhen_BaseFee_TooHigh() public {
        vm.fee(50 gwei);
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(baseFee().lte(uint256(10 gwei)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_GasPrice_TooHigh() public {
        vm.txGasPrice(40 gwei);
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(gasPrice().lt(uint256(30 gwei)))
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

    function test_FieldOfDynamicTuple() public view {
        bytes memory policy = PolicyBuilder.create("foo((address,uint256,bytes))")
            .add(arg(0, 1).eq(uint256(42)))
            .buildUnsafe();
        bytes memory tupleBody = abi.encode(address(1), uint256(42), bytes("payload"));
        harness.enforce(policy, _encodeDynTupleArg("foo((address,uint256,bytes))", tupleBody));
    }

    function test_FieldPastADynamicSibling() public view {
        // The bytes field ahead of the target occupies one offset word in the tuple head.
        bytes memory policy = PolicyBuilder.create("foo((bytes,uint256))")
            .add(arg(0, 1).eq(uint256(42)))
            .buildUnsafe();
        bytes memory tupleBody = abi.encode(bytes("payload"), uint256(42));
        harness.enforce(policy, _encodeDynTupleArg("foo((bytes,uint256))", tupleBody));
    }

    function test_NestedDynamicTuples() public view {
        bytes memory policy = PolicyBuilder.create("foo(((bytes,uint256),uint256))")
            .add(arg(0, 0, 1).eq(uint256(42)))
            .buildUnsafe();
        bytes memory inner = abi.encode(bytes("payload"), uint256(42));
        bytes memory tupleBody = abi.encodePacked(uint256(0x40), uint256(7), inner);
        harness.enforce(policy, _encodeDynTupleArg("foo(((bytes,uint256),uint256))", tupleBody));
    }

    function test_ConsecutiveArrayCrossings() public view {
        uint256[][] memory outer = new uint256[][](2);
        outer[0] = _uintArray(1);
        outer[1] = _uintArray(4); // [1, 2, 3, 4]
        bytes memory policy = PolicyBuilder.create("foo(uint256[][])")
            .add(arg(0, 1, 2).eq(uint256(3)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(uint256[][])", outer));
    }

    function test_ElementOfDynamicElementArray() public view {
        bytes[] memory arr = new bytes[](2);
        arr[0] = bytes("a");
        arr[1] = bytes("four");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, 1).lengthEq(4))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(bytes[])", arr));
    }

    function test_RevertWhen_ElementIndexBeyondArrayLength() public {
        uint256[] memory arr = _uintArray(2);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, 5).eq(uint256(6)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(CalldataReader.ArrayIndexOutOfBounds.selector, 5, 2));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_OffsetWordWouldWrap() public {
        // An offset word near the top of the range must be rejected, never folded around it.
        bytes memory policy = PolicyBuilder.create("foo(bytes)").add(arg(0).lengthEq(1)).buildUnsafe();
        bytes memory callData = abi.encodePacked(bytes4(keccak256("foo(bytes)")), type(uint256).max, uint256(1));
        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_ElementOffsetWordWouldWrap() public {
        bytes memory policy = PolicyBuilder.create("foo(bytes[])").add(arg(0, 0).lengthEq(1)).buildUnsafe();
        // Element count of one, then an element offset word at the top of the range.
        bytes memory callData = abi.encodePacked(
            bytes4(keccak256("foo(bytes[])")), uint256(0x20), uint256(1), type(uint256).max
        );
        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_BytesLengthOverrunsCalldata() public {
        // The declared byte length must be backed by calldata before the operator sees it.
        bytes memory policy = PolicyBuilder.create("foo(bytes)").add(arg(0).lengthEq(64)).buildUnsafe();
        bytes memory callData =
            abi.encodePacked(bytes4(keccak256("foo(bytes)")), uint256(0x20), uint256(64), uint256(0));
        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
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

/// @dev Tests for array quantifiers (ALL, ANY)
// forgefmt: disable-next-item
contract EnforceQuantifierTest is PolicyEnforcerTest {
    /*/////////////////////////////////////////////////////////////////////////
                              QUANTIFIER SEMANTICS
    /////////////////////////////////////////////////////////////////////////*/

    function test_All_OnEmptyArray_VacuouslyPasses() public view {
        uint256[] memory arr = new uint256[](0);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).eq(uint256(42)))
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

    function test_All_OnStaticArray_WhenAllElementsMatch() public view {
        // build() (not buildUnsafe) proves the validator accepts static-array quantifiers.
        bytes memory policy = PolicyBuilder.create("foo(uint256[3])")
            .add(arg(0, Path.ALL).lte(uint256(3)))
            .build();
        uint256[3] memory arr = [uint256(1), 2, 3];
        bytes memory callData = abi.encodeWithSignature("foo(uint256[3])", arr);
        harness.enforce(policy, callData);
    }

    function test_All_OnStaticArray_WhenOneElementViolates() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256[3])")
            .add(arg(0, Path.ALL).lte(uint256(3)))
            .build();
        uint256[3] memory arr = [uint256(1), 2, 4];
        bytes memory callData = abi.encodeWithSignature("foo(uint256[3])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_Any_OnStaticArray_WhenOneElementMatches() public view {
        bytes memory policy = PolicyBuilder.create("foo(address[2])")
            .add(arg(0, Path.ANY).eq(address(1)))
            .build();
        address[2] memory arr = [address(9), address(1)];
        bytes memory callData = abi.encodeWithSignature("foo(address[2])", arr);
        harness.enforce(policy, callData);
    }

    function test_AllWithSuffix() public view {
        TwoUints[] memory arr = new TwoUints[](2);
        arr[0] = TwoUints({ a: 1, b: 10 });
        arr[1] = TwoUints({ a: 2, b: 20 });
        bytes memory policy = PolicyBuilder.create("foo((uint256,uint256)[])")
            .add(arg(0, Path.ALL, 1).lte(uint256(20)))
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

    function test_All_OverDynamicElements() public view {
        bytes[] memory arr = new bytes[](3);
        arr[0] = bytes("aa");
        arr[1] = bytes("bb");
        arr[2] = bytes("cc");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ALL).lengthEq(2))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(bytes[])", arr));
    }

    function test_RevertWhen_All_OverDynamicElements_OneElementFails() public {
        bytes[] memory arr = new bytes[](3);
        arr[0] = bytes("aa");
        arr[1] = bytes("bbb");
        arr[2] = bytes("cc");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ALL).lengthEq(2))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(bytes[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_All_OverDynamicElementsWithSuffix() public view {
        UintWithBytes[] memory arr = new UintWithBytes[](2);
        arr[0] = UintWithBytes({ value: 1, payload: bytes("a") });
        arr[1] = UintWithBytes({ value: 2, payload: bytes("bb") });
        bytes memory policy = PolicyBuilder.create("foo((uint256,bytes)[])")
            .add(arg(0, Path.ALL, 0).lte(uint256(2)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo((uint256,bytes)[])", arr));
    }

    function test_Any_OverDynamicElements() public view {
        bytes[] memory arr = new bytes[](2);
        arr[0] = bytes("a");
        arr[1] = bytes("bbbb");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ANY).lengthEq(4))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(bytes[])", arr));
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
                           QUANTIFIED VALUE OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_All_Lt() public view {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).lt(uint256(4)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(uint256[])", arr));
    }

    function test_All_Gte() public view {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).gte(uint256(1)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(uint256[])", arr));
    }

    function test_All_Between() public view {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).between(uint256(1), uint256(3)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(uint256[])", arr));
    }

    function test_All_In() public view {
        uint256[] memory arr = new uint256[](2);
        arr[0] = 10;
        arr[1] = 30;
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).isIn(_defaultSet()))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(uint256[])", arr));
    }

    function test_All_BitmaskAll() public view {
        uint256[] memory arr = new uint256[](2);
        arr[0] = 0x0F;
        arr[1] = 0xFF;
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).bitmaskAll(0x0F))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(uint256[])", arr));
    }

    function test_All_BitmaskAny() public view {
        uint256[] memory arr = new uint256[](2);
        arr[0] = 0x01;
        arr[1] = 0x08;
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).bitmaskAny(0x0F))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(uint256[])", arr));
    }

    function test_All_BitmaskNone() public view {
        uint256[] memory arr = new uint256[](2);
        arr[0] = 0xF0;
        arr[1] = 0x10;
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).bitmaskNone(0x0F))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(uint256[])", arr));
    }

    function test_All_NotFlag_NegatesEq() public view {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).neq(uint256(100)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(uint256[])", arr));
    }

    function test_All_NotFlag_NegatesIn() public view {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).notIn(_defaultSet()))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(uint256[])", arr));
    }

    /*/////////////////////////////////////////////////////////////////////////
                           QUANTIFIED LENGTH OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_All_LengthLt() public view {
        bytes[] memory arr = new bytes[](2);
        arr[0] = bytes("a");
        arr[1] = bytes("bb");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ALL).lengthLt(3))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(bytes[])", arr));
    }

    function test_All_LengthLte() public view {
        bytes[] memory arr = new bytes[](2);
        arr[0] = bytes("a");
        arr[1] = bytes("bb");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ALL).lengthLte(2))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(bytes[])", arr));
    }

    function test_All_LengthGte() public view {
        bytes[] memory arr = new bytes[](2);
        arr[0] = bytes("aa");
        arr[1] = bytes("bbb");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ALL).lengthGte(2))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(bytes[])", arr));
    }

    function test_All_LengthBetween() public view {
        bytes[] memory arr = new bytes[](2);
        arr[0] = bytes("a");
        arr[1] = bytes("bb");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ALL).lengthBetween(1, 2))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(bytes[])", arr));
    }

    /*/////////////////////////////////////////////////////////////////////////
                           QUANTIFIED SIGNED ORDERING
    /////////////////////////////////////////////////////////////////////////*/

    function test_All_Lt_SignedNegativeLessThanPositive() public view {
        int256[] memory arr = new int256[](2);
        arr[0] = -2;
        arr[1] = -1;
        bytes memory policy = PolicyBuilder.create("foo(int256[])")
            .add(arg(0, Path.ALL).lt(int256(1)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(int256[])", arr));
    }

    function test_All_Gt_SignedPositiveGreaterThanNegative() public view {
        int256[] memory arr = new int256[](2);
        arr[0] = -100;
        arr[1] = 1;
        bytes memory policy = PolicyBuilder.create("foo(int256[])")
            .add(arg(0, Path.ALL).gt(int256(-200)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(int256[])", arr));
    }

    function test_All_Gte_SignedNegativeEqual() public view {
        int256[] memory arr = new int256[](2);
        arr[0] = -42;
        arr[1] = 0;
        bytes memory policy = PolicyBuilder.create("foo(int256[])")
            .add(arg(0, Path.ALL).gte(int256(-42)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(int256[])", arr));
    }

    function test_All_Lte_SignedNegativeEqual() public view {
        int256[] memory arr = new int256[](2);
        arr[0] = -100;
        arr[1] = -42;
        bytes memory policy = PolicyBuilder.create("foo(int256[])")
            .add(arg(0, Path.ALL).lte(int256(-42)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(int256[])", arr));
    }

    function test_All_Between_SignedNegativeRange() public view {
        int256[] memory arr = new int256[](2);
        arr[0] = -75;
        arr[1] = -60;
        bytes memory policy = PolicyBuilder.create("foo(int256[])")
            .add(arg(0, Path.ALL).between(int256(-100), int256(-50)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(int256[])", arr));
    }

    function test_All_Between_SignedCrossZeroRange() public view {
        int256[] memory arr = new int256[](3);
        arr[0] = -10;
        arr[1] = 0;
        arr[2] = 10;
        bytes memory policy = PolicyBuilder.create("foo(int256[])")
            .add(arg(0, Path.ALL).between(int256(-50), int256(50)))
            .buildUnsafe();
        harness.enforce(policy, abi.encodeWithSignature("foo(int256[])", arr));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                QUANTIFIER ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_All_OneElementFails() public {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).lte(uint256(2)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_ComposedStrictAll_EmptyArray() public {
        // Strict universality composes as lengthGt(0) + ALL in one group; empty arrays fail the length rule.
        uint256[] memory arr = new uint256[](0);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthGt(0))
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

    function test_RevertWhen_AnyElementReadOutOfBounds() public {
        // A read the enforcer cannot perform aborts under every quantifier, so the second group
        // never runs even though it would pass.
        bytes memory policy = PolicyBuilder.createRaw("uint256[],uint256")
            .add(arg(0, Path.ANY).eq(uint256(7)))
            .or()
            .add(arg(1).eq(uint256(5)))
            .build();
        // The array claims two elements but supplies one.
        bytes memory callData = abi.encodePacked(uint256(64), uint256(5), uint256(2), uint256(1));

        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
        harness.check(policy, callData);
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

    function test_RevertWhen_ValueOpOnDynamicElement() public {
        bytes memory policy =
            PolicyBuilder.create("foo(bytes[])").add(arg(0, Path.ALL).eq(uint256(0))).buildUnsafe();
        bytes[] memory arr = new bytes[](1);
        arr[0] = hex"1122";
        bytes memory callData = abi.encodeWithSignature("foo(bytes[])", arr);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NotScalar.selector, TypeCode.BYTES));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_ValueOpOnDynamicSuffixTarget() public {
        bytes memory policy =
            PolicyBuilder.create("foo(bytes[][])").add(arg(0, Path.ALL, 0).eq(uint256(0))).buildUnsafe();
        bytes[][] memory arr = new bytes[][](1);
        arr[0] = new bytes[](1);
        arr[0][0] = hex"1122";
        bytes memory callData = abi.encodeWithSignature("foo(bytes[][])", arr);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NotScalar.selector, TypeCode.BYTES));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_Lt_OneElementFails() public {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).lt(uint256(3)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_Gte_OneElementFails() public {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).gte(uint256(2)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_Between_OneElementFails() public {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).between(uint256(2), uint256(3)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_In_OneElementOutsideSet() public {
        uint256[] memory arr = new uint256[](2);
        arr[0] = 10;
        arr[1] = 11;
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).isIn(_defaultSet()))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_BitmaskAll_OneElementFails() public {
        uint256[] memory arr = new uint256[](2);
        arr[0] = 0x0F;
        arr[1] = 0x07;
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).bitmaskAll(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_BitmaskAny_OneElementFails() public {
        uint256[] memory arr = new uint256[](2);
        arr[0] = 0x01;
        arr[1] = 0xF0;
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).bitmaskAny(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_BitmaskNone_OneElementFails() public {
        uint256[] memory arr = new uint256[](2);
        arr[0] = 0xF0;
        arr[1] = 0x01;
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).bitmaskNone(0x0F))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_NotFlag_OneElementEqual() public {
        uint256[] memory arr = _uintArray(3); // [1, 2, 3]
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).neq(uint256(2)))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_NotIn_OneElementInSet() public {
        uint256[] memory arr = new uint256[](2);
        arr[0] = 1;
        arr[1] = 10;
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).notIn(_defaultSet()))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_LengthLt_OneElementFails() public {
        bytes[] memory arr = new bytes[](2);
        arr[0] = bytes("a");
        arr[1] = bytes("bbb");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ALL).lengthLt(3))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(bytes[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_LengthLte_OneElementFails() public {
        bytes[] memory arr = new bytes[](2);
        arr[0] = bytes("a");
        arr[1] = bytes("bbb");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ALL).lengthLte(2))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(bytes[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_LengthGte_OneElementFails() public {
        bytes[] memory arr = new bytes[](2);
        arr[0] = bytes("aa");
        arr[1] = bytes("b");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ALL).lengthGte(2))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(bytes[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
        harness.enforce(policy, callData);
    }

    function test_RevertWhen_All_LengthBetween_OneElementFails() public {
        bytes[] memory arr = new bytes[](2);
        arr[0] = bytes("a");
        arr[1] = bytes("bbb");
        bytes memory policy = PolicyBuilder.create("foo(bytes[])")
            .add(arg(0, Path.ALL).lengthBetween(1, 2))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(bytes[])", arr);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, 0, 0));
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

    function testFuzz_All_Semantics(uint8 length, uint256 threshold) public view {
        length = uint8(bound(length, 0, 50));
        threshold = bound(threshold, 0, type(uint128).max);

        uint256[] memory arr = _uintArray(length);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).lte(threshold))
            .buildUnsafe();
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);

        bool expected = length == 0 || length <= threshold;
        assertEq(harness.check(policy, callData), expected);
    }

    function testFuzz_ComposedStrictAll_Semantics(uint8 length, uint256 threshold) public view {
        length = uint8(bound(length, 0, 50));
        threshold = bound(threshold, 0, type(uint128).max);

        uint256[] memory arr = _uintArray(length);
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0).lengthGt(0))
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
        data.groups[0][0] = Constraint({ scope: PF.SCOPE_CALLDATA, path: hex"0000", operators: operators, hint: "" });
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

    /*/////////////////////////////////////////////////////////////////////////
                            VALUE CANONICALIZATION
    /////////////////////////////////////////////////////////////////////////*/

    // A resolved scalar must already carry the canonical encoding of its declared type. A word
    // with bits outside that encoding is rejected rather than masked, so the operator always
    // applies to the same bytes a consumer decoding the same type would read.

    /// @dev uint64: bit set above the declared width.
    function test_RevertWhen_UintCarriesBitsAboveWidth() public {
        bytes memory policy = PolicyBuilder.create("foo(uint64)").add(arg(0).gte(uint256(1000))).buildUnsafe();
        bytes32 word = bytes32((uint256(1) << 64) | 1);
        bytes memory callData = abi.encodePacked(bytes4(keccak256("foo(uint64)")), word);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.NonCanonicalValue.selector, TypeCode.UINT64, word));
        harness.check(policy, callData);
    }

    /// @dev int64: low bits encode a negative value without the matching sign extension.
    function test_RevertWhen_SignedLacksSignExtension() public {
        bytes memory policy = PolicyBuilder.create("foo(int64)").add(arg(0).gte(int256(0))).buildUnsafe();
        bytes32 word = bytes32(uint256(type(uint64).max));
        bytes memory callData = abi.encodePacked(bytes4(keccak256("foo(int64)")), word);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.NonCanonicalValue.selector, TypeCode.INT64, word));
        harness.check(policy, callData);
    }

    /// @dev The rejection precedes the operator, so a negated rule is no exception.
    function test_RevertWhen_NegatedEqualityReceivesDirtyWord() public {
        bytes memory policy = PolicyBuilder.create("foo(uint64)").add(arg(0).neq(uint256(7))).buildUnsafe();
        bytes32 word = bytes32((uint256(1) << 255) | 7);
        bytes memory callData = abi.encodePacked(bytes4(keccak256("foo(uint64)")), word);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.NonCanonicalValue.selector, TypeCode.UINT64, word));
        harness.check(policy, callData);
    }

    /// @dev Control: the same policies discriminate normally on canonically encoded words.
    function test_CanonicalWordsStillDiscriminate() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint64)").add(arg(0).gte(uint256(1000))).buildUnsafe();
        bytes4 selector = bytes4(keccak256("foo(uint64)"));
        assertTrue(harness.check(policy, abi.encodePacked(selector, bytes32(uint256(2000)))), "2000 satisfies >= 1000");
        assertFalse(harness.check(policy, abi.encodePacked(selector, bytes32(uint256(1)))), "1 violates >= 1000");
    }
}

/// @dev Tests for hint-driven target resolution.
/// A calldata rule resolves its target through its compiled hint alone, so rewriting a stored hint
/// changes what the rule reads while its path stays as it was.
contract EnforceHintDispatchTest is PolicyEnforcerTest {
    /// @dev Returns the offset of the target delta of the first rule's hop-free hint block.
    function _firstTargetDeltaOffset(bytes memory policy) private pure returns (uint256) {
        return _firstHintOffset(policy) + PF.HINT_HEADER_SIZE;
    }

    function test_HintAddressesTarget() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256,uint256)").add(arg(0).eq(uint256(1))).buildUnsafe();
        // Re-point the hint at the second argument while the path still names the first.
        _writeU32(policy, _firstTargetDeltaOffset(policy), 32);

        bytes memory callData = abi.encodeWithSignature("foo(uint256,uint256)", uint256(9), uint256(1));
        assertTrue(harness.check(policy, callData), "the hint selects the read");
    }

    function test_PathBytesDoNotAddressTheTarget() public view {
        bytes memory policy = PolicyBuilder.create("foo(uint256,uint256)").add(arg(1).eq(uint256(1))).buildUnsafe();
        // Rewriting the path leaves resolution untouched; the hint still reaches the second argument.
        Be16.write(policy, _firstRuleOffset(policy) + PF.RULE_PATH_OFFSET, 0);

        assertTrue(
            harness.check(policy, abi.encodeWithSignature("foo(uint256,uint256)", uint256(9), uint256(1))),
            "the hint reaches its own target"
        );
        assertFalse(
            harness.check(policy, abi.encodeWithSignature("foo(uint256,uint256)", uint256(1), uint256(9))),
            "the rewritten path selects nothing"
        );
    }

    function test_RevertWhen_QuantifiedHintPointerOutOfBounds() public {
        bytes memory policy = PolicyBuilder.create("foo(uint256[])").add(arg(0, Path.ALL).eq(uint256(1))).buildUnsafe();
        // The array head word addresses far beyond calldata, so the read fails.
        bytes memory callData = abi.encodePacked(bytes4(keccak256("foo(uint256[])")), uint256(2) ** 200, uint256(1));

        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
        harness.check(policy, callData);
    }

    function test_QuantifiedHintAddressesElementField() public view {
        bytes memory policy =
            PolicyBuilder.create("foo((uint256,uint256)[])").add(arg(0, Path.ALL, 0).eq(uint256(1))).buildUnsafe();
        // Re-point the target delta at the second field of each element.
        uint256 targetDeltaOffset = _firstHintOffset(policy) + PF.HINT_HEADER_SIZE + PF.HINT_HOP_SIZE
            + PF.HINT_FRAME_PREFIX_SIZE + PF.HINT_HEADER_SIZE;
        _writeU32(policy, targetDeltaOffset, 32);

        TwoUints[] memory elements = new TwoUints[](2);
        elements[0] = TwoUints({ a: 9, b: 1 });
        elements[1] = TwoUints({ a: 9, b: 1 });
        bytes memory callData = abi.encodeWithSignature("foo((uint256,uint256)[])", elements);
        assertTrue(harness.check(policy, callData), "the target delta selects the field");
    }
}

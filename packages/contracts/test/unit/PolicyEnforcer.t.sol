// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { DescriptorFormat as DF } from "src/DescriptorFormat.sol";
import { OpCode } from "src/OpCode.sol";
import { Policy } from "src/Policy.sol";
import { PolicyEnforcer } from "src/PolicyEnforcer.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";
import { TypeCode } from "src/TypeCode.sol";
import { LibBytes } from "src/vendor/solady/utils/LibBytes.sol";

import { PolicyEnforcerHarness } from "test/harnesses/PolicyEnforcerHarness.sol";

abstract contract PolicyEnforcerTest is Test {
    /// @dev Enforcement vector `canon-uint-dirty-reject`: uint64 word with the top bit set.
    bytes internal constant CANON_UINT_DIRTY_REJECT_BLOB =
        hex"60decb0da1000302010801000100000019001901010000000000000000000804000800000000000003e8";

    bytes internal constant CANON_UINT_DIRTY_REJECT_CALLDATA =
        hex"decb0da180000000000000000000000000000000000000000000000000000000000007d0";

    /// @dev Enforcement vector `multi-rule-and-fail`: GT 0 and LTE 100 on one argument: 101 fails the second.
    bytes internal constant MULTI_RULE_AND_FAIL_BLOB =
        hex"602fbebd380003020120010002000000620031010100000000000000000020020020000000000000000000000000000000000000000000000000000000000000000000310101000000000000000000200500200000000000000000000000000000000000000000000000000000000000000064";

    bytes internal constant MULTI_RULE_AND_FAIL_CALLDATA =
        hex"2fbebd380000000000000000000000000000000000000000000000000000000000000065";

    /// @dev Enforcement vector `multi-group-or-fail-all`: every group fails, since 99 is neither 1 nor 2.
    bytes internal constant MULTI_GROUP_OR_FAIL_ALL_BLOB =
        hex"602fbebd380003020120020001000000310031010100000000000000000020010020000000000000000000000000000000000000000000000000000000000000000100010000003100310101000000000000000000200100200000000000000000000000000000000000000000000000000000000000000002";

    bytes internal constant MULTI_GROUP_OR_FAIL_ALL_CALLDATA =
        hex"2fbebd380000000000000000000000000000000000000000000000000000000000000063";

    /// @dev Enforcement vector `quantifier-static-limit-exceeded`: ALL over a static array of MAX_STATIC_ARRAY_LENGTH
    /// elements aborts before reading an element.
    bytes internal constant QUANTIFIER_STATIC_LIMIT_EXCEEDED_BLOB =
        hex"60ef32e7e10009020180fff007200fff010001000000410041020101000000000000000fff00010001002f01000000000000000020040020000000000000000000000000000000000000000000000000000000000000000a";

    bytes internal constant QUANTIFIER_STATIC_LIMIT_EXCEEDED_CALLDATA = hex"ef32e7e1";

    /// @dev Enforcement vector `quantifier-all-reads-dirty`: ALL reads each passing element; a dirty one aborts.
    bytes internal constant QUANTIFIER_ALL_READS_DIRTY_BLOB =
        hex"60af79f68b0007020181000005010100010000002a002a02010100000100000000ffff0000000000000000400100010010010000000000000000010200010a";

    bytes internal constant QUANTIFIER_ALL_READS_DIRTY_CALLDATA =
        hex"af79f68b00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000001ff";

    PolicyEnforcerHarness internal harness;

    function setUp() public virtual {
        harness = new PolicyEnforcerHarness();
    }

    /// @dev Returns the blob of one group holding one test on the only argument of a function whose selector is zero:
    /// the argument of type `typeCode` compared by `opCode` against the operator data `data`.
    function _singleTestBlob(uint8 typeCode, uint8 opCode, bytes memory data) internal pure returns (bytes memory) {
        bytes memory rule = abi.encodePacked(
            PF.SCOPE_CALLDATA,
            uint8(1), // pathDepth.
            uint16(0), // path: parameter 0.
            uint8(0), // hint: no hops.
            uint32(0), // targetDelta.
            uint16(0), // targetMeta.
            typeCode,
            opCode,
            uint16(data.length),
            data
        );
        rule = abi.encodePacked(uint16(rule.length + PF.RULE_SIZE_SIZE), rule);
        bytes memory desc = abi.encodePacked(DF.VERSION, uint8(1), typeCode);
        return abi.encodePacked(
            uint8(PF.MAJOR << PF.MAJOR_SHIFT),
            bytes4(0),
            uint16(desc.length),
            desc,
            uint8(1), // groupCount.
            uint16(1), // ruleCount.
            uint32(rule.length), // groupSize.
            rule
        );
    }

    /// @dev Returns calldata calling the zero selector with `word` as its only argument.
    function _callData(bytes32 word) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes4(0), word);
    }
}

contract PolicyEnforcerEnforceTest is PolicyEnforcerTest {
    function test_RevertWhen_EveryGroupFails() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, uint32(1), uint32(0)));
        harness.enforce(MULTI_GROUP_OR_FAIL_ALL_BLOB, MULTI_GROUP_OR_FAIL_ALL_CALLDATA);
    }

    function test_RevertWhen_ALaterRuleFails() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.PolicyViolation.selector, uint32(0), uint32(1)));
        harness.enforce(MULTI_RULE_AND_FAIL_BLOB, MULTI_RULE_AND_FAIL_CALLDATA);
    }
}

contract PolicyEnforcerCheckTest is PolicyEnforcerTest {
    /// @dev Returns the verdict on `word` of one test applying `opCode` with operand `data` to the type `typeCode`.
    function _check(uint8 typeCode, uint8 opCode, bytes memory data, bytes32 word) private view returns (bool) {
        return harness.check(_singleTestBlob(typeCode, opCode, data), _callData(word));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 ENTRY AND ABORTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_MajorUnsupported() public {
        bytes memory blob = MULTI_RULE_AND_FAIL_BLOB;
        uint8 major = PF.MAJOR + 1;
        uint8 minor = PF.SUPPORTED_MINOR + 1;
        blob[PF.POLICY_HEADER_OFFSET] = bytes1((major << PF.MAJOR_SHIFT) | (minor << PF.MINOR_SHIFT));
        vm.expectRevert(abi.encodeWithSelector(Policy.UnsupportedVersion.selector, major));
        harness.check(blob, MULTI_RULE_AND_FAIL_CALLDATA);
    }

    function test_RevertWhen_MinorAboveSupported() public {
        bytes memory blob = MULTI_RULE_AND_FAIL_BLOB;
        uint8 minor = PF.SUPPORTED_MINOR + 1;
        blob[PF.POLICY_HEADER_OFFSET] = bytes1((PF.MAJOR << PF.MAJOR_SHIFT) | (minor << PF.MINOR_SHIFT));
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.UnsupportedMinor.selector, minor));
        harness.check(blob, MULTI_RULE_AND_FAIL_CALLDATA);
    }

    function test_RevertWhen_LoopExceedsLimit() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyEnforcer.QuantifierLimitExceeded.selector,
                DF.MAX_STATIC_ARRAY_LENGTH,
                PF.MAX_QUANTIFIED_ARRAY_LENGTH
            )
        );
        harness.check(QUANTIFIER_STATIC_LIMIT_EXCEEDED_BLOB, QUANTIFIER_STATIC_LIMIT_EXCEEDED_CALLDATA);
    }

    function test_RevertWhen_WordIsNotCanonical() public {
        bytes memory callData = CANON_UINT_DIRTY_REJECT_CALLDATA;
        // The vector's only argument is the dirty word.
        bytes32 word = LibBytes.load(callData, callData.length - 32);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.NonCanonicalValue.selector, TypeCode.UINT64, word));
        harness.check(CANON_UINT_DIRTY_REJECT_BLOB, callData);
    }

    function test_RevertWhen_ElementIsNotCanonical() public {
        bytes memory callData = QUANTIFIER_ALL_READS_DIRTY_CALLDATA;
        // The vector's last element is the dirty word.
        bytes32 word = LibBytes.load(callData, callData.length - 32);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnforcer.NonCanonicalValue.selector, TypeCode.UINT8, word));
        harness.check(QUANTIFIER_ALL_READS_DIRTY_BLOB, callData);
    }

    /*/////////////////////////////////////////////////////////////////////////
                               OPERATOR APPLICATION
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Order comparisons on a signed operand one byte wide compare as signed integers.
    function prove_OrdersSignedValues(int8 value, int8 operand, bool negated) public view {
        bytes memory data = abi.encodePacked(operand);
        bytes32 word = bytes32(uint256(int256(value)));
        uint8 not = negated ? OpCode.NOT : 0;
        assertEq(_check(TypeCode.INT8, OpCode.GT | not, data, word), (value > operand) != negated);
        assertEq(_check(TypeCode.INT8, OpCode.LT | not, data, word), (value < operand) != negated);
        assertEq(_check(TypeCode.INT8, OpCode.GTE | not, data, word), (value >= operand) != negated);
        assertEq(_check(TypeCode.INT8, OpCode.LTE | not, data, word), (value <= operand) != negated);
        assertEq(_check(TypeCode.INT8, OpCode.EQ | not, data, word), (value == operand) != negated);
    }

    /// @dev Order comparisons on an unsigned operand one byte wide compare as unsigned integers.
    function prove_OrdersUnsignedValues(uint8 value, uint8 operand) public view {
        bytes memory data = abi.encodePacked(operand);
        bytes32 word = bytes32(uint256(value));
        assertEq(_check(TypeCode.UINT8, OpCode.GT, data, word), value > operand);
        assertEq(_check(TypeCode.UINT8, OpCode.LT, data, word), value < operand);
        assertEq(_check(TypeCode.UINT8, OpCode.GTE, data, word), value >= operand);
        assertEq(_check(TypeCode.UINT8, OpCode.LTE, data, word), value <= operand);
    }

    /// @dev A signed range holds its bounds and every value between them.
    function prove_RangesSignedValues(int8 value, int8 lower, int8 upper) public view {
        bytes memory data = abi.encodePacked(lower, upper);
        bytes32 word = bytes32(uint256(int256(value)));
        assertEq(_check(TypeCode.INT8, OpCode.BETWEEN, data, word), value >= lower && value <= upper);
    }

    /// @dev A mask on a signed operand is its bit pattern, sign-extended like the value it masks.
    function prove_MasksSignedValues(int8 value, int8 mask) public view {
        bytes memory data = abi.encodePacked(mask);
        bytes32 word = bytes32(uint256(int256(value)));
        assertEq(_check(TypeCode.INT8, OpCode.BITMASK_ALL, data, word), value & mask == mask);
        assertEq(_check(TypeCode.INT8, OpCode.BITMASK_ANY, data, word), value & mask != 0);
        assertEq(_check(TypeCode.INT8, OpCode.BITMASK_NONE, data, word), value & mask == 0);
    }

    /// @dev A left-aligned operand compares against the value's high bytes.
    function prove_ComparesLeftAlignedValues(bytes4 value, bytes4 operand) public view {
        assertEq(_check(TypeCode.BYTES4, OpCode.EQ, abi.encodePacked(operand), bytes32(value)), value == operand);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  SET MEMBERSHIP
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev A set of eight ascending 32-byte members holds exactly its members.
    function prove_FindsExactlyTheMembers(uint256[8] memory members, uint256 value) public view {
        for (uint256 i = 1; i < members.length; ++i) {
            vm.assume(members[i - 1] < members[i]);
        }
        bool isMember;
        for (uint256 i = 0; i < members.length; ++i) {
            isMember = isMember || members[i] == value;
        }
        assertEq(_check(TypeCode.UINT256, OpCode.IN, abi.encodePacked(members), bytes32(value)), isMember);
    }

    /// @dev A set of eight ascending 20-byte members holds exactly its members, each probe stepping one member wide.
    function prove_FindsExactlyTheNarrowMembers(address[8] memory members, address value) public view {
        bytes memory data;
        bool isMember;
        for (uint256 i = 0; i < members.length; ++i) {
            if (i > 0) vm.assume(members[i - 1] < members[i]);
            data = abi.encodePacked(data, members[i]);
            isMember = isMember || members[i] == value;
        }
        assertEq(_check(TypeCode.ADDRESS, OpCode.IN, data, bytes32(uint256(uint160(value)))), isMember);
    }
}

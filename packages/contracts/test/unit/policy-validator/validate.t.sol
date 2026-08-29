// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyValidatorHarness } from "../../harnesses/PolicyValidatorHarness.sol";
import { PolicyValidatorTest } from "../PolicyValidator.t.sol";
import { Constraint, arg, msgSender } from "src/Constraint.sol";
import { Descriptor } from "src/Descriptor.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { IssueCode } from "src/IssueCode.sol";
import { OpCode } from "src/OpCode.sol";
import { Path } from "src/Path.sol";
import { PolicyData } from "src/PolicyCoder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";
import { PolicyValidator } from "src/PolicyValidator.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeDesc } from "src/TypeDesc.sol";
import { Issue, IssueCategory, IssueSeverity } from "src/ValidationIssue.sol";

contract LengthOnStaticTest is PolicyValidatorTest {
    function test_LengthOnUint256_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // Create constraint with length operator on uint256
        Constraint memory c = arg(0).lengthEq(5);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].severity, IssueSeverity.Error);
        assertEq(issues[0].category, IssueCategory.TypeMismatch);
        assertEq(issues[0].code, IssueCode.LENGTH_ON_STATIC);
    }

    function test_LengthOnAddress_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.address_()).build();

        Constraint memory c = arg(0).lengthGt(0);

        PolicyData memory data = _createPolicyData("foo(address)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues[0].code, IssueCode.LENGTH_ON_STATIC);
    }

    function test_LengthOnDynamicBytes_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytes_()).build();

        Constraint memory c = arg(0).lengthEq(10);

        PolicyData memory data = _createPolicyData("foo(bytes)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }

    function test_LengthOnString_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.string_()).build();

        Constraint memory c = arg(0).lengthLte(100);

        PolicyData memory data = _createPolicyData("foo(string)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }

    function test_LengthOnDynamicArray_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.uint256_())).build();

        Constraint memory c = arg(0).lengthGte(1);

        PolicyData memory data = _createPolicyData("foo(uint256[])", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }
}

contract ValueOpOnCompositeTest is PolicyValidatorTest {
    function test_EqOnSingleElementStaticArray_ReturnsError() public pure {
        // uint256[1] has a 32-byte static head but is composite; the enforcer cannot load it.
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.uint256_(), 1)).build();

        Constraint memory c = arg(0).eq(uint256(42));

        PolicyData memory data = _createPolicyData("foo(uint256[1])", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].severity, IssueSeverity.Error);
        assertEq(issues[0].category, IssueCategory.TypeMismatch);
        assertEq(issues[0].code, IssueCode.VALUE_OP_ON_COMPOSITE);
    }

    function test_EqOnSingleStaticFieldTuple_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.tuple_(TypeDesc.uint256_())).build();

        Constraint memory c = arg(0).eq(uint256(42));

        PolicyData memory data = _createPolicyData("foo((uint256))", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.VALUE_OP_ON_COMPOSITE);
    }

    function test_EqOnTupleField_NoError() public pure {
        // Descending into the field reaches the elementary type; this is the correct authoring.
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.tuple_(TypeDesc.uint256_())).build();

        Constraint memory c = arg(0, 0).eq(uint256(42));

        PolicyData memory data = _createPolicyData("foo((uint256))", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }

    function test_AllQuantifierOnStaticArray_NoError() public pure {
        // Quantified paths resolve to the element type for static arrays.
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.uint256_(), 3)).build();

        Constraint memory c = arg(0, Path.ALL).eq(uint256(42));

        PolicyData memory data = _createPolicyData("foo(uint256[3])", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }
}

contract NumericOpOnNonNumericTest is PolicyValidatorTest {
    function test_GtOnAddress_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.address_()).build();

        Constraint memory c = arg(0).gt(uint256(100));

        PolicyData memory data = _createPolicyData("foo(address)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues[0].code, IssueCode.NUMERIC_OP_ON_NON_NUMERIC);
    }

    function test_LtOnBool_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bool_()).build();

        Constraint memory c = arg(0).lt(uint256(1));

        PolicyData memory data = _createPolicyData("foo(bool)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues[0].code, IssueCode.NUMERIC_OP_ON_NON_NUMERIC);
    }

    function test_GtOnUint256_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(0).gt(uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }

    function test_GtOnInt256_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.int256_()).build();

        Constraint memory c = arg(0).gt(int256(-100));

        PolicyData memory data = _createPolicyData("foo(int256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }
}

contract BitmaskOnInvalidTest is PolicyValidatorTest {
    function test_BitmaskOnAddress_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.address_()).build();

        Constraint memory c = arg(0).bitmaskAll(uint256(0xff));

        PolicyData memory data = _createPolicyData("foo(address)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues[0].code, IssueCode.BITMASK_ON_INVALID);
    }

    function test_BitmaskOnUint256_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(0).bitmaskAll(uint256(0xff));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }

    function test_BitmaskOnBytes32_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytes32_()).build();

        Constraint memory c = arg(0).bitmaskAny(uint256(0xff));

        PolicyData memory data = _createPolicyData("foo(bytes32)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }
}

contract NonCanonicalOperandTest is PolicyValidatorTest {
    function test_RightAlignedBytes4Operand_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytesN_(4)).build();

        // A right-aligned word for a left-aligned type can never match a canonical value.
        Constraint memory c = arg(0).eq(bytes32(uint256(0x11223344)));

        PolicyData memory data = _createPolicyData("foo(bytes4)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues[0].code, IssueCode.NON_CANONICAL_OPERAND);
    }

    function test_LeftAlignedBytes4Operand_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytesN_(4)).build();

        Constraint memory c = arg(0).eq(bytes32(bytes4(0x11223344)));

        PolicyData memory data = _createPolicyData("foo(bytes4)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }

    function test_TrailingBytes4Operand_ReportsOperandAndCanonical() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytesN_(4)).build();

        bytes32 operand = bytes32(bytes4(0x11223344)) | bytes32(uint256(0x55));
        Constraint memory c = arg(0).eq(operand);

        PolicyData memory data = _createPolicyData("foo(bytes4)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.NON_CANONICAL_OPERAND);
        assertEq(issue.value1, operand);
        assertEq(issue.value2, bytes32(bytes4(0x11223344)));
    }

    function test_RightAlignedInMember_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytesN_(4)).build();

        bytes32[] memory set = new bytes32[](2);
        set[0] = bytes32(uint256(0x11223344));
        set[1] = bytes32(bytes4(0x11223344));
        Constraint memory c = arg(0).isIn(set);

        PolicyData memory data = _createPolicyData("foo(bytes4)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues[0].code, IssueCode.NON_CANONICAL_OPERAND);
    }
}

contract UnknownOperatorTest is PolicyValidatorTest {
    function test_UnassignedOpcode_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // First opcode in the unassigned gap before the bitmask range.
        Constraint memory c = arg(0).addOp(0x09, new bytes(32));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].severity, IssueSeverity.Error);
        assertEq(issues[0].category, IssueCategory.TypeMismatch);
        assertEq(issues[0].code, IssueCode.UNKNOWN_OPERATOR);
    }

    function test_MismatchedPayloadSize_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // A single-operand opcode carrying a two-word payload.
        Constraint memory c = arg(0).addOp(OpCode.EQ, new bytes(64));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.UNKNOWN_OPERATOR);
    }

    function test_InPayloadNotWordMultiple_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(0).addOp(OpCode.IN, new bytes(48));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.UNKNOWN_OPERATOR);
    }
}

contract ValidPolicyTest is PolicyValidatorTest {
    function test_ValidEqOnUint256_NoIssues() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(0).eq(uint256(42));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }

    function test_ValidContextConstraint_NoIssues() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = msgSender().eq(address(1));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }
}

contract ImpossibleRangeTest is PolicyValidatorTest {
    function test_GtThenLt_ImpossibleRange_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gt(100).lt(50) - impossible because nothing is both > 100 and < 50
        Constraint memory c = arg(0).gt(uint256(100)).lt(uint256(50));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
        assertEq(issue.severity, IssueSeverity.Error);
        assertEq(issue.category, IssueCategory.Contradiction);
        assertEq(issue.value1, bytes32(uint256(100)));
        assertEq(issue.value2, bytes32(uint256(50)));
    }

    function test_GteThenLte_EqualBoundsExclusive_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gt(50).lte(50) - impossible because nothing is both > 50 and <= 50
        Constraint memory c = arg(0).gt(uint256(50)).lte(uint256(50));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertGt(issues.length, 0);
    }

    function test_ValidRange_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gt(10).lt(100) - valid range
        Constraint memory c = arg(0).gt(uint256(10)).lt(uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
    }

    function test_GteLte_SameValue_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gte(50).lte(50) - valid, matches exactly 50
        Constraint memory c = arg(0).gte(uint256(50)).lte(uint256(50));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
    }

    function test_Between_Decomposition_Works() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(256)).build();

        // between(10, 20).gt(30) -> [10, 20] and > 30 is impossible
        Constraint memory c = arg(0).between(uint256(10), uint256(20)).gt(uint256(30));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
    }

    function test_CrossConstraint_Contradiction_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(256)).build();

        // Constraint 0: arg(0).gt(100)
        // Constraint 1: arg(0).lt(50)
        // AND-ed -> contradiction
        Constraint[] memory group = new Constraint[](2);
        group[0] = arg(0).gt(uint256(100));
        group[1] = arg(0).lt(uint256(50));

        // forgefmt: disable-next-item
        PolicyData memory data = PolicyData({
            isSelectorless: false, selector: 0x12345678, descriptor: desc, groups: new Constraint[][](1)
        });
        data.groups[0] = group;

        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
    }

    function test_ComposedStrictAll_WithLengthEqZero_ReturnsContradiction() public pure {
        // Strict universality composes as lengthGt(0) + ALL; adding lengthEq(0) contradicts the length rule.
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");

        Constraint[] memory group = new Constraint[](2);
        group[0] = arg(0).lengthEq(0).lengthGt(0);
        group[1] = arg(0, Path.ALL).gt(uint256(0));

        // forgefmt: disable-next-item
        PolicyData memory data = PolicyData({
            isSelectorless: false, selector: 0x12345678, descriptor: desc, groups: new Constraint[][](1)
        });
        data.groups[0] = group;

        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.BOUNDS_EXCLUDE_LENGTH);
    }

    function test_NegatedGT_Decomposition_ReturnsContradiction() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Constraint memory c = arg(0).gt(uint256(10));
        // NOT GT(10) is LTE(10). GT(10) and LTE(10) is impossible.
        c.operators = _appendOp(c.operators, OpCode.GT | OpCode.NOT, abi.encode(uint256(10)));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
    }

    function test_NegatedBetween_Satisfiable_NoImpossibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // !between(5, 10) is (x < 5 OR x > 10), a disjunction satisfiable at e.g. 3 or 11.
        // The negation must not be modeled as (x > 10 AND x < 5), a spurious contradiction.
        Constraint memory c = arg(0);
        c.operators = _appendOp(c.operators, OpCode.BETWEEN | OpCode.NOT, abi.encodePacked(uint256(5), uint256(10)));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
    }

    function test_NegatedLengthBetween_Satisfiable_NoImpossibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytes_()).build();

        // !lengthBetween(5, 10) is (len < 5 OR len > 10), a disjunction satisfiable at e.g. 3 or 11.
        Constraint memory c = arg(0);
        // forgefmt: disable-next-item
        c.operators = _appendOp(
            c.operators, OpCode.LENGTH_BETWEEN | OpCode.NOT, abi.encodePacked(uint256(5), uint256(10))
        );

        PolicyData memory data = _createPolicyData("foo(bytes)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.IMPOSSIBLE_LENGTH_RANGE);
    }
}

contract FusibleRangeTest is PolicyValidatorTest {
    function test_GteLtePair_ReportsFusibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(0).gte(uint256(10)).lte(uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.FUSIBLE_RANGE);
        assertEq(issues[0].severity, IssueSeverity.Warning);
        assertEq(issues[0].category, IssueCategory.Redundancy);
        assertEq(issues[0].value1, bytes32(uint256(10)));
        assertEq(issues[0].value2, bytes32(uint256(100)));
    }

    function test_GteLtePair_EqualBounds_ReportsFusibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(0).gte(uint256(50)).lte(uint256(50));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.FUSIBLE_RANGE);
    }

    function test_SignedGteLtePair_ReportsFusibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.int256_()).build();

        Constraint memory c = arg(0).gte(int256(-5)).lte(int256(5));

        PolicyData memory data = _createPolicyData("foo(int256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.FUSIBLE_RANGE);
        assertEq(issues[0].value1, bytes32(uint256(int256(-5))));
        assertEq(issues[0].value2, bytes32(uint256(int256(5))));
    }

    function test_LengthGteLtePair_ReportsFusibleLengthRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytes_()).build();

        Constraint memory c = arg(0).lengthGte(2).lengthLte(8);

        PolicyData memory data = _createPolicyData("foo(bytes)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.FUSIBLE_LENGTH_RANGE);
        assertEq(issues[0].value1, bytes32(uint256(2)));
        assertEq(issues[0].value2, bytes32(uint256(8)));
    }

    function test_Between_NoFusibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(0).between(uint256(10), uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }

    function test_GtLtPair_NoFusibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // Strict bounds have no inclusive-range equivalent.
        Constraint memory c = arg(0).gt(uint256(10)).lt(uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.FUSIBLE_RANGE);
    }

    function test_ImpossibleRange_NoFusibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(0).gte(uint256(100)).lte(uint256(50));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
        _assertNoIssue(issues, IssueCode.FUSIBLE_RANGE);
    }

    function test_SignedImpossibleRange_NoFusibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.int256_()).build();

        Constraint memory c = arg(0).gte(int256(5)).lte(int256(-5));

        PolicyData memory data = _createPolicyData("foo(int256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
        _assertNoIssue(issues, IssueCode.FUSIBLE_RANGE);
    }

    function test_NegatedGte_NoFusibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(0).lte(uint256(100));
        c.operators = _appendOp(c.operators, OpCode.GTE | OpCode.NOT, abi.encode(uint256(10)));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.FUSIBLE_RANGE);
    }

    function test_DuplicatedGte_NoFusibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // Only a clean single pair is fusible; extra bounds are already flagged as dominated.
        Constraint memory c = arg(0).gte(uint256(5)).gte(uint256(6)).lte(uint256(10));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.DOMINATED_BOUND);
        _assertNoIssue(issues, IssueCode.FUSIBLE_RANGE);
    }
}

contract ConflictingEqualityTest is PolicyValidatorTest {
    function test_MultipleEq_DifferentValues_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // eq(5).eq(10) - impossible because value can't equal both 5 and 10
        Constraint memory c = arg(0).eq(uint256(5)).eq(uint256(10));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.CONFLICTING_EQUALITY);
        assertEq(issue.value1, bytes32(uint256(5)));
        assertEq(issue.value2, bytes32(uint256(10)));
    }

    function test_MultipleEq_SameValue_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // eq(5).eq(5) - redundant but not conflicting
        Constraint memory c = arg(0).eq(uint256(5)).eq(uint256(5));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.CONFLICTING_EQUALITY);
    }

    function test_EqNeq_Contradiction_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(256)).build();

        // eq(42).neq(42)
        Constraint memory c = arg(0).eq(uint256(42)).neq(uint256(42));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.EQ_NEQ_CONTRADICTION);
    }

    function test_NeqEq_Contradiction_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(256)).build();

        // neq(42).eq(42)
        Constraint memory c = arg(0).neq(uint256(42)).eq(uint256(42));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.EQ_NEQ_CONTRADICTION);
    }
}

contract BoundsExcludeEqualityTest is PolicyValidatorTest {
    function test_EqBelowLowerBound_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // eq(5).gt(10) - impossible because 5 is not > 10
        Constraint memory c = arg(0).eq(uint256(5)).gt(uint256(10));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.BOUNDS_EXCLUDE_EQUALITY);
        assertEq(issue.value1, bytes32(uint256(5)));
        assertEq(issue.value2, bytes32(uint256(10)));
    }

    function test_EqAboveUpperBound_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // eq(100).lt(50) - impossible because 100 is not < 50
        Constraint memory c = arg(0).eq(uint256(100)).lt(uint256(50));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertGt(issues.length, 0);
    }

    function test_EqWithinBounds_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // eq(50).gte(10).lte(100) - valid, 50 is within [10, 100]
        Constraint memory c = arg(0).eq(uint256(50)).gte(uint256(10)).lte(uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.BOUNDS_EXCLUDE_EQUALITY);
    }

    function test_EqNotIn_Contradiction_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(256)).build();

        // eq(42).notIn([42, 43])
        uint256[] memory set = new uint256[](2);
        set[0] = 42;
        set[1] = 43;
        Constraint memory c = arg(0).eq(uint256(42)).notIn(set);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.SET_EXCLUDES_EQUALITY);
    }
}

contract DominatedBoundTest is PolicyValidatorTest {
    function test_GtGt_LowerDominated_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gt(10).gt(5) - gt(5) is redundant because gt(10) is stricter
        Constraint memory c = arg(0).gt(uint256(10)).gt(uint256(5));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.DOMINATED_BOUND);
        assertEq(issue.severity, IssueSeverity.Warning);
        assertEq(issue.category, IssueCategory.Redundancy);
    }

    function test_LtLt_HigherDominated_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // lt(50).lt(100) - lt(100) is redundant because lt(50) is stricter
        Constraint memory c = arg(0).lt(uint256(50)).lt(uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.DOMINATED_BOUND);
    }

    function test_GteGte_Dominated_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gte(100).gte(50) - gte(50) is redundant
        Constraint memory c = arg(0).gte(uint256(100)).gte(uint256(50));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertGt(issues.length, 0);
    }

    function test_LteLte_Dominated_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // lte(50).lte(100) - lte(100) is redundant
        Constraint memory c = arg(0).lte(uint256(50)).lte(uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertGt(issues.length, 0);
    }

    function test_EqMakesBoundRedundant() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Constraint memory c = arg(0).eq(uint256(10)).gte(uint256(5));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.REDUNDANT_BOUND);
        assertEq(issue.severity, IssueSeverity.Warning);
        assertEq(issue.value1, bytes32(uint256(5)));
        assertEq(issue.value2, bytes32(uint256(10)));
    }

    function test_GtGteSameValue_NoWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        // gt(5).gte(5) - gte(5) is looser, should be ignored silently
        Constraint memory c = arg(0).gt(uint256(5)).gte(uint256(5));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.DOMINATED_BOUND);
    }

    function test_GtSupersededByGte_ReportsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gt(0).gte(3) - gt(0) becomes dominated when gte(3) replaces it.
        Constraint memory c = arg(0).gt(uint256(0)).gte(uint256(3));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.DOMINATED_BOUND);
        assertEq(uint256(issue.value1), 0);
    }

    function test_GteSupersededByGt_ReportsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gte(5).gt(10) - gte(5) becomes dominated when gt(10) replaces it.
        Constraint memory c = arg(0).gte(uint256(5)).gt(uint256(10));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.DOMINATED_BOUND);
        assertEq(uint256(issue.value1), 5);
    }

    function test_LteSupersededByLt_ReportsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // lte(100).lt(50) - lte(100) becomes dominated when lt(50) replaces it.
        Constraint memory c = arg(0).lte(uint256(100)).lt(uint256(50));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.DOMINATED_BOUND);
        assertEq(uint256(issue.value1), 100);
    }

    function test_LtSupersededByLte_ReportsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // lt(200).lte(100) - lt(200) becomes dominated when lte(100) replaces it.
        Constraint memory c = arg(0).lt(uint256(200)).lte(uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.DOMINATED_BOUND);
    }

    function test_GteSupersededByGtSameValue_ReportsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gte(5).gt(5) - gt(5) is stricter, so gte(5) becomes dominated.
        Constraint memory c = arg(0).gte(uint256(5)).gt(uint256(5));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.DOMINATED_BOUND);
    }

    function test_LteSupersededByLtSameValue_ReportsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // lte(50).lt(50) - lt(50) is stricter, so lte(50) becomes dominated.
        Constraint memory c = arg(0).lte(uint256(50)).lt(uint256(50));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.DOMINATED_BOUND);
    }

    function test_LengthGteSuperseded_ReportsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytes_()).build();

        // lengthGte(5).lengthGte(10) - lengthGte(5) becomes dominated.
        Constraint memory c = arg(0).lengthGte(uint256(5)).lengthGte(uint256(10));

        PolicyData memory data = _createPolicyData("foo(bytes)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.DOMINATED_LENGTH_BOUND);
    }

    function test_LengthLteSuperseded_ReportsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytes_()).build();

        // lengthLte(100).lengthLte(50) - lengthLte(100) becomes dominated.
        Constraint memory c = arg(0).lengthLte(uint256(100)).lengthLte(uint256(50));

        PolicyData memory data = _createPolicyData("foo(bytes)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.DOMINATED_LENGTH_BOUND);
    }
}

contract DuplicateConstraintTest is PolicyValidatorTest {
    function test_DuplicateEq_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // eq(42).eq(42) - duplicate operator
        Constraint memory c = arg(0).eq(uint256(42)).eq(uint256(42));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.DUPLICATE_CONSTRAINT);
        assertEq(issue.severity, IssueSeverity.Warning);
    }

    function test_DuplicateGt_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gt(10).gt(10) - duplicate operator
        Constraint memory c = arg(0).gt(uint256(10)).gt(uint256(10));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertGt(issues.length, 0);
    }

    function test_DifferentOps_NoWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gt(10).lt(100) - not duplicates
        Constraint memory c = arg(0).gt(uint256(10)).lt(uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.DUPLICATE_CONSTRAINT);
    }
}

contract NoRedundancyTest is PolicyValidatorTest {
    function test_NonOverlappingBounds_NoWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // gt(10).lt(100) - valid range, no redundancy
        Constraint memory c = arg(0).gt(uint256(10)).lt(uint256(100));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }
}

contract PhysicalBoundsTest is PolicyValidatorTest {
    function test_Uint8_OutOfRange_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();

        // eq(256) on uint8 is impossible
        Constraint memory c = arg(0).eq(uint256(256));

        PolicyData memory data = _createPolicyData("foo(uint8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.OUT_OF_PHYSICAL_BOUNDS);
        assertEq(issue.severity, IssueSeverity.Error);
    }

    function test_Int8_OutOfRange_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.intN_(8)).build();

        // eq(128) on int8 is impossible (max is 127)
        Constraint memory c = arg(0).eq(int256(128));

        PolicyData memory data = _createPolicyData("foo(int8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.OUT_OF_PHYSICAL_BOUNDS);
    }

    function test_Int8_NegativeOutOfRange_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.intN_(8)).build();

        // eq(-129) on int8 is impossible (min is -128)
        Constraint memory c = arg(0).eq(int256(-129));

        PolicyData memory data = _createPolicyData("foo(int8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertGt(issues.length, 0);
    }

    function test_Uint8_SetMemberOutOfRange_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();

        uint256[] memory set = new uint256[](2);
        set[0] = 5;
        set[1] = 1000;
        Constraint memory c = arg(0).isIn(set);

        PolicyData memory data = _createPolicyData("foo(uint8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.OUT_OF_PHYSICAL_BOUNDS);
        assertEq(issue.severity, IssueSeverity.Error);
    }

    function test_Int8_NegativeSetMemberOutOfRange_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.intN_(8)).build();

        int256[] memory set = new int256[](2);
        set[0] = -5;
        set[1] = -129;
        Constraint memory c = arg(0).isIn(set);

        PolicyData memory data = _createPolicyData("foo(int8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.OUT_OF_PHYSICAL_BOUNDS);
    }

    function test_Uint8_SetMembersWithinRange_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();

        uint256[] memory set = new uint256[](2);
        set[0] = 0;
        set[1] = 255;
        Constraint memory c = arg(0).isIn(set);

        PolicyData memory data = _createPolicyData("foo(uint8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }

    function test_Uint8_WithinRange_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();

        Constraint memory c = arg(0).eq(uint256(255));

        PolicyData memory data = _createPolicyData("foo(uint8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }

    function test_ImpossibleGT_TypeMax_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();
        Constraint memory c = arg(0).gt(uint256(255));

        PolicyData memory data = _createPolicyData("foo(uint8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.IMPOSSIBLE_GT);
        assertEq(issue.severity, IssueSeverity.Error);
    }
}

contract VacuousConstraintTest is PolicyValidatorTest {
    function test_GteZero_ReturnsInfo() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();
        Constraint memory c = arg(0).gte(uint256(0));

        PolicyData memory data = _createPolicyData("foo(uint8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.VACUOUS_GTE);
        assertEq(issue.severity, IssueSeverity.Info);
        assertEq(issue.category, IssueCategory.Vacuity);
    }

    function test_LteMax_ReturnsInfo() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();
        Constraint memory c = arg(0).lte(uint256(255));

        PolicyData memory data = _createPolicyData("foo(uint8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.VACUOUS_LTE);
        assertEq(issue.severity, IssueSeverity.Info);
    }

    function test_NegatedRangeInvertedBounds_ReturnsInfo() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Constraint memory c = arg(0).addOp(OpCode.BETWEEN | OpCode.NOT, abi.encodePacked(uint256(100), uint256(10)));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.VACUOUS_NEGATED_RANGE);
        assertEq(issue.severity, IssueSeverity.Info);
        assertEq(issue.category, IssueCategory.Vacuity);
        assertEq(issue.value1, bytes32(uint256(100)));
        assertEq(issue.value2, bytes32(uint256(10)));
    }

    function test_NegatedRangeInvertedSignedBounds_ReturnsInfo() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.int256_()).build();
        Constraint memory c =
            arg(0).addOp(OpCode.BETWEEN | OpCode.NOT, abi.encodePacked(uint256(10), uint256(int256(-10))));

        PolicyData memory data = _createPolicyData("foo(int256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.VACUOUS_NEGATED_RANGE);
    }

    function test_NegatedLengthRangeInvertedBounds_ReturnsInfo() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytes_()).build();
        Constraint memory c =
            arg(0).addOp(OpCode.LENGTH_BETWEEN | OpCode.NOT, abi.encodePacked(uint256(100), uint256(10)));

        PolicyData memory data = _createPolicyData("foo(bytes)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.VACUOUS_NEGATED_LENGTH_RANGE);
        assertEq(issue.value1, bytes32(uint256(100)));
        assertEq(issue.value2, bytes32(uint256(10)));
    }

    function test_NegatedRangeOrderedBounds_NoIssue() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Constraint memory c = arg(0).addOp(OpCode.BETWEEN | OpCode.NOT, abi.encodePacked(uint256(10), uint256(100)));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 0);
    }
}

contract SetContradictionTest is PolicyValidatorTest {
    function test_EmptyIntersection_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        uint256[] memory set1 = new uint256[](2);
        set1[0] = 1;
        set1[1] = 2;
        uint256[] memory set2 = new uint256[](2);
        set2[0] = 3;
        set2[1] = 4;

        Constraint memory c = arg(0).isIn(set1).isIn(set2);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.EMPTY_SET_INTERSECTION);
        assertEq(issue.severity, IssueSeverity.Error);
    }

    function test_FullyExcluded_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        uint256[] memory set = new uint256[](2);
        set[0] = 1;
        set[1] = 2;

        Constraint memory c = arg(0).isIn(set).neq(uint256(1)).neq(uint256(2));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.SET_FULLY_EXCLUDED);
        assertEq(issue.severity, IssueSeverity.Error);
    }

    function test_FullyExcludedByManyNeqHoles_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        uint256[] memory set = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            set[i] = i + 1;
        }

        Constraint memory c = arg(0).isIn(set);
        for (uint256 i = 0; i < 10; ++i) {
            c = c.neq(i + 1);
        }

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.SET_FULLY_EXCLUDED);
    }

    function test_FullyExcludedByLargeNotInSet_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        uint256[] memory set = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            set[i] = i + 1;
        }

        Constraint memory c = arg(0).isIn(set).notIn(set);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.SET_FULLY_EXCLUDED);
    }

    function test_IntersectionPreserved_NoReduction() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        uint256[] memory set1 = new uint256[](3);
        set1[0] = 1;
        set1[1] = 2;
        set1[2] = 3;
        uint256[] memory set2 = new uint256[](3);
        set2[0] = 2;
        set2[1] = 3;
        set2[2] = 4;
        uint256[] memory notInSet = new uint256[](1);
        notInSet[0] = 4;
        Constraint memory c = arg(0).isIn(set1).isIn(set2).notIn(notInSet);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.SET_REDUCTION);
    }

    function test_ManyReductions_NoOverflow() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        // A large isIn/notIn overlap emits one SET_REDUCTION per element — far more issues than the
        // per-operator capacity estimate, so the issue buffer must grow rather than overflow.
        uint256 count = 64;
        uint256[] memory set = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            set[i] = i + 1;
        }
        Constraint memory c = arg(0).isIn(set).notIn(set);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        // Must not revert with Panic(0x32); every reduction is returned, none truncated.
        Issue[] memory issues = PolicyValidator.validate(data);

        uint256 reductions;
        for (uint256 i = 0; i < issues.length; ++i) {
            if (issues[i].code == IssueCode.SET_REDUCTION) ++reductions;
        }
        assertEq(reductions, count);
    }
}

contract BitmaskRedundancyTest is PolicyValidatorTest {
    function test_AllAll_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Constraint memory c = arg(0).bitmaskAll(0xF).bitmaskAll(0x3);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.REDUNDANT_BITMASK);
        assertEq(issue.severity, IssueSeverity.Warning);
        assertEq(issue.value1, bytes32(uint256(0x3)));
        assertEq(issue.value2, bytes32(uint256(0xF)));
    }

    function test_NoneNone_Value2Correct() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Constraint memory c = arg(0).bitmaskNone(0xF).bitmaskNone(0x3);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.REDUNDANT_BITMASK);
        assertEq(uint256(issue.value2), 0xF);
    }
}

contract LengthContradictionTest is PolicyValidatorTest {
    function test_BetweenDecomposition_ImpossibleRange() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.string_()).build();

        // lengthBetween(10, 20).lengthGt(30)
        Constraint memory c = arg(0).lengthBetween(uint256(10), uint256(20)).lengthGt(uint256(30));

        PolicyData memory data = _createPolicyData("foo(string)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.IMPOSSIBLE_LENGTH_RANGE);
    }

    function test_EqNegation_Contradiction() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.string_()).build();
        Constraint memory c = arg(0).lengthEq(10);
        c.operators = _appendOp(c.operators, OpCode.LENGTH_EQ | OpCode.NOT, abi.encode(uint256(10)));

        PolicyData memory data = _createPolicyData("foo(string)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.LENGTH_EQ_NEQ_CONTRADICTION);
        assertEq(issue.severity, IssueSeverity.Error);
    }

    function test_EqRedundancy_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.string_()).build();
        Constraint memory c = arg(0).lengthEq(uint256(10)).lengthGte(uint256(5));

        PolicyData memory data = _createPolicyData("foo(string)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.REDUNDANT_LENGTH_BOUND);
        assertEq(issue.value1, bytes32(uint256(5)));
        assertEq(issue.value2, bytes32(uint256(10)));
    }
}

contract SetOrderingTest is PolicyValidatorTest {
    PolicyValidatorHarness harness;

    function setUp() public {
        harness = new PolicyValidatorHarness();
    }

    function test_SetIntersection_PreservesOriginalOrdering() public view {
        // We use unsorted sets in the harness to verify that PolicyValidator
        // preserves the ordering of the original set (set1) during intersection.

        // set1: [2, 1, 3]
        uint256[] memory set1 = new uint256[](3);
        set1[0] = 2;
        set1[1] = 1;
        set1[2] = 3;

        // set2: [3, 2, 4]
        uint256[] memory set2 = new uint256[](3);
        set2[0] = 3;
        set2[1] = 2;
        set2[2] = 4;

        // Intersection should be [2, 3] because it preserves set1's relative order.
        uint256[] memory intersection = harness.checkSetIntersection(set1, set2);

        assertEq(intersection.length, 2, "Intersection length mismatch");
        assertEq(intersection[0], 2, "First element should be 2 (from set1 order)");
        assertEq(intersection[1], 3, "Second element should be 3 (from set1 order)");
    }
}

contract UnsortedInSetTest is PolicyValidatorTest {
    function test_UnsortedInSet_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // Manually construct a constraint with an unsorted IN set.
        Constraint memory c = arg(0);
        bytes[] memory ops = new bytes[](1);
        // opCode(IN) || unsorted payload: [3, 1, 2] as 32-byte words.
        ops[0] = abi.encodePacked(OpCode.IN, bytes32(uint256(3)), bytes32(uint256(1)), bytes32(uint256(2)));
        c.operators = ops;

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _assertIssue(issues, IssueCode.UNSORTED_IN_SET);
        assertEq(issue.severity, IssueSeverity.Error);
        assertEq(issue.category, IssueCategory.Contradiction);
    }

    function test_SortedInSet_NoError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        uint256[] memory set = new uint256[](3);
        set[0] = 1;
        set[1] = 2;
        set[2] = 3;
        Constraint memory c = arg(0).isIn(set);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.UNSORTED_IN_SET);
    }

    function test_DuplicateInSet_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // Manually construct a constraint with duplicates in IN set.
        Constraint memory c = arg(0);
        bytes[] memory ops = new bytes[](1);
        ops[0] = abi.encodePacked(OpCode.IN, bytes32(uint256(1)), bytes32(uint256(1)), bytes32(uint256(2)));
        c.operators = ops;

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.UNSORTED_IN_SET);
    }
}

contract EmptyGroupTest is PolicyValidatorTest {
    function test_EmptyGroup_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // Create PolicyData with one empty group.
        Constraint[][] memory groups = new Constraint[][](1);
        groups[0] = new Constraint[](0);

        PolicyData memory data = PolicyData({
            isSelectorless: false, selector: bytes4(keccak256("foo(uint256)")), descriptor: desc, groups: groups
        });
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.EMPTY_GROUP);
        assertEq(issues[0].severity, IssueSeverity.Error);
        assertEq(issues[0].category, IssueCategory.Vacuity);
        assertEq(issues[0].groupIndex, 0);
    }

    function test_MultipleEmptyGroups_ReturnsMultipleErrors() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // Create PolicyData with two empty groups.
        Constraint[][] memory groups = new Constraint[][](2);
        groups[0] = new Constraint[](0);
        groups[1] = new Constraint[](0);

        PolicyData memory data = PolicyData({
            isSelectorless: false, selector: bytes4(keccak256("foo(uint256)")), descriptor: desc, groups: groups
        });
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 2);
        assertEq(issues[0].code, IssueCode.EMPTY_GROUP);
        assertEq(issues[0].groupIndex, 0);
        assertEq(issues[1].code, IssueCode.EMPTY_GROUP);
        assertEq(issues[1].groupIndex, 1);
    }
}

contract UnnavigablePathTest is PolicyValidatorTest {
    function test_ArgIndexOutOfBounds_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(2).eq(uint256(1));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].severity, IssueSeverity.Error);
        assertEq(issues[0].category, IssueCategory.TypeMismatch);
        assertEq(issues[0].code, IssueCode.UNNAVIGABLE_PATH);
        assertEq(issues[0].groupIndex, 0);
        assertEq(issues[0].constraintIndex, 0);
    }

    function test_TupleFieldOutOfBounds_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.tuple_(TypeDesc.uint256_())).build();

        Constraint memory c = arg(0, 5).eq(uint256(1));

        PolicyData memory data = _createPolicyData("foo((uint256))", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.UNNAVIGABLE_PATH);
    }

    function test_StaticArrayIndexOutOfBounds_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.uint256_(), 3)).build();

        Constraint memory c = arg(0, 3).eq(uint256(1));

        PolicyData memory data = _createPolicyData("foo(uint256[3])", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.UNNAVIGABLE_PATH);
    }

    function test_DescentIntoElementary_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint memory c = arg(0, 0).eq(uint256(1));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 1);
        assertEq(issues[0].code, IssueCode.UNNAVIGABLE_PATH);
    }

    function test_OtherIssuesSurviveUnnavigablePath() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        Constraint[] memory constraints = new Constraint[](2);
        constraints[0] = arg(0).lengthEq(5);
        constraints[1] = arg(2).eq(uint256(1));

        PolicyData memory data = _createPolicyDataMulti("foo(uint256)", desc, constraints);
        Issue[] memory issues = PolicyValidator.validate(data);

        assertEq(issues.length, 2);
        _assertIssue(issues, IssueCode.LENGTH_ON_STATIC);
        _assertIssue(issues, IssueCode.UNNAVIGABLE_PATH);
    }
}

contract NestedQuantifierTest is PolicyValidatorTest {
    function test_TwoQuantifiers_ReturnsError() public pure {
        bytes memory desc =
            DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.array_(TypeDesc.uint256_()))).build();

        Constraint memory c = arg(0, Path.ALL, Path.ALL).eq(uint256(1));

        Issue[] memory issues = PolicyValidator.validate(_createPolicyData("foo(uint256[][])", desc, c));

        assertEq(issues.length, 1);
        assertEq(issues[0].severity, IssueSeverity.Error);
        assertEq(issues[0].category, IssueCategory.TypeMismatch);
        assertEq(issues[0].code, IssueCode.NESTED_QUANTIFIER);
        assertEq(issues[0].groupIndex, 0);
        assertEq(issues[0].constraintIndex, 0);
    }

    function test_SingleQuantifier_ReturnsNoIssue() public pure {
        bytes memory desc =
            DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.array_(TypeDesc.uint256_()))).build();

        Constraint memory c = arg(0, 0, Path.ALL).eq(uint256(1));

        Issue[] memory issues = PolicyValidator.validate(_createPolicyData("foo(uint256[][])", desc, c));
        _assertNoIssue(issues, IssueCode.NESTED_QUANTIFIER);
    }
}

contract QuantifierOverStaticLimitTest is PolicyValidatorTest {
    /// @dev Builds policy data quantifying over a static array of `length` elements.
    function _quantifiedOverStatic(uint16 length) private pure returns (PolicyData memory) {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.uint256_(), length)).build();
        return _createPolicyData("foo(uint256[])", desc, arg(0, Path.ALL).eq(uint256(1)));
    }

    function test_BeyondLimit_ReturnsError() public pure {
        Issue[] memory issues =
            PolicyValidator.validate(_quantifiedOverStatic(uint16(PF.MAX_QUANTIFIED_ARRAY_LENGTH) + 1));

        Issue memory issue = _assertIssue(issues, IssueCode.QUANTIFIER_OVER_STATIC_LIMIT);
        assertEq(issue.severity, IssueSeverity.Error);
        assertEq(issue.category, IssueCategory.Compatibility);
        assertEq(issue.value1, bytes32(PF.MAX_QUANTIFIED_ARRAY_LENGTH + 1));
        assertEq(issue.value2, bytes32(PF.MAX_QUANTIFIED_ARRAY_LENGTH));
    }

    function test_AtLimit_ReturnsNoIssue() public pure {
        Issue[] memory issues = PolicyValidator.validate(_quantifiedOverStatic(uint16(PF.MAX_QUANTIFIED_ARRAY_LENGTH)));
        _assertNoIssue(issues, IssueCode.QUANTIFIER_OVER_STATIC_LIMIT);
    }
}

contract MalformedDescriptorTest is PolicyValidatorTest {
    function test_RevertWhen_UnknownTypeCode() public {
        bytes memory desc = bytes.concat(hex"0201", bytes1(TypeCode.TUPLE + 1));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, arg(0).eq(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnknownTypeCode.selector, TypeCode.TUPLE + 1));
        PolicyValidator.validate(data);
    }

    function test_RevertWhen_TrailingDescriptorBytes() public {
        // One declared param, two encoded address nodes.
        bytes memory desc = hex"02014141";

        PolicyData memory data = _createPolicyData("foo(address)", desc, arg(0).eq(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(Descriptor.ParamCountMismatch.selector, 1, 2));
        PolicyValidator.validate(data);
    }
}

contract HintMismatchTest is PolicyValidatorTest {
    /// @dev A single-argument descriptor for `foo(uint256)`.
    function _desc() private pure returns (bytes memory) {
        return DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
    }

    /// @dev Attaches `hint` to a constraint on the first argument.
    function _withHint(bytes memory hint) private pure returns (PolicyData memory) {
        Constraint memory c = arg(0).eq(uint256(1));
        c.hint = hint;
        return _createPolicyData("foo(uint256)", _desc(), c);
    }

    function test_MatchingHint_ReturnsNoIssue() public pure {
        Issue[] memory issues = PolicyValidator.validate(_withHint(hex"0000000000000020"));
        _assertNoIssue(issues, IssueCode.HINT_MISMATCH);
    }

    function test_AbsentHint_ReturnsNoIssue() public pure {
        Issue[] memory issues =
            PolicyValidator.validate(_createPolicyData("foo(uint256)", _desc(), arg(0).eq(uint256(1))));
        _assertNoIssue(issues, IssueCode.HINT_MISMATCH);
    }

    function test_DivergentTargetDelta_ReturnsError() public pure {
        Issue[] memory issues = PolicyValidator.validate(_withHint(hex"0000000020000020"));

        Issue memory issue = _assertIssue(issues, IssueCode.HINT_MISMATCH);
        assertEq(issue.severity, IssueSeverity.Error);
        assertEq(issue.category, IssueCategory.TypeMismatch);
        assertEq(issue.groupIndex, 0);
        assertEq(issue.constraintIndex, 0);
    }

    function test_SpuriousHop_ReturnsError() public pure {
        _assertIssue(
            PolicyValidator.validate(_withHint(hex"0100000000ffff000000000000000020")), IssueCode.HINT_MISMATCH
        );
    }

    function test_UnnavigablePath_ReportsPathAlone() public pure {
        // Compilation is undefined for a path the descriptor rejects, so no hint comparison runs.
        Constraint memory c = arg(3).eq(uint256(1));
        c.hint = hex"0000000000000020";

        Issue[] memory issues = PolicyValidator.validate(_createPolicyData("foo(uint256)", _desc(), c));

        _assertIssue(issues, IssueCode.UNNAVIGABLE_PATH);
        _assertNoIssue(issues, IssueCode.HINT_MISMATCH);
    }

    function test_ContextConstraintHintIgnored() public pure {
        Constraint memory c = msgSender().eq(address(1));
        c.hint = hex"0000000000000020";

        Issue[] memory issues = PolicyValidator.validate(_createPolicyData("foo(uint256)", _desc(), c));
        _assertNoIssue(issues, IssueCode.HINT_MISMATCH);
    }
}

/*//////////////////////////////////////////////////////////////////////////
                             ISSUE PROVENANCE
//////////////////////////////////////////////////////////////////////////*/

contract IssueProvenanceTest is PolicyValidatorTest {
    /// @dev Two uint256 parameters, so the reported constraint index differs from the group index.
    function _twoArgs() private pure returns (bytes memory) {
        return DescriptorBuilder.create().add(TypeDesc.uint256_()).add(TypeDesc.uint256_()).build();
    }

    /// @dev Places the constraint under test at index 1, behind a constraint that raises nothing.
    function _atIndexOne(Constraint memory c) private pure returns (Issue[] memory) {
        Constraint[] memory constraints = new Constraint[](2);
        constraints[0] = arg(0).eq(uint256(42));
        constraints[1] = c;
        return PolicyValidator.validate(_createPolicyDataMulti("foo(uint256,uint256)", _twoArgs(), constraints));
    }

    function _assertAtIndexOne(Issue[] memory issues, bytes32 code) private pure returns (Issue memory) {
        Issue memory issue = _assertIssue(issues, code);
        assertEq(issue.groupIndex, 0);
        assertEq(issue.constraintIndex, 1);
        return issue;
    }

    function test_BitmaskContradictionOnAll() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).bitmaskNone(0xF).bitmaskAll(0x3)), IssueCode.BITMASK_CONTRADICTION);
        assertEq(issue.value1, bytes32(uint256(0x3)));
        assertEq(issue.value2, bytes32(uint256(0xF)));
    }

    function test_BitmaskContradictionOnNone() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).bitmaskAll(0xF).bitmaskNone(0x3)), IssueCode.BITMASK_CONTRADICTION);
        assertEq(issue.value1, bytes32(uint256(0x3)));
        assertEq(issue.value2, bytes32(uint256(0xF)));
    }

    function test_BitmaskAnyImpossible() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).bitmaskNone(0xF).bitmaskAny(0x3)), IssueCode.BITMASK_ANY_IMPOSSIBLE);
        assertEq(issue.value1, bytes32(uint256(0x3)));
        assertEq(issue.value2, bytes32(uint256(0xF)));
    }

    function test_RedundantBitmaskOnNone() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).bitmaskNone(0xF).bitmaskNone(0x3)), IssueCode.REDUNDANT_BITMASK);
        assertEq(issue.value1, bytes32(uint256(0x3)));
        assertEq(issue.value2, bytes32(uint256(0xF)));
    }

    function test_RedundantBitmaskOnAny() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).bitmaskAll(0xF).bitmaskAny(0x3)), IssueCode.REDUNDANT_BITMASK);
        assertEq(issue.value1, bytes32(uint256(0x3)));
        assertEq(issue.value2, bytes32(uint256(0xF)));
    }

    function test_BoundsExcludeEquality() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).eq(uint256(5)).gt(uint256(10))), IssueCode.BOUNDS_EXCLUDE_EQUALITY);
        assertEq(issue.value1, bytes32(uint256(5)));
        assertEq(issue.value2, bytes32(uint256(10)));
    }

    function test_RedundantBound() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).eq(uint256(10)).gte(uint256(5))), IssueCode.REDUNDANT_BOUND);
        assertEq(issue.value1, bytes32(uint256(5)));
        assertEq(issue.value2, bytes32(uint256(10)));
    }

    function test_DominatedLowerBoundRedundant() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).gte(uint256(5)).gte(uint256(3))), IssueCode.DOMINATED_BOUND);
        assertEq(issue.value1, bytes32(uint256(3)));
    }

    function test_DominatedLowerBoundStrictlyBetter() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).gte(uint256(3)).gte(uint256(5))), IssueCode.DOMINATED_BOUND);
        assertEq(issue.value1, bytes32(uint256(3)));
    }

    function test_DominatedUpperBoundRedundant() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).lte(uint256(5)).lte(uint256(10))), IssueCode.DOMINATED_BOUND);
        assertEq(issue.value1, bytes32(uint256(10)));
    }

    function test_DominatedUpperBoundStrictlyBetter() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).lte(uint256(10)).lte(uint256(5))), IssueCode.DOMINATED_BOUND);
        assertEq(issue.value1, bytes32(uint256(10)));
    }

    function _set(uint256 a, uint256 b) private pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = a;
        values[1] = b;
    }

    function test_EqNeqContradiction() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).eq(uint256(42)).neq(uint256(42))), IssueCode.EQ_NEQ_CONTRADICTION);
    }

    function test_DuplicateConstraint() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).eq(uint256(42)).eq(uint256(42))), IssueCode.DUPLICATE_CONSTRAINT);
    }

    function test_SetExcludesEquality() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).eq(uint256(1)).notIn(_set(1, 2))), IssueCode.SET_EXCLUDES_EQUALITY);
    }

    function test_EmptySetIntersection() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).isIn(_set(1, 2)).isIn(_set(3, 4))), IssueCode.EMPTY_SET_INTERSECTION);
    }

    function test_SetFullyExcluded() public pure {
        _assertAtIndexOne(
            _atIndexOne(arg(1).isIn(_set(1, 2)).neq(uint256(1)).neq(uint256(2))), IssueCode.SET_FULLY_EXCLUDED
        );
    }

    function test_SetPartiallyExcluded() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).isIn(_set(1, 2)).neq(uint256(1))), IssueCode.SET_PARTIALLY_EXCLUDED);
    }

    function test_SetRedundancy() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).isIn(_set(1, 2)).isIn(_set(2, 3))), IssueCode.SET_REDUNDANCY);
    }

    function test_SetReduction() public pure {
        Issue[] memory issues = _atIndexOne(arg(1).isIn(_set(1, 2)).notIn(_set(1, 3)));
        _assertAtIndexOne(issues, IssueCode.SET_REDUCTION);
        _assertAtIndexOne(issues, IssueCode.SET_PARTIALLY_EXCLUDED);
    }

    /// @dev Two uint8 parameters, so a set member above the type domain is out of physical bounds.
    function _atIndexOneNarrow(Constraint memory c) private pure returns (Issue[] memory) {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).add(TypeDesc.uintN_(8)).build();
        Constraint[] memory constraints = new Constraint[](2);
        constraints[0] = arg(0).eq(uint256(1));
        constraints[1] = c;
        return PolicyValidator.validate(_createPolicyDataMulti("foo(uint8,uint8)", desc, constraints));
    }

    function test_BoundsExcludeEqualityAboveUpper() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).eq(uint256(15)).lt(uint256(10))), IssueCode.BOUNDS_EXCLUDE_EQUALITY);
        assertEq(issue.value1, bytes32(uint256(15)));
        assertEq(issue.value2, bytes32(uint256(10)));
    }

    function test_RedundantUpperBound() public pure {
        Issue memory issue =
            _assertAtIndexOne(_atIndexOne(arg(1).eq(uint256(10)).lte(uint256(20))), IssueCode.REDUNDANT_BOUND);
        assertEq(issue.value1, bytes32(uint256(20)));
        assertEq(issue.value2, bytes32(uint256(10)));
    }

    function test_EqNeqContradictionEqAfterNeq() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).neq(uint256(42)).eq(uint256(42))), IssueCode.EQ_NEQ_CONTRADICTION);
    }

    function test_SetPartiallyExcludedAfterNotIn() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).neq(uint256(1)).isIn(_set(1, 2))), IssueCode.SET_PARTIALLY_EXCLUDED);
    }

    function test_OutOfPhysicalBoundsInSet() public pure {
        _assertAtIndexOne(_atIndexOneNarrow(arg(1).isIn(_set(1, 256))), IssueCode.OUT_OF_PHYSICAL_BOUNDS);
    }

    /// @dev Two int256 parameters, so bound comparisons take the signed branch.
    function _atIndexOneSigned(Constraint memory c) private pure returns (Issue[] memory) {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.int256_()).add(TypeDesc.int256_()).build();
        Constraint[] memory constraints = new Constraint[](2);
        constraints[0] = arg(0).eq(int256(1));
        constraints[1] = c;
        return PolicyValidator.validate(_createPolicyDataMulti("foo(int256,int256)", desc, constraints));
    }

    // An equality sitting exactly on an exclusive bound is excluded; on an inclusive bound it is
    // merely redundant. The pair pins the boundary direction of the signed-aware comparisons.

    function test_EqOnExclusiveUpperIsExcluded() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).eq(uint256(10)).lt(uint256(10))), IssueCode.BOUNDS_EXCLUDE_EQUALITY);
    }

    function test_EqOnInclusiveUpperIsRedundant() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).eq(uint256(10)).lte(uint256(10))), IssueCode.REDUNDANT_BOUND);
    }

    function test_EqOnExclusiveLowerIsExcluded() public pure {
        _assertAtIndexOne(_atIndexOne(arg(1).eq(uint256(10)).gt(uint256(10))), IssueCode.BOUNDS_EXCLUDE_EQUALITY);
    }

    function test_SignedEqOnExclusiveUpperIsExcluded() public pure {
        _assertAtIndexOne(_atIndexOneSigned(arg(1).eq(int256(-10)).lt(int256(-10))), IssueCode.BOUNDS_EXCLUDE_EQUALITY);
    }

    function test_SignedEqOnInclusiveUpperIsRedundant() public pure {
        _assertAtIndexOne(_atIndexOneSigned(arg(1).eq(int256(-10)).lte(int256(-10))), IssueCode.REDUNDANT_BOUND);
    }

    function test_SignedEqOnExclusiveLowerIsExcluded() public pure {
        _assertAtIndexOne(_atIndexOneSigned(arg(1).eq(int256(-10)).gt(int256(-10))), IssueCode.BOUNDS_EXCLUDE_EQUALITY);
    }

    function test_SignedEqAboveExclusiveUpperIsExcluded() public pure {
        _assertAtIndexOne(_atIndexOneSigned(arg(1).eq(int256(-5)).lt(int256(-10))), IssueCode.BOUNDS_EXCLUDE_EQUALITY);
    }
}

/*//////////////////////////////////////////////////////////////////////////
                            DOMAIN UPDATE EDGES
//////////////////////////////////////////////////////////////////////////*/

contract DomainUpdateEdgeTest is PolicyValidatorTest {
    function _uint256Arg(Constraint memory c) private pure returns (Issue[] memory) {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        return PolicyValidator.validate(_createPolicyData("foo(uint256)", desc, c));
    }

    function _uint8Arg(Constraint memory c) private pure returns (Issue[] memory) {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();
        return PolicyValidator.validate(_createPolicyData("foo(uint8)", desc, c));
    }

    function _int8Arg(Constraint memory c) private pure returns (Issue[] memory) {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.intN_(8)).build();
        return PolicyValidator.validate(_createPolicyData("foo(int8)", desc, c));
    }

    function _set(uint256 a, uint256 b) private pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = a;
        values[1] = b;
    }

    // A neq only contradicts an equality that is actually recorded and actually equal.

    function test_NeqWithoutEqualityIsNotContradiction() public pure {
        _assertNoIssue(_uint256Arg(arg(0).neq(uint256(0))), IssueCode.EQ_NEQ_CONTRADICTION);
    }

    function test_NeqAboveEqualityIsNotContradiction() public pure {
        _assertNoIssue(_uint256Arg(arg(0).eq(uint256(5)).neq(uint256(10))), IssueCode.EQ_NEQ_CONTRADICTION);
    }

    function test_NeqBelowEqualityIsNotContradiction() public pure {
        _assertNoIssue(_uint256Arg(arg(0).eq(uint256(10)).neq(uint256(5))), IssueCode.EQ_NEQ_CONTRADICTION);
    }

    function test_DistinctNeqValuesAreTrackedSeparately() public pure {
        // The second hole must be recorded on its own; a later eq on it is a contradiction.
        _assertIssue(
            _uint256Arg(arg(0).neq(uint256(10)).neq(uint256(5)).eq(uint256(5))), IssueCode.EQ_NEQ_CONTRADICTION
        );
    }

    // Vacuity is reported only for the bound that actually sits on the type's limit.

    function test_LteAtDomainMinIsNotVacuousGte() public pure {
        _assertNoIssue(_uint256Arg(arg(0).lte(uint256(0))), IssueCode.VACUOUS_GTE);
    }

    function test_GteBelowDomainMinIsNotVacuousGte() public pure {
        _assertNoIssue(_int8Arg(arg(0).gte(int256(-200))), IssueCode.VACUOUS_GTE);
    }

    function test_LteAboveDomainMaxIsNotVacuousLte() public pure {
        _assertNoIssue(_uint8Arg(arg(0).lte(uint256(256))), IssueCode.VACUOUS_LTE);
    }

    // A repeated equality is a conflict regardless of which value came first.

    function test_DescendingConflictingEquality() public pure {
        _assertIssue(_uint256Arg(arg(0).eq(uint256(10)).eq(uint256(5))), IssueCode.CONFLICTING_EQUALITY);
    }

    function test_LaterEqualityRecheckedAgainstUpperBound() public pure {
        _assertIssue(_uint256Arg(arg(0).lt(uint256(7)).eq(uint256(10)).eq(uint256(5))), IssueCode.REDUNDANT_BOUND);
    }

    function test_AscendingLaterEqualityRecheckedAgainstUpperBound() public pure {
        _assertIssue(
            _uint256Arg(arg(0).lt(uint256(7)).eq(uint256(5)).eq(uint256(10))), IssueCode.BOUNDS_EXCLUDE_EQUALITY
        );
    }

    // Bitmask accumulation must union, so a later contradicting mask still sees earlier bits.

    function test_RepeatedAllMaskStaysAccumulated() public pure {
        _assertIssue(
            _uint256Arg(arg(0).bitmaskAll(0x3).bitmaskAll(0x3).bitmaskNone(0x3)), IssueCode.BITMASK_CONTRADICTION
        );
    }

    function test_RepeatedNoneMaskStaysAccumulated() public pure {
        _assertIssue(
            _uint256Arg(arg(0).bitmaskNone(0x3).bitmaskNone(0x3).bitmaskAll(0x3)), IssueCode.BITMASK_CONTRADICTION
        );
    }

    function test_EmptyAnyMaskIsNotImpossible() public pure {
        _assertNoIssue(_uint256Arg(arg(0).bitmaskAny(0)), IssueCode.BITMASK_ANY_IMPOSSIBLE);
    }

    // A hole only forbids the set member it actually equals.

    function test_UnrelatedHoleDoesNotExcludeSet() public pure {
        Issue[] memory issues = _uint256Arg(arg(0).isIn(_set(1, 2)).neq(uint256(3)));
        _assertNoIssue(issues, IssueCode.SET_FULLY_EXCLUDED);
        _assertNoIssue(issues, IssueCode.SET_PARTIALLY_EXCLUDED);
    }

    function _set3(uint256 a, uint256 b, uint256 c) private pure returns (uint256[] memory values) {
        values = new uint256[](3);
        values[0] = a;
        values[1] = b;
        values[2] = c;
    }

    // An equality survives a set only if a member actually equals it.

    function test_SetAboveEqualityStillExcludesIt() public pure {
        _assertIssue(_uint256Arg(arg(0).eq(uint256(1)).isIn(_set(2, 3))), IssueCode.SET_EXCLUDES_EQUALITY);
    }

    function test_DisjointSetsIntersectToNothing() public pure {
        _assertIssue(_uint256Arg(arg(0).isIn(_set(5, 6)).isIn(_set(1, 2))), IssueCode.EMPTY_SET_INTERSECTION);
    }

    // Narrowing on either side is redundancy, so each side is reported on its own.

    function test_IntersectionNarrowerThanIncomingSet() public pure {
        _assertIssue(_uint256Arg(arg(0).isIn(_set(1, 2)).isIn(_set3(1, 2, 3))), IssueCode.SET_REDUNDANCY);
    }

    function test_IntersectionNarrowerThanExistingSet() public pure {
        _assertIssue(_uint256Arg(arg(0).isIn(_set3(1, 2, 3)).isIn(_set(1, 2))), IssueCode.SET_REDUNDANCY);
    }

    function test_RepeatedIncomingMemberCountedOnce() public pure {
        _assertIssue(_uint256Arg(arg(0).isIn(_set(1, 2)).isIn(_set(1, 1))), IssueCode.SET_REDUNDANCY);
    }
}

contract EqCtxTest is PolicyValidatorTest {
    /// @dev Validates a single EQ_CTX constraint against a one-parameter descriptor.
    function _validateEqCtx(
        bytes memory desc,
        string memory sig,
        Constraint memory c
    )
        private
        pure
        returns (Issue[] memory)
    {
        return PolicyValidator.validate(_createPolicyData(sig, desc, c));
    }

    /*/////////////////////////////////////////////////////////////////////////
                             COMPATIBLE PAIRINGS
    /////////////////////////////////////////////////////////////////////////*/

    function test_AddressTargetAddressProperty_NoIssues() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.address_()).build();
        Issue[] memory issues = _validateEqCtx(desc, "foo(address)", arg(0).eqCtx(PF.CTX_MSG_SENDER));
        assertEq(issues.length, 0);
    }

    function test_UintTargetUintProperty_NoIssues() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Issue[] memory issues = _validateEqCtx(desc, "foo(uint256)", arg(0).eqCtx(PF.CTX_BLOCK_TIMESTAMP));
        assertEq(issues.length, 0);
    }

    function test_NarrowUintTargetUintProperty_NoIssues() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(128)).build();
        Issue[] memory issues = _validateEqCtx(desc, "foo(uint128)", arg(0).eqCtx(PF.CTX_MSG_VALUE));
        assertEq(issues.length, 0);
    }

    function test_NegatedEqCtx_NoIssues() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.address_()).build();
        Issue[] memory issues = _validateEqCtx(desc, "foo(address)", arg(0).neqCtx(PF.CTX_MSG_SENDER));
        assertEq(issues.length, 0);
    }

    function test_ContextSubjectContextOperand_NoIssues() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Issue[] memory issues = _validateEqCtx(desc, "foo(uint256)", msgSender().eqCtx(PF.CTX_TX_ORIGIN));
        assertEq(issues.length, 0);
    }

    /*/////////////////////////////////////////////////////////////////////////
                             INCOMPATIBLE PAIRINGS
    /////////////////////////////////////////////////////////////////////////*/

    function test_UintTargetAddressProperty_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Issue[] memory issues = _validateEqCtx(desc, "foo(uint256)", arg(0).eqCtx(PF.CTX_MSG_SENDER));

        Issue memory issue = _assertIssue(issues, IssueCode.CONTEXT_TYPE_MISMATCH);
        assertEq(issue.severity, IssueSeverity.Error);
        assertEq(issue.category, IssueCategory.TypeMismatch);
    }

    function test_AddressTargetUintProperty_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.address_()).build();
        Issue[] memory issues = _validateEqCtx(desc, "foo(address)", arg(0).eqCtx(PF.CTX_MSG_VALUE));
        _assertIssue(issues, IssueCode.CONTEXT_TYPE_MISMATCH);
    }

    function test_SignedTarget_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.int256_()).build();
        Issue[] memory issues = _validateEqCtx(desc, "foo(int256)", arg(0).eqCtx(PF.CTX_MSG_VALUE));
        _assertIssue(issues, IssueCode.CONTEXT_TYPE_MISMATCH);
    }

    function test_Bytes32Target_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytes32_()).build();
        Issue[] memory issues = _validateEqCtx(desc, "foo(bytes32)", arg(0).eqCtx(PF.CTX_MSG_SENDER));
        _assertIssue(issues, IssueCode.CONTEXT_TYPE_MISMATCH);
    }

    function test_DynamicTarget_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.bytes_()).build();
        Issue[] memory issues = _validateEqCtx(desc, "foo(bytes)", arg(0).eqCtx(PF.CTX_MSG_SENDER));
        _assertIssue(issues, IssueCode.VALUE_OP_ON_DYNAMIC);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              OPERAND VALIDITY
    /////////////////////////////////////////////////////////////////////////*/

    function test_UnknownProperty_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        // The fluent method rejects the ID eagerly, so the raw escape hatch injects it.
        Constraint memory c = arg(0).addOp(OpCode.EQ_CTX, abi.encode(uint256(PF.CTX_MAX) + 1));
        Issue[] memory issues = _validateEqCtx(desc, "foo(uint256)", c);

        Issue memory issue = _assertIssue(issues, IssueCode.UNKNOWN_CONTEXT_PROPERTY);
        assertEq(issue.severity, IssueSeverity.Warning);
        // An unknown property has no declared type, so no pairing verdict exists.
        _assertNoIssue(issues, IssueCode.CONTEXT_TYPE_MISMATCH);
    }
}

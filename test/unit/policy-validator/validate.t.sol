// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyValidatorHarness } from "../../harnesses/PolicyValidatorHarness.sol";
import { PolicyValidatorTest } from "../PolicyValidator.t.sol";
import { Constraint, arg, msgSender } from "src/Constraint.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { IssueCode } from "src/IssueCode.sol";
import { OpCode } from "src/OpCode.sol";
import { PolicyData } from "src/PolicyCoder.sol";
import { PolicyValidator } from "src/PolicyValidator.sol";
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

        Issue memory issue = _findIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
        assertEq(issue.severity, IssueSeverity.Error);
        assertEq(issue.category, IssueCategory.Contradiction);
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

    function test_NegatedGT_Decomposition_ReturnsContradiction() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Constraint memory c = arg(0).gt(uint256(10));
        // NOT GT(10) is LTE(10). GT(10) and LTE(10) is impossible.
        c.operators = _appendOp(c.operators, OpCode.GT | OpCode.NOT, abi.encode(uint256(10)));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.IMPOSSIBLE_RANGE);
    }
}

contract ConflictingEqualityTest is PolicyValidatorTest {
    function test_MultipleEq_DifferentValues_ReturnsError() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // eq(5).eq(10) - impossible because value can't equal both 5 and 10
        Constraint memory c = arg(0).eq(uint256(5)).eq(uint256(10));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.CONFLICTING_EQUALITY);
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

        _assertIssue(issues, IssueCode.BOUNDS_EXCLUDE_EQUALITY);
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

        Issue memory issue = _findIssue(issues, IssueCode.DOMINATED_BOUND);
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

        Issue memory issue = _findIssue(issues, IssueCode.REDUNDANT_BOUND);
        assertEq(issue.severity, IssueSeverity.Warning);
    }

    function test_GtGteSameValue_NoWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        // gt(5).gte(5) - gte(5) is looser, should be ignored silently
        Constraint memory c = arg(0).gt(uint256(5)).gte(uint256(5));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertNoIssue(issues, IssueCode.DOMINATED_BOUND);
    }
}

contract DuplicateConstraintTest is PolicyValidatorTest {
    function test_DuplicateEq_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();

        // eq(42).eq(42) - duplicate operator
        Constraint memory c = arg(0).eq(uint256(42)).eq(uint256(42));

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _findIssue(issues, IssueCode.DUPLICATE_CONSTRAINT);
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

        Issue memory issue = _findIssue(issues, IssueCode.OUT_OF_PHYSICAL_BOUNDS);
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

        Issue memory issue = _findIssue(issues, IssueCode.IMPOSSIBLE_GT);
        assertEq(issue.severity, IssueSeverity.Error);
    }
}

contract VacuousConstraintTest is PolicyValidatorTest {
    function test_GteZero_ReturnsInfo() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();
        Constraint memory c = arg(0).gte(uint256(0));

        PolicyData memory data = _createPolicyData("foo(uint8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _findIssue(issues, IssueCode.VACUOUS_GTE);
        assertEq(issue.severity, IssueSeverity.Info);
        assertEq(issue.category, IssueCategory.Vacuity);
    }

    function test_LteMax_ReturnsInfo() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();
        Constraint memory c = arg(0).lte(uint256(255));

        PolicyData memory data = _createPolicyData("foo(uint8)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _findIssue(issues, IssueCode.VACUOUS_LTE);
        assertEq(issue.severity, IssueSeverity.Info);
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

        Issue memory issue = _findIssue(issues, IssueCode.EMPTY_SET_INTERSECTION);
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

        Issue memory issue = _findIssue(issues, IssueCode.SET_FULLY_EXCLUDED);
        assertEq(issue.severity, IssueSeverity.Error);
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
}

contract BitmaskRedundancyTest is PolicyValidatorTest {
    function test_AllAll_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Constraint memory c = arg(0).bitmaskAll(0xF).bitmaskAll(0x3);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _findIssue(issues, IssueCode.REDUNDANT_BITMASK);
        assertEq(issue.severity, IssueSeverity.Warning);
    }

    function test_NoneNone_Value2Correct() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        Constraint memory c = arg(0).bitmaskNone(0xF).bitmaskNone(0x3);

        PolicyData memory data = _createPolicyData("foo(uint256)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        Issue memory issue = _findIssue(issues, IssueCode.REDUNDANT_BITMASK);
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

        Issue memory issue = _findIssue(issues, IssueCode.LENGTH_EQ_NEQ_CONTRADICTION);
        assertEq(issue.severity, IssueSeverity.Error);
    }

    function test_EqRedundancy_ReturnsWarning() public pure {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.string_()).build();
        Constraint memory c = arg(0).lengthEq(uint256(10)).lengthGte(uint256(5));

        PolicyData memory data = _createPolicyData("foo(string)", desc, c);
        Issue[] memory issues = PolicyValidator.validate(data);

        _assertIssue(issues, IssueCode.REDUNDANT_LENGTH_BOUND);
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

        Issue memory issue = _findIssue(issues, IssueCode.UNSORTED_IN_SET);
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

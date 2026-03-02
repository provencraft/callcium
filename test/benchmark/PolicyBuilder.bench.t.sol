// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { PolicyBuilderHarness } from "test/harnesses/PolicyBuilderHarness.sol";

/// @dev Base contract for PolicyBuilder benchmarks parameterised by build mode.
abstract contract PolicyBuilderBench is Test {
    PolicyBuilderHarness internal harness;

    /// @dev Whether to use the validated build path.
    function _safe() internal pure virtual returns (bool);

    /// @dev Snapshot group label (e.g. "PolicyBuilder.build").
    function _label() internal pure virtual returns (string memory);

    function setUp() public {
        harness = new PolicyBuilderHarness();
    }

    // SIGNATURE COMPLEXITY

    function test_SimpleElementary() public {
        harness.simpleElementary(_safe());
        vm.snapshotGasLastCall(_label(), "simple_elementary");
    }

    function test_MultipleElementaryTypes() public {
        harness.multipleElementaryTypes(_safe());
        vm.snapshotGasLastCall(_label(), "multiple_elementary_types");
    }

    function test_SingleTuple() public {
        harness.singleTuple(_safe());
        vm.snapshotGasLastCall(_label(), "single_tuple");
    }

    function test_NestedTuple() public {
        harness.nestedTuple(_safe());
        vm.snapshotGasLastCall(_label(), "nested_tuple");
    }

    function test_ArrayTypes() public {
        harness.arrayTypes(_safe());
        vm.snapshotGasLastCall(_label(), "array_types");
    }

    function test_ComplexMixed() public {
        harness.complexMixed(_safe());
        vm.snapshotGasLastCall(_label(), "complex_mixed");
    }

    // CONSTRAINT COUNT

    function test_SingleConstraint() public {
        harness.singleConstraint(_safe());
        vm.snapshotGasLastCall(_label(), "single_constraint");
    }

    function test_FourConstraints() public {
        harness.fourConstraints(_safe());
        vm.snapshotGasLastCall(_label(), "four_constraints");
    }

    function test_EightConstraints() public {
        harness.eightConstraints(_safe());
        vm.snapshotGasLastCall(_label(), "eight_constraints");
    }

    function test_SixteenConstraints() public {
        harness.sixteenConstraints(_safe());
        vm.snapshotGasLastCall(_label(), "sixteen_constraints");
    }

    // GROUP COUNT

    function test_TwoGroups() public {
        harness.twoGroups(_safe());
        vm.snapshotGasLastCall(_label(), "two_groups");
    }

    function test_FourGroups() public {
        harness.fourGroups(_safe());
        vm.snapshotGasLastCall(_label(), "four_groups");
    }

    function test_EightGroups() public {
        harness.eightGroups(_safe());
        vm.snapshotGasLastCall(_label(), "eight_groups");
    }

    // PATH DEPTH

    function test_PathDepth1() public {
        harness.pathDepth1(_safe());
        vm.snapshotGasLastCall(_label(), "path_depth_1");
    }

    function test_PathDepth2() public {
        harness.pathDepth2(_safe());
        vm.snapshotGasLastCall(_label(), "path_depth_2");
    }

    function test_PathDepth3() public {
        harness.pathDepth3(_safe());
        vm.snapshotGasLastCall(_label(), "path_depth_3");
    }

    function test_PathDepth4() public {
        harness.pathDepth4(_safe());
        vm.snapshotGasLastCall(_label(), "path_depth_4");
    }

    // OPERATOR COMPLEXITY

    function test_SingleOperator() public {
        harness.singleOperator(_safe());
        vm.snapshotGasLastCall(_label(), "single_operator");
    }

    function test_ChainedOperators() public {
        harness.chainedOperators(_safe());
        vm.snapshotGasLastCall(_label(), "chained_operators");
    }

    function test_SetMembership() public {
        harness.setMembership(_safe());
        vm.snapshotGasLastCall(_label(), "set_membership");
    }

    // SCOPE

    function test_CalldataOnly() public {
        harness.calldataOnly(_safe());
        vm.snapshotGasLastCall(_label(), "calldata_only");
    }

    function test_ContextOnly() public {
        harness.contextOnly(_safe());
        vm.snapshotGasLastCall(_label(), "context_only");
    }

    function test_MixedScope() public {
        harness.mixedScope(_safe());
        vm.snapshotGasLastCall(_label(), "mixed_scope");
    }
}

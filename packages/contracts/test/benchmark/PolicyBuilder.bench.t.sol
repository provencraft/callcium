// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Policy } from "src/Policy.sol";
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

    /// @dev Snapshots the harness call just made and rejects a blob that is not well-formed, so a
    /// scenario that stops building what its name claims fails instead of recording a number.
    function _bench(bytes memory policy, string memory name) private {
        vm.snapshotGasLastCall(_label(), name);
        Policy.validate(policy);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SIGNATURE COMPLEXITY
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev The cheapest pipeline, and the baseline every section below reads against. Each series
    /// once carried its own copy of this scenario; those rows recorded the same number by
    /// construction and could not diverge from this one, so this is the only row that runs it.
    function test_SimpleElementary() public {
        _bench(harness.elementaryEq(_safe()), "simple_elementary");
    }

    function test_MultipleElementaryTypes() public {
        _bench(harness.multipleElementaryTypes(_safe()), "multiple_elementary_types");
    }

    function test_SingleTuple() public {
        _bench(harness.singleTuple(_safe()), "single_tuple");
    }

    function test_NestedTuple() public {
        _bench(harness.nestedTuple(_safe()), "nested_tuple");
    }

    function test_ArrayTypes() public {
        _bench(harness.arrayTypes(_safe()), "array_types");
    }

    function test_ComplexMixed() public {
        _bench(harness.complexMixed(_safe()), "complex_mixed");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                CONSTRAINT COUNT
    /////////////////////////////////////////////////////////////////////////*/

    function test_FourConstraints() public {
        _bench(harness.fourConstraints(_safe()), "four_constraints");
    }

    function test_EightConstraints() public {
        _bench(harness.eightConstraints(_safe()), "eight_constraints");
    }

    function test_SixteenConstraints() public {
        _bench(harness.sixteenConstraints(_safe()), "sixteen_constraints");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   GROUP COUNT
    /////////////////////////////////////////////////////////////////////////*/

    function test_TwoGroups() public {
        _bench(harness.twoGroups(_safe()), "two_groups");
    }

    function test_FourGroups() public {
        _bench(harness.fourGroups(_safe()), "four_groups");
    }

    function test_EightGroups() public {
        _bench(harness.eightGroups(_safe()), "eight_groups");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    PATH DEPTH
    /////////////////////////////////////////////////////////////////////////*/

    function test_PathDepth2() public {
        _bench(harness.pathDepth2(_safe()), "path_depth_2");
    }

    function test_PathDepth3() public {
        _bench(harness.pathDepth3(_safe()), "path_depth_3");
    }

    function test_PathDepth4() public {
        _bench(harness.pathDepth4(_safe()), "path_depth_4");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              OPERATOR COMPLEXITY
    /////////////////////////////////////////////////////////////////////////*/

    function test_ChainedOperators() public {
        _bench(harness.chainedOperators(_safe()), "chained_operators");
    }

    function test_SetMembership() public {
        _bench(harness.setMembership(_safe()), "set_membership");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                      SCOPE
    /////////////////////////////////////////////////////////////////////////*/

    function test_CalldataOnly() public {
        _bench(harness.calldataOnly(_safe()), "calldata_only");
    }

    function test_ContextOnly() public {
        _bench(harness.contextOnly(_safe()), "context_only");
    }

    function test_MixedScope() public {
        _bench(harness.mixedScope(_safe()), "mixed_scope");
    }
}

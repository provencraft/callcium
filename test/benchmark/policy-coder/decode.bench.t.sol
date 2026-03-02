// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyCoderBench } from "../PolicyCoder.bench.t.sol";

/// @dev Benchmarks for PolicyCoder.decode().
contract DecodeBench is PolicyCoderBench {
    /*/////////////////////////////////////////////////////////////////////////
                              SINGLE GROUP SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_SingleGroup1Rule() public {
        harness.decode(encodedSingleGroup1Rule);
        vm.snapshotGasLastCall("PolicyCoder.decode", "single_group_1rule");
    }

    function test_SingleGroup4Rules() public {
        harness.decode(encodedSingleGroup4Rules);
        vm.snapshotGasLastCall("PolicyCoder.decode", "single_group_4rules");
    }

    function test_SingleGroup8Rules() public {
        harness.decode(encodedSingleGroup8Rules);
        vm.snapshotGasLastCall("PolicyCoder.decode", "single_group_8rules");
    }

    function test_SingleGroup16Rules() public {
        harness.decode(encodedSingleGroup16Rules);
        vm.snapshotGasLastCall("PolicyCoder.decode", "single_group_16rules");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              MULTI-GROUP SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_TwoGroups() public {
        harness.decode(encodedTwoGroups);
        vm.snapshotGasLastCall("PolicyCoder.decode", "two_groups");
    }

    function test_FourGroups() public {
        harness.decode(encodedFourGroups);
        vm.snapshotGasLastCall("PolicyCoder.decode", "four_groups");
    }

    function test_EightGroups() public {
        harness.decode(encodedEightGroups);
        vm.snapshotGasLastCall("PolicyCoder.decode", "eight_groups");
    }

    /*/////////////////////////////////////////////////////////////////////////
                            LARGE GROUP COUNT
    /////////////////////////////////////////////////////////////////////////*/

    function test_Groups32() public {
        harness.decode(encodedGroups32);
        vm.snapshotGasLastCall("PolicyCoder.decode", "groups_32");
    }

    function test_Groups64() public {
        harness.decode(encodedGroups64);
        vm.snapshotGasLastCall("PolicyCoder.decode", "groups_64");
    }

    function test_Groups128() public {
        harness.decode(encodedGroups128);
        vm.snapshotGasLastCall("PolicyCoder.decode", "groups_128");
    }

    function test_Groups255() public {
        harness.decode(encodedGroups255);
        vm.snapshotGasLastCall("PolicyCoder.decode", "groups_255");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              CONTEXT SCOPE
    /////////////////////////////////////////////////////////////////////////*/

    function test_ContextOnly() public {
        harness.decode(encodedContextOnly);
        vm.snapshotGasLastCall("PolicyCoder.decode", "context_only");
    }

    function test_MixedScope() public {
        harness.decode(encodedMixedScope);
        vm.snapshotGasLastCall("PolicyCoder.decode", "mixed_scope");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              BOUNDARY
    /////////////////////////////////////////////////////////////////////////*/

    function test_MixedOpCodes() public {
        harness.decode(encodedMixedOpCodes);
        vm.snapshotGasLastCall("PolicyCoder.decode", "mixed_op_codes");
    }
}

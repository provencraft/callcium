// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyCoderBench } from "../PolicyCoder.bench.t.sol";

/// @dev Benchmarks for PolicyCoder.encode().
contract EncodeBench is PolicyCoderBench {
    /*/////////////////////////////////////////////////////////////////////////
                              SINGLE GROUP SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_SingleGroup1Rule() public {
        harness.encode(singleGroup1Rule, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "single_group_1rule");
    }

    function test_SingleGroup4Rules() public {
        harness.encode(singleGroup4Rules, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "single_group_4rules");
    }

    function test_SingleGroup8Rules() public {
        harness.encode(singleGroup8Rules, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "single_group_8rules");
    }

    function test_SingleGroup16Rules() public {
        harness.encode(singleGroup16Rules, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "single_group_16rules");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              MULTI-GROUP SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_TwoGroups() public {
        harness.encode(twoGroups, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "two_groups");
    }

    function test_FourGroups() public {
        harness.encode(fourGroups, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "four_groups");
    }

    function test_EightGroups() public {
        harness.encode(eightGroups, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "eight_groups");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              PATH DEPTH VARIATION
    /////////////////////////////////////////////////////////////////////////*/

    function test_PathDepth1() public {
        harness.encode(pathDepth1, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "path_depth_1");
    }

    function test_PathDepth2() public {
        harness.encode(pathDepth2, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "path_depth_2");
    }

    function test_PathDepth4() public {
        harness.encode(pathDepth4, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "path_depth_4");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              DATA SIZE VARIATION
    /////////////////////////////////////////////////////////////////////////*/

    function test_DataSize32() public {
        harness.encode(dataSize32, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "data_size_32");
    }

    function test_DataSize128() public {
        harness.encode(dataSize128, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "data_size_128");
    }

    function test_DataSize256() public {
        harness.encode(dataSize256, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "data_size_256");
    }

    function test_DataSize512() public {
        harness.encode(dataSize512, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "data_size_512");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SORTING STRESS TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_ReverseSortedRules() public {
        harness.encode(reverseSortedRules, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "reverse_sorted_rules");
    }

    function test_EqualKeyRules() public {
        harness.encode(equalKeyRules, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "equal_key_rules");
    }

    function test_IdenticalGroups() public {
        harness.encode(identicalGroups, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "identical_groups");
    }

    /*/////////////////////////////////////////////////////////////////////////
                            LARGE GROUP COUNT TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_Groups32() public {
        harness.encode(groups32, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "groups_32");
    }

    function test_Groups64() public {
        harness.encode(groups64, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "groups_64");
    }

    function test_Groups128() public {
        harness.encode(groups128, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "groups_128");
    }

    function test_Groups255() public {
        harness.encode(groups255, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "groups_255");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              CONTEXT SCOPE TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_ContextOnly() public {
        harness.encode(contextOnly, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "context_only");
    }

    function test_MixedScope() public {
        harness.encode(mixedScope, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "mixed_scope");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                DEEP PATH TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_PathDepth8() public {
        harness.encode(pathDepth8, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "path_depth_8");
    }

    function test_PathDepth16() public {
        harness.encode(pathDepth16, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "path_depth_16");
    }

    function test_LongCommonPrefix() public {
        harness.encode(longCommonPrefix, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "long_common_prefix");
    }

    /*/////////////////////////////////////////////////////////////////////////
                            LARGE PAYLOAD TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_DataSize1024() public {
        harness.encode(dataSize1024, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "data_size_1024");
    }

    function test_DataSize2048() public {
        harness.encode(dataSize2048, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "data_size_2048");
    }

    function test_DataSize4096() public {
        harness.encode(dataSize4096, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "data_size_4096");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              BOUNDARY TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_ManyRulesPerGroup() public {
        harness.encode(manyRulesPerGroup, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "many_rules_per_group");
    }

    function test_MixedOpCodes() public {
        harness.encode(mixedOpCodes, SELECTOR, DESCRIPTOR);
        vm.snapshotGasLastCall("PolicyCoder.encode", "mixed_op_codes");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyCoderBench } from "../PolicyCoder.bench.t.sol";

/// @dev Benchmarks for PolicyCoder.encode().
contract EncodeBench is PolicyCoderBench {
    /*/////////////////////////////////////////////////////////////////////////
                              SINGLE GROUP SCALING
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev One group, one rule, one 32-byte operand — the floor the path-depth and data-size
    /// series read against. Both once opened with their own copy of this policy, which encoded to
    /// the same blob shape and could not diverge from this row.
    function test_SingleGroup1Rule() public {
        _benchEncode(harness.encode(singleGroup1Rule, SELECTOR, descriptorBlob), "single_group_1rule");
    }

    function test_SingleGroup4Rules() public {
        _benchEncode(harness.encode(singleGroup4Rules, SELECTOR, descriptorBlob), "single_group_4rules");
    }

    function test_SingleGroup8Rules() public {
        _benchEncode(harness.encode(singleGroup8Rules, SELECTOR, descriptorBlob), "single_group_8rules");
    }

    function test_SingleGroup16Rules() public {
        _benchEncode(harness.encode(singleGroup16Rules, SELECTOR, descriptorBlob), "single_group_16rules");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              MULTI-GROUP SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_TwoGroups() public {
        _benchEncode(harness.encode(twoGroups, SELECTOR, descriptorBlob), "two_groups");
    }

    function test_FourGroups() public {
        _benchEncode(harness.encode(fourGroups, SELECTOR, descriptorBlob), "four_groups");
    }

    function test_EightGroups() public {
        _benchEncode(harness.encode(eightGroups, SELECTOR, descriptorBlob), "eight_groups");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              PATH DEPTH VARIATION
    /////////////////////////////////////////////////////////////////////////*/

    function test_PathDepth2() public {
        _benchEncode(harness.encode(pathDepth2, SELECTOR, descriptorBlob), "path_depth_2");
    }

    function test_PathDepth4() public {
        _benchEncode(harness.encode(pathDepth4, SELECTOR, descriptorBlob), "path_depth_4");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              DATA SIZE VARIATION
    /////////////////////////////////////////////////////////////////////////*/

    function test_DataSize128() public {
        _benchEncode(harness.encode(dataSize128, SELECTOR, descriptorBlob), "data_size_128");
    }

    function test_DataSize256() public {
        _benchEncode(harness.encode(dataSize256, SELECTOR, descriptorBlob), "data_size_256");
    }

    function test_DataSize512() public {
        _benchEncode(harness.encode(dataSize512, SELECTOR, descriptorBlob), "data_size_512");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SORTING STRESS
    /////////////////////////////////////////////////////////////////////////*/

    function test_ReverseSortedRules() public {
        _benchEncode(harness.encode(reverseSortedRules, SELECTOR, descriptorBlob), "reverse_sorted_rules");
    }

    function test_EqualKeyRules() public {
        _benchEncode(harness.encode(equalKeyRules, SELECTOR, descriptorBlob), "equal_key_rules");
    }

    function test_IdenticalGroups() public {
        _benchEncode(harness.encode(identicalGroups, SELECTOR, descriptorBlob), "identical_groups");
    }

    /*/////////////////////////////////////////////////////////////////////////
                            LARGE GROUP COUNT
    /////////////////////////////////////////////////////////////////////////*/

    function test_Groups32() public {
        _benchEncode(harness.encode(groups32, SELECTOR, descriptorBlob), "groups_32");
    }

    function test_Groups64() public {
        _benchEncode(harness.encode(groups64, SELECTOR, descriptorBlob), "groups_64");
    }

    function test_Groups128() public {
        _benchEncode(harness.encode(groups128, SELECTOR, descriptorBlob), "groups_128");
    }

    function test_Groups255() public {
        _benchEncode(harness.encode(groups255, SELECTOR, descriptorBlob), "groups_255");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              CONTEXT SCOPE
    /////////////////////////////////////////////////////////////////////////*/

    function test_ContextOnly() public {
        _benchEncode(harness.encode(contextOnly, SELECTOR, descriptorBlob), "context_only");
    }

    function test_MixedScope() public {
        _benchEncode(harness.encode(mixedScope, SELECTOR, descriptorBlob), "mixed_scope");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                DEEP PATH
    /////////////////////////////////////////////////////////////////////////*/

    function test_PathDepth8() public {
        _benchEncode(harness.encode(pathDepth8, SELECTOR, descriptorBlob), "path_depth_8");
    }

    function test_PathDepth16() public {
        _benchEncode(harness.encode(pathDepth16, SELECTOR, descriptorBlob), "path_depth_16");
    }

    function test_LongCommonPrefix() public {
        _benchEncode(harness.encode(longCommonPrefix, SELECTOR, descriptorBlob), "long_common_prefix");
    }

    /*/////////////////////////////////////////////////////////////////////////
                            LARGE PAYLOAD
    /////////////////////////////////////////////////////////////////////////*/

    function test_DataSize1024() public {
        _benchEncode(harness.encode(dataSize1024, SELECTOR, descriptorBlob), "data_size_1024");
    }

    function test_DataSize2048() public {
        _benchEncode(harness.encode(dataSize2048, SELECTOR, descriptorBlob), "data_size_2048");
    }

    function test_DataSize4096() public {
        _benchEncode(harness.encode(dataSize4096, SELECTOR, descriptorBlob), "data_size_4096");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              BOUNDARY
    /////////////////////////////////////////////////////////////////////////*/

    function test_ManyRulesPerGroup() public {
        _benchEncode(harness.encode(manyRulesPerGroup, SELECTOR, descriptorBlob), "many_rules_per_group");
    }

    function test_MixedOpCodes() public {
        _benchEncode(harness.encode(mixedOpCodes, SELECTOR, descriptorBlob), "mixed_op_codes");
    }
}

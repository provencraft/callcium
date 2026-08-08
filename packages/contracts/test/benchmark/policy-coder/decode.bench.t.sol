// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyCoderBench } from "../PolicyCoder.bench.t.sol";

/// @dev Benchmarks for PolicyCoder.decode(). Each case asserts the round trip returns as many
///      groups as its source fixture encoded, so a blob that stops decoding fails the benchmark.
contract DecodeBench is PolicyCoderBench {
    /*/////////////////////////////////////////////////////////////////////////
                              SINGLE GROUP SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_SingleGroup1Rule() public {
        _benchDecode(harness.decode(encodedSingleGroup1Rule), "single_group_1rule", singleGroup1Rule.length);
    }

    function test_SingleGroup4Rules() public {
        _benchDecode(harness.decode(encodedSingleGroup4Rules), "single_group_4rules", singleGroup4Rules.length);
    }

    function test_SingleGroup8Rules() public {
        _benchDecode(harness.decode(encodedSingleGroup8Rules), "single_group_8rules", singleGroup8Rules.length);
    }

    function test_SingleGroup16Rules() public {
        _benchDecode(harness.decode(encodedSingleGroup16Rules), "single_group_16rules", singleGroup16Rules.length);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              MULTI-GROUP SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_TwoGroups() public {
        _benchDecode(harness.decode(encodedTwoGroups), "two_groups", twoGroups.length);
    }

    function test_FourGroups() public {
        _benchDecode(harness.decode(encodedFourGroups), "four_groups", fourGroups.length);
    }

    function test_EightGroups() public {
        _benchDecode(harness.decode(encodedEightGroups), "eight_groups", eightGroups.length);
    }

    /*/////////////////////////////////////////////////////////////////////////
                            LARGE GROUP COUNT
    /////////////////////////////////////////////////////////////////////////*/

    function test_Groups32() public {
        _benchDecode(harness.decode(encodedGroups32), "groups_32", groups32.length);
    }

    function test_Groups64() public {
        _benchDecode(harness.decode(encodedGroups64), "groups_64", groups64.length);
    }

    function test_Groups128() public {
        _benchDecode(harness.decode(encodedGroups128), "groups_128", groups128.length);
    }

    function test_Groups255() public {
        _benchDecode(harness.decode(encodedGroups255), "groups_255", groups255.length);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              CONTEXT SCOPE
    /////////////////////////////////////////////////////////////////////////*/

    function test_ContextOnly() public {
        _benchDecode(harness.decode(encodedContextOnly), "context_only", contextOnly.length);
    }

    function test_MixedScope() public {
        _benchDecode(harness.decode(encodedMixedScope), "mixed_scope", mixedScope.length);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              BOUNDARY
    /////////////////////////////////////////////////////////////////////////*/

    function test_MixedOpCodes() public {
        _benchDecode(harness.decode(encodedMixedOpCodes), "mixed_op_codes", mixedOpCodes.length);
    }
}

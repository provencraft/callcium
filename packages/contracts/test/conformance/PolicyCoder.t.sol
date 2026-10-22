// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ConformanceTest } from "test/conformance/ConformanceTest.sol";
import { PolicyCoderHarness } from "test/harnesses/PolicyCoderHarness.sol";

contract PolicyCoderConformanceTest is ConformanceTest {
    PolicyCoderHarness internal coder;

    function setUp() public {
        coder = new PolicyCoderHarness();
    }

    function test_EncodesConformWithSpecification() public view {
        string memory json = vm.readFile("../../spec/vectors/encoding.json");
        uint256 count = _vectorCount(json);
        assertGt(count, 0, "no vectors");
        for (uint256 i = 0; i < count; ++i) {
            string memory key = string.concat(".[", vm.toString(i), "]");
            string memory id = vm.parseJsonString(json, string.concat(key, ".id"));
            bytes memory expected = vm.parseJsonBytes(json, string.concat(key, ".expected"));
            bytes memory input = vm.parseJsonBytes(json, string.concat(key, ".input"));
            // An empty expected blob is the encoder refusing the policy.
            assertEq(_reencode(coder, input), expected, id);
        }
    }
}

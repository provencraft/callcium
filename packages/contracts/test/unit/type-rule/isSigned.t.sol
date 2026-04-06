// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TypeRuleTest } from "../TypeRule.t.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

contract IsSignedTest is TypeRuleTest {
    function testFuzz_TrueOnlyForSignedRange(uint8 code) public pure {
        vm.assume(TypeRule.isValid(code));
        bool expected = code >= TypeCode.INT8 && code <= TypeCode.INT256;
        assertEq(TypeRule.isSigned(code), expected);
    }
}

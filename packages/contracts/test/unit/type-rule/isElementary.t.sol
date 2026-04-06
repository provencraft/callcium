// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TypeRuleTest } from "../TypeRule.t.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

contract IsElementaryTest is TypeRuleTest {
    function test_TrueForElementaryTypes() public pure {
        for (uint8 c = TypeCode.UINT8; c <= TypeCode.UINT256; ++c) {
            assertTrue(TypeRule.isElementary(c));
        }
        for (uint8 c = TypeCode.INT8; c <= TypeCode.INT256; ++c) {
            assertTrue(TypeRule.isElementary(c));
        }
        assertTrue(TypeRule.isElementary(TypeCode.ADDRESS));
        assertTrue(TypeRule.isElementary(TypeCode.BOOL));
        assertTrue(TypeRule.isElementary(TypeCode.FUNCTION));

        for (uint8 c = TypeCode.BYTES1; c <= TypeCode.BYTES32; ++c) {
            assertTrue(TypeRule.isElementary(c));
        }

        assertTrue(TypeRule.isElementary(TypeCode.BYTES));
        assertTrue(TypeRule.isElementary(TypeCode.STRING));
    }

    function testFuzz_FalseForNonElementary(uint8 code) public pure {
        // forgefmt: disable-next-item
        vm.assume(
            !(
                   (code >= TypeCode.UINT8 && code <= TypeCode.UINT256)
                || (code >= TypeCode.INT8 && code <= TypeCode.INT256)
                || (code == TypeCode.ADDRESS || code == TypeCode.BOOL || code == TypeCode.FUNCTION)
                || (code >= TypeCode.BYTES1 && code <= TypeCode.BYTES32)
                || (code == TypeCode.BYTES || code == TypeCode.STRING)
            )
        );
        assertFalse(TypeRule.isElementary(code));
    }

    function testFuzz_ImpliesIsValid(uint8 code) public pure {
        if (TypeRule.isElementary(code)) assertTrue(TypeRule.isValid(code));
    }
}

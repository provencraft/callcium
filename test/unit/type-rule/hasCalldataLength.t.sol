// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TypeRuleTest } from "../TypeRule.t.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

contract HasCalldataLengthTest is TypeRuleTest {
    function test_TrueForTypesWithCalldataLength() public pure {
        assertTrue(TypeRule.hasCalldataLength(TypeCode.BYTES));
        assertTrue(TypeRule.hasCalldataLength(TypeCode.STRING));
        assertTrue(TypeRule.hasCalldataLength(TypeCode.DYNAMIC_ARRAY));
    }

    function testFuzz_FalseForTypesWithoutCalldataLength(uint8 code) public pure {
        // forgefmt: disable-next-item
        vm.assume(
               code != TypeCode.BYTES
            && code != TypeCode.STRING
            && code != TypeCode.DYNAMIC_ARRAY
        );
        assertFalse(TypeRule.hasCalldataLength(code));
    }
}

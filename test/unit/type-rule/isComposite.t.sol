// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TypeRuleTest } from "../TypeRule.t.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

contract IsCompositeTest is TypeRuleTest {
    function test_TrueForComposite() public pure {
        assertTrue(TypeRule.isComposite(TypeCode.STATIC_ARRAY));
        assertTrue(TypeRule.isComposite(TypeCode.DYNAMIC_ARRAY));
        assertTrue(TypeRule.isComposite(TypeCode.TUPLE));
    }

    function testFuzz_FalseForNonComposite(uint8 code) public pure {
        // forgefmt: disable-next-item
        vm.assume(
               code != TypeCode.STATIC_ARRAY
            && code != TypeCode.DYNAMIC_ARRAY
            && code != TypeCode.TUPLE
        );
        assertFalse(TypeRule.isComposite(code));
    }

    function testFuzz_ImpliesIsValid(uint8 code) public pure {
        if (TypeRule.isComposite(code)) assertTrue(TypeRule.isValid(code));
    }
}

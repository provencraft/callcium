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

    function testFuzz_FalseForNonComposite(uint256 seed) public pure {
        uint8[256] memory set;
        uint256 count;
        for (uint16 i = 0; i < 256; ++i) {
            // Cast to 'uint8' is safe because 'i' is bounded to [0, 256).
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 code = uint8(i);
            if (code != TypeCode.STATIC_ARRAY && code != TypeCode.DYNAMIC_ARRAY && code != TypeCode.TUPLE) {
                set[count++] = code;
            }
        }
        assertGt(count, 0, "empty set");
        uint8 picked = set[bound(seed, 0, count - 1)];
        assertFalse(TypeRule.isComposite(picked));
    }

    function testFuzz_ImpliesIsValid(uint8 code) public pure {
        if (TypeRule.isComposite(code)) assertTrue(TypeRule.isValid(code));
    }
}

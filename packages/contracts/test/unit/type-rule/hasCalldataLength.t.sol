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

    function testFuzz_FalseForTypesWithoutCalldataLength(uint256 seed) public pure {
        uint8[256] memory set;
        uint256 count;
        for (uint16 i = 0; i < 256; ++i) {
            // Cast to 'uint8' is safe because 'i' is bounded to [0, 256).
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 code = uint8(i);
            if (code != TypeCode.BYTES && code != TypeCode.STRING && code != TypeCode.DYNAMIC_ARRAY) {
                set[count++] = code;
            }
        }
        assertGt(count, 0, "empty set");
        uint8 picked = set[bound(seed, 0, count - 1)];
        assertFalse(TypeRule.hasCalldataLength(picked));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TypeRuleTest } from "../TypeRule.t.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

contract IsSignedTest is TypeRuleTest {
    function testFuzz_TrueOnlyForSignedRange(uint256 seed) public pure {
        uint8[256] memory set;
        uint256 count;
        for (uint16 i = 0; i < 256; ++i) {
            // Cast to 'uint8' is safe because 'i' is bounded to [0, 256).
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 c = uint8(i);
            if (TypeRule.isValid(c)) set[count++] = c;
        }
        assertGt(count, 0, "empty set");
        uint8 code = set[bound(seed, 0, count - 1)];
        bool expected = code >= TypeCode.INT8 && code <= TypeCode.INT256;
        assertEq(TypeRule.isSigned(code), expected);
    }
}

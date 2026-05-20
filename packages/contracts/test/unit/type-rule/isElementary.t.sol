// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TypeRuleTest } from "../TypeRule.t.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

contract IsElementaryTest is TypeRuleTest {
    function _isElementaryCode(uint8 code) internal pure returns (bool) {
        return (code >= TypeCode.UINT8 && code <= TypeCode.UINT256)
            || (code >= TypeCode.INT8 && code <= TypeCode.INT256) || code == TypeCode.ADDRESS || code == TypeCode.BOOL
            || code == TypeCode.FUNCTION || (code >= TypeCode.BYTES1 && code <= TypeCode.BYTES32)
            || code == TypeCode.BYTES || code == TypeCode.STRING;
    }

    function test_TrueForElementaryTypes() public pure {
        for (uint16 i = 0; i < 256; ++i) {
            // Cast to 'uint8' is safe because 'i' is bounded to [0, 256).
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 code = uint8(i);
            if (_isElementaryCode(code)) assertTrue(TypeRule.isElementary(code));
        }
    }

    function testFuzz_FalseForNonElementary(uint256 seed) public pure {
        uint8[256] memory set;
        uint256 count;
        for (uint16 i = 0; i < 256; ++i) {
            // Cast to 'uint8' is safe because 'i' is bounded to [0, 256).
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 code = uint8(i);
            if (!_isElementaryCode(code)) set[count++] = code;
        }
        assertGt(count, 0, "empty set");
        uint8 picked = set[bound(seed, 0, count - 1)];
        assertFalse(TypeRule.isElementary(picked));
    }

    function testFuzz_ImpliesIsValid(uint8 code) public pure {
        if (TypeRule.isElementary(code)) assertTrue(TypeRule.isValid(code));
    }
}

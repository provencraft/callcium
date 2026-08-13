// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { TypeRuleTest } from "../TypeRule.t.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

contract IsLeftAlignedTest is TypeRuleTest {
    /// @dev Pins the predicate against the type set it names, over the whole code space.
    function test_TrueOnlyForFixedBytesAndFunction() public pure {
        for (uint16 i = 0; i < 256; ++i) {
            // Cast to 'uint8' is safe because 'i' is bounded to [0, 256).
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 code = uint8(i);
            bool expected = (code >= TypeCode.BYTES1 && code <= TypeCode.BYTES32) || code == TypeCode.FUNCTION;
            assertEq(TypeRule.isLeftAligned(code), expected, vm.toString(code));
        }
    }
}

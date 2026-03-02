// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpRule } from "src/OpRule.sol";

contract IsValueOpCompatibleTest is OpRuleTest {
    function test_Static32ByteTypes_Compatible() public pure {
        // Static 32-byte types are compatible with value operators
        assertTrue(OpRule.isValueOpCompatible(false, 32));
    }

    function test_DynamicTypes_NotCompatible() public pure {
        // Dynamic types are not compatible with value operators
        assertFalse(OpRule.isValueOpCompatible(true, 0));
        assertFalse(OpRule.isValueOpCompatible(true, 32));
    }

    function test_SmallStaticTypes_NotCompatible() public pure {
        // Static types smaller than 32 bytes are not compatible
        assertFalse(OpRule.isValueOpCompatible(false, 1));
        assertFalse(OpRule.isValueOpCompatible(false, 20)); // address size
        assertFalse(OpRule.isValueOpCompatible(false, 31));
    }
}

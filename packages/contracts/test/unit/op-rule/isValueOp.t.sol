// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpCode } from "src/OpCode.sol";
import { OpRule } from "src/OpRule.sol";

contract IsValueOpTest is OpRuleTest {
    function test_ComparisonOps_AreValueOps() public pure {
        assertTrue(OpRule.isValueOp(OpCode.EQ));
        assertTrue(OpRule.isValueOp(OpCode.GT));
        assertTrue(OpRule.isValueOp(OpCode.LT));
        assertTrue(OpRule.isValueOp(OpCode.GTE));
        assertTrue(OpRule.isValueOp(OpCode.LTE));
        assertTrue(OpRule.isValueOp(OpCode.BETWEEN));
        assertTrue(OpRule.isValueOp(OpCode.IN));
    }

    function test_BitmaskOps_AreValueOps() public pure {
        assertTrue(OpRule.isValueOp(OpCode.BITMASK_ALL));
        assertTrue(OpRule.isValueOp(OpCode.BITMASK_ANY));
        assertTrue(OpRule.isValueOp(OpCode.BITMASK_NONE));
    }

    function test_LengthOps_NotValueOps() public pure {
        assertFalse(OpRule.isValueOp(OpCode.LENGTH_EQ));
        assertFalse(OpRule.isValueOp(OpCode.LENGTH_GT));
        assertFalse(OpRule.isValueOp(OpCode.LENGTH_BETWEEN));
    }
}

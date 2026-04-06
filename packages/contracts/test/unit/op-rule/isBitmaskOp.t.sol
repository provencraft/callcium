// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpCode } from "src/OpCode.sol";
import { OpRule } from "src/OpRule.sol";

contract IsBitmaskOpTest is OpRuleTest {
    function test_BitmaskOps_AreBitmaskOps() public pure {
        assertTrue(OpRule.isBitmaskOp(OpCode.BITMASK_ALL));
        assertTrue(OpRule.isBitmaskOp(OpCode.BITMASK_ANY));
        assertTrue(OpRule.isBitmaskOp(OpCode.BITMASK_NONE));
    }

    function test_ComparisonOps_NotBitmaskOps() public pure {
        assertFalse(OpRule.isBitmaskOp(OpCode.EQ));
        assertFalse(OpRule.isBitmaskOp(OpCode.GT));
        assertFalse(OpRule.isBitmaskOp(OpCode.LT));
        assertFalse(OpRule.isBitmaskOp(OpCode.GTE));
        assertFalse(OpRule.isBitmaskOp(OpCode.LTE));
        assertFalse(OpRule.isBitmaskOp(OpCode.BETWEEN));
    }

    function test_In_NotBitmaskOp() public pure {
        assertFalse(OpRule.isBitmaskOp(OpCode.IN));
    }

    function test_LengthOps_NotBitmaskOps() public pure {
        assertFalse(OpRule.isBitmaskOp(OpCode.LENGTH_EQ));
        assertFalse(OpRule.isBitmaskOp(OpCode.LENGTH_GT));
        assertFalse(OpRule.isBitmaskOp(OpCode.LENGTH_BETWEEN));
    }
}

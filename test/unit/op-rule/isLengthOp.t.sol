// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpCode } from "src/OpCode.sol";
import { OpRule } from "src/OpRule.sol";

contract IsLengthOpTest is OpRuleTest {
    function test_LengthOps_AreLengthOps() public pure {
        assertTrue(OpRule.isLengthOp(OpCode.LENGTH_EQ));
        assertTrue(OpRule.isLengthOp(OpCode.LENGTH_GT));
        assertTrue(OpRule.isLengthOp(OpCode.LENGTH_LT));
        assertTrue(OpRule.isLengthOp(OpCode.LENGTH_GTE));
        assertTrue(OpRule.isLengthOp(OpCode.LENGTH_LTE));
        assertTrue(OpRule.isLengthOp(OpCode.LENGTH_BETWEEN));
    }

    function test_ValueOps_NotLengthOps() public pure {
        assertFalse(OpRule.isLengthOp(OpCode.EQ));
        assertFalse(OpRule.isLengthOp(OpCode.GT));
        assertFalse(OpRule.isLengthOp(OpCode.BITMASK_ALL));
    }
}

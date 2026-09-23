// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpCode } from "src/OpCode.sol";
import { OpRule } from "src/OpRule.sol";

contract IsContextOpTest is OpRuleTest {
    function test_ContextReferenceOps_AreContextOps() public pure {
        assertTrue(OpRule.isContextOp(OpCode.EQ_CTX));
        assertTrue(OpRule.isContextOp(OpCode.GT_CTX));
        assertTrue(OpRule.isContextOp(OpCode.LT_CTX));
        assertTrue(OpRule.isContextOp(OpCode.GTE_CTX));
        assertTrue(OpRule.isContextOp(OpCode.LTE_CTX));
    }

    function test_Neighbours_NotContextOps() public pure {
        assertFalse(OpRule.isContextOp(OpCode.IN));
        assertFalse(OpRule.isContextOp(OpCode.BITMASK_ALL));
    }
}

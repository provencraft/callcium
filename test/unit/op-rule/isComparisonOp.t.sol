// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpCode } from "src/OpCode.sol";
import { OpRule } from "src/OpRule.sol";

contract IsComparisonOpTest is OpRuleTest {
    function test_ComparisonOps_AreComparisonOps() public pure {
        assertTrue(OpRule.isComparisonOp(OpCode.GT));
        assertTrue(OpRule.isComparisonOp(OpCode.LT));
        assertTrue(OpRule.isComparisonOp(OpCode.GTE));
        assertTrue(OpRule.isComparisonOp(OpCode.LTE));
        assertTrue(OpRule.isComparisonOp(OpCode.BETWEEN));
    }

    function test_Eq_NotComparisonOp() public pure {
        assertFalse(OpRule.isComparisonOp(OpCode.EQ));
    }

    function test_In_NotComparisonOp() public pure {
        assertFalse(OpRule.isComparisonOp(OpCode.IN));
    }

    function test_BitmaskOps_NotComparisonOps() public pure {
        assertFalse(OpRule.isComparisonOp(OpCode.BITMASK_ALL));
        assertFalse(OpRule.isComparisonOp(OpCode.BITMASK_ANY));
        assertFalse(OpRule.isComparisonOp(OpCode.BITMASK_NONE));
    }

    function test_LengthOps_NotComparisonOps() public pure {
        assertFalse(OpRule.isComparisonOp(OpCode.LENGTH_EQ));
        assertFalse(OpRule.isComparisonOp(OpCode.LENGTH_GT));
        assertFalse(OpRule.isComparisonOp(OpCode.LENGTH_BETWEEN));
    }
}

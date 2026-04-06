// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpCode } from "src/OpCode.sol";
import { OpRule } from "src/OpRule.sol";

contract IsLengthComparisonOpTest is OpRuleTest {
    function test_LengthComparisonOps_AreLengthComparisonOps() public pure {
        assertTrue(OpRule.isLengthComparisonOp(OpCode.LENGTH_GT));
        assertTrue(OpRule.isLengthComparisonOp(OpCode.LENGTH_LT));
        assertTrue(OpRule.isLengthComparisonOp(OpCode.LENGTH_GTE));
        assertTrue(OpRule.isLengthComparisonOp(OpCode.LENGTH_LTE));
        assertTrue(OpRule.isLengthComparisonOp(OpCode.LENGTH_BETWEEN));
    }

    function test_LengthEq_NotLengthComparisonOp() public pure {
        assertFalse(OpRule.isLengthComparisonOp(OpCode.LENGTH_EQ));
    }

    function test_ValueOps_NotLengthComparisonOps() public pure {
        assertFalse(OpRule.isLengthComparisonOp(OpCode.EQ));
        assertFalse(OpRule.isLengthComparisonOp(OpCode.GT));
        assertFalse(OpRule.isLengthComparisonOp(OpCode.LT));
        assertFalse(OpRule.isLengthComparisonOp(OpCode.BETWEEN));
    }

    function test_BitmaskOps_NotLengthComparisonOps() public pure {
        assertFalse(OpRule.isLengthComparisonOp(OpCode.BITMASK_ALL));
        assertFalse(OpRule.isLengthComparisonOp(OpCode.BITMASK_ANY));
        assertFalse(OpRule.isLengthComparisonOp(OpCode.BITMASK_NONE));
    }
}

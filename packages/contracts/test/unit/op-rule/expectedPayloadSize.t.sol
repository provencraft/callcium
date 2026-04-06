// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpCode } from "src/OpCode.sol";
import { OpRule } from "src/OpRule.sol";

contract ExpectedPayloadSizeTest is OpRuleTest {
    function test_SingleOperand_Returns32() public pure {
        assertEq(OpRule.expectedPayloadSize(OpCode.EQ), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.GT), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.LT), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.GTE), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.LTE), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.BITMASK_ALL), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.BITMASK_ANY), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.BITMASK_NONE), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.LENGTH_EQ), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.LENGTH_GT), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.LENGTH_LT), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.LENGTH_GTE), 32);
        assertEq(OpRule.expectedPayloadSize(OpCode.LENGTH_LTE), 32);
    }

    function test_RangeOperators_Returns64() public pure {
        assertEq(OpRule.expectedPayloadSize(OpCode.BETWEEN), 64);
        assertEq(OpRule.expectedPayloadSize(OpCode.LENGTH_BETWEEN), 64);
    }

    function test_InOperator_Returns0_Variable() public pure {
        assertEq(OpRule.expectedPayloadSize(OpCode.IN), 0);
    }

    function test_UnknownOperator_Returns0() public pure {
        assertEq(OpRule.expectedPayloadSize(0xFF), 0);
        assertEq(OpRule.expectedPayloadSize(0x00), 0);
        assertEq(OpRule.expectedPayloadSize(0x50), 0);
    }
}

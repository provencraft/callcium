// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpCode } from "src/OpCode.sol";
import { OpRule } from "src/OpRule.sol";

contract IsValidPayloadSizeTest is OpRuleTest {
    function test_SingleOperand_Valid32() public pure {
        assertTrue(OpRule.isValidPayloadSize(OpCode.EQ, 32));
        assertTrue(OpRule.isValidPayloadSize(OpCode.GT, 32));
        assertTrue(OpRule.isValidPayloadSize(OpCode.LT, 32));
    }

    function test_SingleOperand_InvalidNon32() public pure {
        assertFalse(OpRule.isValidPayloadSize(OpCode.EQ, 0));
        assertFalse(OpRule.isValidPayloadSize(OpCode.EQ, 31));
        assertFalse(OpRule.isValidPayloadSize(OpCode.EQ, 64));
    }

    function test_RangeOperators_Valid64() public pure {
        assertTrue(OpRule.isValidPayloadSize(OpCode.BETWEEN, 64));
        assertTrue(OpRule.isValidPayloadSize(OpCode.LENGTH_BETWEEN, 64));
    }

    function test_RangeOperators_InvalidNon64() public pure {
        assertFalse(OpRule.isValidPayloadSize(OpCode.BETWEEN, 32));
        assertFalse(OpRule.isValidPayloadSize(OpCode.BETWEEN, 0));
    }

    function test_InOperator_ValidMultiplesOf32() public pure {
        assertTrue(OpRule.isValidPayloadSize(OpCode.IN, 32));
        assertTrue(OpRule.isValidPayloadSize(OpCode.IN, 64));
        assertTrue(OpRule.isValidPayloadSize(OpCode.IN, 96));
        assertTrue(OpRule.isValidPayloadSize(OpCode.IN, 128));
    }

    function test_InOperator_InvalidZero() public pure {
        assertFalse(OpRule.isValidPayloadSize(OpCode.IN, 0));
    }

    function test_InOperator_InvalidNonMultipleOf32() public pure {
        assertFalse(OpRule.isValidPayloadSize(OpCode.IN, 31));
        assertFalse(OpRule.isValidPayloadSize(OpCode.IN, 33));
        assertFalse(OpRule.isValidPayloadSize(OpCode.IN, 63));
    }

    function test_UnknownOperator_AlwaysFalse() public pure {
        assertFalse(OpRule.isValidPayloadSize(0xFF, 32));
        assertFalse(OpRule.isValidPayloadSize(0x00, 0));
    }
}

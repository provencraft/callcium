// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpRule } from "src/OpRule.sol";
import { TypeCode } from "src/TypeCode.sol";

contract IsNumericTypeTest is OpRuleTest {
    function test_UintTypes_AreNumeric() public pure {
        assertTrue(OpRule.isNumericType(TypeCode.UINT8));
        assertTrue(OpRule.isNumericType(TypeCode.UINT256));
        assertTrue(OpRule.isNumericType(TypeCode.UINT128));
    }

    function test_IntTypes_AreNumeric() public pure {
        assertTrue(OpRule.isNumericType(TypeCode.INT8));
        assertTrue(OpRule.isNumericType(TypeCode.INT256));
        assertTrue(OpRule.isNumericType(TypeCode.INT128));
    }

    function test_Address_NotNumeric() public pure {
        assertFalse(OpRule.isNumericType(TypeCode.ADDRESS));
    }

    function test_Bool_NotNumeric() public pure {
        assertFalse(OpRule.isNumericType(TypeCode.BOOL));
    }

    function test_Bytes32_NotNumeric() public pure {
        assertFalse(OpRule.isNumericType(TypeCode.BYTES32));
    }
}

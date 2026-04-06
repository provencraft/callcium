// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpRule } from "src/OpRule.sol";
import { TypeCode } from "src/TypeCode.sol";

contract IsComparisonCompatibleTest is OpRuleTest {
    function test_UintTypes_Compatible() public pure {
        assertTrue(OpRule.isComparisonCompatible(TypeCode.UINT8));
        assertTrue(OpRule.isComparisonCompatible(TypeCode.UINT256));
        assertTrue(OpRule.isComparisonCompatible(TypeCode.UINT128));
    }

    function test_IntTypes_Compatible() public pure {
        assertTrue(OpRule.isComparisonCompatible(TypeCode.INT8));
        assertTrue(OpRule.isComparisonCompatible(TypeCode.INT256));
        assertTrue(OpRule.isComparisonCompatible(TypeCode.INT128));
    }

    function test_Address_NotCompatible() public pure {
        assertFalse(OpRule.isComparisonCompatible(TypeCode.ADDRESS));
    }

    function test_Bool_NotCompatible() public pure {
        assertFalse(OpRule.isComparisonCompatible(TypeCode.BOOL));
    }

    function test_Bytes32_NotCompatible() public pure {
        assertFalse(OpRule.isComparisonCompatible(TypeCode.BYTES32));
    }

    function test_DynamicTypes_NotCompatible() public pure {
        assertFalse(OpRule.isComparisonCompatible(TypeCode.BYTES));
        assertFalse(OpRule.isComparisonCompatible(TypeCode.STRING));
    }

    function test_CompositeTypes_NotCompatible() public pure {
        assertFalse(OpRule.isComparisonCompatible(TypeCode.TUPLE));
        assertFalse(OpRule.isComparisonCompatible(TypeCode.STATIC_ARRAY));
        assertFalse(OpRule.isComparisonCompatible(TypeCode.DYNAMIC_ARRAY));
    }
}

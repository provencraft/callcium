// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpRule } from "src/OpRule.sol";
import { TypeCode } from "src/TypeCode.sol";

contract IsBitmaskCompatibleTest is OpRuleTest {
    function test_UintTypes_Compatible() public pure {
        assertTrue(OpRule.isBitmaskCompatible(TypeCode.UINT8));
        assertTrue(OpRule.isBitmaskCompatible(TypeCode.UINT256));
    }

    function test_Bytes32_Compatible() public pure {
        assertTrue(OpRule.isBitmaskCompatible(TypeCode.BYTES32));
    }

    function test_IntTypes_NotCompatible() public pure {
        assertFalse(OpRule.isBitmaskCompatible(TypeCode.INT256));
    }

    function test_Address_NotCompatible() public pure {
        assertFalse(OpRule.isBitmaskCompatible(TypeCode.ADDRESS));
    }

    function test_Bool_NotCompatible() public pure {
        assertFalse(OpRule.isBitmaskCompatible(TypeCode.BOOL));
    }
}

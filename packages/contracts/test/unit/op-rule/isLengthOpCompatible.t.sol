// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpRule } from "src/OpRule.sol";
import { TypeCode } from "src/TypeCode.sol";

contract IsLengthOpCompatibleTest is OpRuleTest {
    function test_DynamicBytes_Compatible() public pure {
        assertTrue(OpRule.isLengthOpCompatible(TypeCode.BYTES));
    }

    function test_String_Compatible() public pure {
        assertTrue(OpRule.isLengthOpCompatible(TypeCode.STRING));
    }

    function test_DynamicArray_Compatible() public pure {
        assertTrue(OpRule.isLengthOpCompatible(TypeCode.DYNAMIC_ARRAY));
    }

    function test_StaticArray_NotCompatible() public pure {
        assertFalse(OpRule.isLengthOpCompatible(TypeCode.STATIC_ARRAY));
    }

    function test_Uint256_NotCompatible() public pure {
        assertFalse(OpRule.isLengthOpCompatible(TypeCode.UINT256));
    }

    function test_Address_NotCompatible() public pure {
        assertFalse(OpRule.isLengthOpCompatible(TypeCode.ADDRESS));
    }

    function test_Tuple_NotCompatible() public pure {
        assertFalse(OpRule.isLengthOpCompatible(TypeCode.TUPLE));
    }
}

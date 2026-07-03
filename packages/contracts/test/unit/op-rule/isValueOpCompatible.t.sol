// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpRule } from "src/OpRule.sol";
import { TypeCode } from "src/TypeCode.sol";

contract IsValueOpCompatibleTest is OpRuleTest {
    function test_Static32ByteElementaryTypes_Compatible() public pure {
        // Static 32-byte elementary types are compatible with value operators
        assertTrue(OpRule.isValueOpCompatible(TypeCode.UINT256, false, 32));
        assertTrue(OpRule.isValueOpCompatible(TypeCode.ADDRESS, false, 32));
        assertTrue(OpRule.isValueOpCompatible(TypeCode.BYTES32, false, 32));
    }

    function test_DynamicTypes_NotCompatible() public pure {
        // Dynamic types are not compatible with value operators
        assertFalse(OpRule.isValueOpCompatible(TypeCode.BYTES, true, 0));
        assertFalse(OpRule.isValueOpCompatible(TypeCode.DYNAMIC_ARRAY, true, 32));
    }

    function test_SmallStaticTypes_NotCompatible() public pure {
        // Static types smaller than 32 bytes are not compatible
        assertFalse(OpRule.isValueOpCompatible(TypeCode.UINT256, false, 1));
        assertFalse(OpRule.isValueOpCompatible(TypeCode.ADDRESS, false, 20));
        assertFalse(OpRule.isValueOpCompatible(TypeCode.UINT256, false, 31));
    }

    function test_CompositesWith32ByteHead_NotCompatible() public pure {
        // A one-element static array or single-static-field tuple has a 32-byte head
        // but is not a scalar; the enforcer cannot load it
        assertFalse(OpRule.isValueOpCompatible(TypeCode.STATIC_ARRAY, false, 32));
        assertFalse(OpRule.isValueOpCompatible(TypeCode.TUPLE, false, 32));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { OpRuleTest } from "../OpRule.t.sol";
import { OpCode } from "src/OpCode.sol";
import { OpRule } from "src/OpRule.sol";
import { TypeCode } from "src/TypeCode.sol";

contract CheckCompatibilityTest is OpRuleTest {
    function test_EqOn32ByteStatic_Compatible() public pure {
        (bool ok, bytes32 code) = OpRule.checkCompatibility(OpCode.EQ, TypeCode.UINT256, false, 32);
        assertTrue(ok);
        assertEq(code, bytes32(0));
    }

    function test_EqOnDynamic_NotCompatible() public pure {
        (bool ok, bytes32 code) = OpRule.checkCompatibility(OpCode.EQ, TypeCode.BYTES, true, 0);
        assertFalse(ok);
        assertEq(code, "VALUE_OP_ON_DYNAMIC");
    }

    function test_GtOnNonNumeric_NotCompatible() public pure {
        (bool ok, bytes32 code) = OpRule.checkCompatibility(OpCode.GT, TypeCode.ADDRESS, false, 32);
        assertFalse(ok);
        assertEq(code, "NUMERIC_OP_ON_NON_NUMERIC");
    }

    function test_GtOnNumeric_Compatible() public pure {
        (bool ok, bytes32 code) = OpRule.checkCompatibility(OpCode.GT, TypeCode.UINT256, false, 32);
        assertTrue(ok);
        assertEq(code, bytes32(0));
    }

    function test_BitmaskOnUint_Compatible() public pure {
        (bool ok, bytes32 code) = OpRule.checkCompatibility(OpCode.BITMASK_ALL, TypeCode.UINT256, false, 32);
        assertTrue(ok);
        assertEq(code, bytes32(0));
    }

    function test_BitmaskOnAddress_NotCompatible() public pure {
        (bool ok, bytes32 code) = OpRule.checkCompatibility(OpCode.BITMASK_ALL, TypeCode.ADDRESS, false, 32);
        assertFalse(ok);
        assertEq(code, "BITMASK_ON_INVALID");
    }

    function test_LengthOnDynamic_Compatible() public pure {
        (bool ok, bytes32 code) = OpRule.checkCompatibility(OpCode.LENGTH_EQ, TypeCode.BYTES, true, 0);
        assertTrue(ok);
        assertEq(code, bytes32(0));
    }

    function test_LengthOnStatic_NotCompatible() public pure {
        (bool ok, bytes32 code) = OpRule.checkCompatibility(OpCode.LENGTH_EQ, TypeCode.UINT256, false, 32);
        assertFalse(ok);
        assertEq(code, "LENGTH_ON_STATIC");
    }

    function test_LengthOnStaticArray_NotCompatible() public pure {
        (bool ok, bytes32 code) = OpRule.checkCompatibility(OpCode.LENGTH_EQ, TypeCode.STATIC_ARRAY, true, 0);
        assertFalse(ok);
        assertEq(code, "LENGTH_ON_STATIC");
    }

    function test_UnknownOperator_NotCompatible() public pure {
        (bool ok, bytes32 code) = OpRule.checkCompatibility(0xFF, TypeCode.UINT256, false, 32);
        assertFalse(ok);
        assertEq(code, "UNKNOWN_OPERATOR");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title OpCode
/// @notice Byte values for policy operators.
library OpCode {
    /*/////////////////////////////////////////////////////////////////////////
                             CORE COMPARISON OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    uint8 internal constant EQ = 0x01;
    uint8 internal constant GT = 0x02;
    uint8 internal constant LT = 0x03;
    uint8 internal constant GTE = 0x04;
    uint8 internal constant LTE = 0x05;
    uint8 internal constant BETWEEN = 0x06;

    /*/////////////////////////////////////////////////////////////////////////
                              SET MEMBERSHIP OPERATOR
    /////////////////////////////////////////////////////////////////////////*/

    uint8 internal constant IN = 0x07;

    /*/////////////////////////////////////////////////////////////////////////
                               BITMASK OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    uint8 internal constant BITMASK_ALL = 0x10;
    uint8 internal constant BITMASK_ANY = 0x11;
    uint8 internal constant BITMASK_NONE = 0x12;

    /*/////////////////////////////////////////////////////////////////////////
                               LENGTH OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    uint8 internal constant LENGTH_EQ = 0x18;
    uint8 internal constant LENGTH_GT = 0x19;
    uint8 internal constant LENGTH_LT = 0x1A;
    uint8 internal constant LENGTH_GTE = 0x1B;
    uint8 internal constant LENGTH_LTE = 0x1C;
    uint8 internal constant LENGTH_BETWEEN = 0x1D;

    /*/////////////////////////////////////////////////////////////////////////
                                   NOT FLAG
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev OR with any operator to negate.
    uint8 internal constant NOT = 0x80;

    /*/////////////////////////////////////////////////////////////////////////
                                  OPERAND SOURCE
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Bit shift of `source` (bits 6-5). The comparison fills bits 4-0.
    uint8 internal constant SOURCE_SHIFT = 5;

    /// @dev Mask for the comparison bits of an operator code.
    uint8 internal constant COMPARISON_MASK = 0x1F;

    /// @dev Source of constant operand values.
    uint8 internal constant SOURCE_CONSTANT = 0;

    /// @dev Source of a context property operand.
    uint8 internal constant SOURCE_CONTEXT = 1;
}

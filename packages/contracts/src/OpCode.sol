// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title OpCode
/// @notice Byte values for policy operators (the "instruction set").
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

    uint8 internal constant LENGTH_EQ = 0x20;
    uint8 internal constant LENGTH_GT = 0x21;
    uint8 internal constant LENGTH_LT = 0x22;
    uint8 internal constant LENGTH_GTE = 0x23;
    uint8 internal constant LENGTH_LTE = 0x24;
    uint8 internal constant LENGTH_BETWEEN = 0x25;

    /*/////////////////////////////////////////////////////////////////////////
                                   NOT FLAG
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev OR with any operator to negate.
    uint8 internal constant NOT = 0x80;
}

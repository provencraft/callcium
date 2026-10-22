// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { OpCode } from "./OpCode.sol";
import { TypeRule } from "./TypeRule.sol";

/// @title OpRule
/// @notice Single source of truth for operator validation rules.
library OpRule {
    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Validates that a payload length is valid for the given operator.
    /// @param opBase The comparison bits of the operator code, a defined comparison.
    /// @param dataLength The actual payload length.
    /// @param width The operand width in bytes, at least one.
    /// @return True if the payload length is valid for this operator.
    function isValidPayloadSize(uint8 opBase, uint16 dataLength, uint256 width) internal pure returns (bool) {
        // Range operators carry a lower and an upper operand; IN carries one or more; every other operator one.
        if (opBase == OpCode.BETWEEN || opBase == OpCode.LENGTH_BETWEEN) return dataLength == 2 * width;
        if (opBase == OpCode.IN) return dataLength > 0 && dataLength % width == 0;
        return dataLength == width;
    }

    /// @notice Checks if an operator is a length operator.
    /// @param opBase The comparison bits of the operator code.
    /// @return True if this is a length operator.
    function isLengthOp(uint8 opBase) internal pure returns (bool) {
        return opBase >= OpCode.LENGTH_EQ && opBase <= OpCode.LENGTH_BETWEEN;
    }

    /// @notice Checks if an operator code names a defined comparison.
    /// @param opBase The comparison bits of the operator code.
    /// @return True if the comparison is defined.
    function isComparison(uint8 opBase) internal pure returns (bool) {
        return (opBase >= OpCode.EQ && opBase <= OpCode.IN)
            || (opBase >= OpCode.BITMASK_ALL && opBase <= OpCode.BITMASK_NONE) || isLengthOp(opBase);
    }

    /// @notice Checks if an operator admits a context property operand: EQ, GT, LT, GTE or LTE.
    /// @param opBase The comparison bits of the operator code.
    /// @return True if the operator admits a context source.
    function acceptsContextSource(uint8 opBase) internal pure returns (bool) {
        return opBase >= OpCode.EQ && opBase <= OpCode.LTE;
    }

    /// @notice Returns the type a comparison's constants take against a target type.
    /// @dev A length comparison compares a type with a calldata length as `LENGTH_TYPE`, any other comparison a static
    /// elementary type as itself.
    /// @param comparison The comparison bits of the operator code.
    /// @param typeCode The target's type code.
    /// @return The operand type code, or zero where the comparison does not apply to the target.
    function operandTypeOf(uint8 comparison, uint8 typeCode) internal pure returns (uint8) {
        if (isLengthOp(comparison)) return TypeRule.hasCalldataLength(typeCode) ? TypeRule.LENGTH_TYPE : 0;
        return TypeRule.operandWidth(typeCode) != 0 ? typeCode : 0;
    }
}

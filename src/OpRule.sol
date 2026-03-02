// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IssueCode } from "./IssueCode.sol";
import { OpCode } from "./OpCode.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";

/// @title OpRule
/// @notice Single source of truth for operator validation rules.
/// @dev Defines valid operator-type pairings and physical bounds per type.
library OpRule {
    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the expected payload size for an operator, or 0 for variable-length operators.
    /// @param opBase The operator code without the NOT flag.
    /// @return size The expected payload size in bytes, or 0 if variable/unknown.
    function expectedPayloadSize(uint8 opBase) internal pure returns (uint16 size) {
        // Single-operand operators: 32 bytes.
        // forgefmt: disable-next-item
        if (
               opBase == OpCode.EQ
            || opBase == OpCode.GT
            || opBase == OpCode.LT
            || opBase == OpCode.GTE
            || opBase == OpCode.LTE
            || opBase == OpCode.BITMASK_ALL
            || opBase == OpCode.BITMASK_ANY
            || opBase == OpCode.BITMASK_NONE
            || opBase == OpCode.LENGTH_EQ
            || opBase == OpCode.LENGTH_GT
            || opBase == OpCode.LENGTH_LT
            || opBase == OpCode.LENGTH_GTE
            || opBase == OpCode.LENGTH_LTE
        ) {
            return 32;
        }

        // Range operators: 64 bytes (lower + upper)
        if (opBase == OpCode.BETWEEN || opBase == OpCode.LENGTH_BETWEEN) return 64;

        // IN operator: variable length (must be > 0 and multiple of 32)
        // Return 0 to indicate variable-length.
        if (opBase == OpCode.IN) return 0;

        // Unknown operator.
        return 0;
    }

    /// @notice Validates that a payload length is valid for the given operator.
    /// @param opBase The operator code without the NOT flag.
    /// @param dataLength The actual payload length.
    /// @return True if the payload length is valid for this operator.
    function isValidPayloadSize(uint8 opBase, uint16 dataLength) internal pure returns (bool) {
        uint16 expected = expectedPayloadSize(opBase);

        // Fixed-size operators.
        if (expected != 0) return dataLength == expected;

        // Variable-size operator (IN)
        if (opBase == OpCode.IN) return dataLength > 0 && dataLength % 32 == 0;

        // Unknown operator.
        return false;
    }

    /// @notice Checks if a value operator is compatible with the given type.
    /// @dev Value operators (EQ, GT, LT, GTE, LTE, BETWEEN, IN, BITMASK_*) require 32-byte static types.
    /// @param isDynamic Whether the type has dynamic ABI encoding.
    /// @param staticSize The ABI head size in bytes (0 if dynamic).
    /// @return True if the value operator can be used with this type.
    function isValueOpCompatible(bool isDynamic, uint32 staticSize) internal pure returns (bool) {
        return !isDynamic && staticSize == 32;
    }

    /// @notice Checks if a length operator is compatible with the given type code.
    /// @dev Length operators work only on types with calldata length: bytes, string, or dynamic arrays.
    /// @param typeCode The type code of the target value.
    /// @return True if length operators can be used with this type.
    function isLengthOpCompatible(uint8 typeCode) internal pure returns (bool) {
        return TypeRule.hasCalldataLength(typeCode);
    }

    /// @notice Checks if an operator is a value operator (as opposed to a length operator).
    /// @param opBase The operator code without the NOT flag.
    /// @return True if this is a value operator.
    function isValueOp(uint8 opBase) internal pure returns (bool) {
        return opBase <= OpCode.BITMASK_NONE;
    }

    /// @notice Checks if an operator is a length operator.
    /// @param opBase The operator code without the NOT flag.
    /// @return True if this is a length operator.
    function isLengthOp(uint8 opBase) internal pure returns (bool) {
        return opBase >= OpCode.LENGTH_EQ && opBase <= OpCode.LENGTH_BETWEEN;
    }

    /// @notice Checks if an operator is a comparison operator (GT, LT, GTE, LTE, BETWEEN).
    /// @param opBase The operator code without the NOT flag.
    /// @return True if this is a comparison operator.
    function isComparisonOp(uint8 opBase) internal pure returns (bool) {
        return opBase >= OpCode.GT && opBase <= OpCode.BETWEEN;
    }

    /// @notice Checks if an operator is a length comparison operator.
    /// @param opBase The operator code without the NOT flag.
    /// @return True if this is a length comparison operator.
    function isLengthComparisonOp(uint8 opBase) internal pure returns (bool) {
        return opBase >= OpCode.LENGTH_GT && opBase <= OpCode.LENGTH_BETWEEN;
    }

    /// @notice Checks if an operator is a bitmask operator.
    /// @param opBase The operator code without the NOT flag.
    /// @return True if this is a bitmask operator.
    function isBitmaskOp(uint8 opBase) internal pure returns (bool) {
        return opBase >= OpCode.BITMASK_ALL && opBase <= OpCode.BITMASK_NONE;
    }

    /// @notice Checks if a type code represents a numeric type (uint or int).
    /// @param typeCode The type code to check.
    /// @return True if the type is numeric.
    function isNumericType(uint8 typeCode) internal pure returns (bool) {
        return typeCode <= TypeCode.UINT256 || (typeCode >= TypeCode.INT8 && typeCode <= TypeCode.INT256);
    }

    /// @notice Checks if a type code is valid for bitmask operations.
    /// @dev Bitmask operations work on uint types and bytes32.
    /// @param typeCode The type code to check.
    /// @return True if bitmask operators can be used with this type.
    function isBitmaskCompatible(uint8 typeCode) internal pure returns (bool) {
        return typeCode <= TypeCode.UINT256 || typeCode == TypeCode.BYTES32;
    }

    /// @notice Checks if comparison operators are semantically valid for a type.
    /// @dev GT/LT/GTE/LTE/BETWEEN are only meaningful for numeric types.
    /// @param typeCode The type code to check.
    /// @return True if comparison operators are valid for this type.
    function isComparisonCompatible(uint8 typeCode) internal pure returns (bool) {
        return isNumericType(typeCode);
    }

    /// @notice Validates operator & type compatibility during semantic validation.
    /// @param opBase The operator code without the NOT flag.
    /// @param typeCode The type code of the target value.
    /// @param isDynamic Whether the type has dynamic ABI encoding.
    /// @param staticSize The ABI head size in bytes (0 if dynamic).
    /// @return compatible True if the operator is compatible with the type.
    /// @return code Machine-readable error code if incompatible.
    function checkCompatibility(
        uint8 opBase,
        uint8 typeCode,
        bool isDynamic,
        uint32 staticSize
    )
        internal
        pure
        returns (bool compatible, bytes32 code)
    {
        if (isValueOp(opBase)) {
            // Value operators require 32-byte static types.
            if (!isValueOpCompatible(isDynamic, staticSize)) return (false, IssueCode.VALUE_OP_ON_DYNAMIC);

            // Comparison operators need numeric types.
            if (isComparisonOp(opBase) && !isComparisonCompatible(typeCode)) {
                return (false, IssueCode.NUMERIC_OP_ON_NON_NUMERIC);
            }

            // Bitmask operators need compatible types.
            if (isBitmaskOp(opBase) && !isBitmaskCompatible(typeCode)) return (false, IssueCode.BITMASK_ON_INVALID);

            return (true, bytes32(0));
        }

        if (isLengthOp(opBase)) {
            // Length operators require types with calldata length.
            if (!isLengthOpCompatible(typeCode)) return (false, IssueCode.LENGTH_ON_STATIC);

            return (true, bytes32(0));
        }

        // Unknown operator.
        return (false, IssueCode.UNKNOWN_OPERATOR);
    }

    /// @notice Returns the human-readable message for a compatibility error code.
    /// @param code The error code from checkCompatibility.
    /// @return message The human-readable description.
    function compatibilityMessage(bytes32 code) internal pure returns (string memory message) {
        if (code == IssueCode.VALUE_OP_ON_DYNAMIC) return "Value operator used on dynamic type";
        if (code == IssueCode.NUMERIC_OP_ON_NON_NUMERIC) return "Comparison operator used on non-numeric type";
        if (code == IssueCode.BITMASK_ON_INVALID) return "Bitmask operator used on incompatible type";
        if (code == IssueCode.LENGTH_ON_STATIC) return "Length operator used on non-dynamic type";
        return "Unknown operator code";
    }
}

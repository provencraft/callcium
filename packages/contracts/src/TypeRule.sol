// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { TypeCode } from "./TypeCode.sol";

/// @title TypeRule
/// @notice Single source of truth for ABI type properties and validation rules.
library TypeRule {
    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns true if `code` has its length encoded in calldata (bytes, string, or dynamic array).
    /// @param code The code to test.
    /// @return True if the type has a calldata-encoded length prefix.
    function hasCalldataLength(uint8 code) internal pure returns (bool) {
        return code == TypeCode.BYTES || code == TypeCode.STRING || code == TypeCode.DYNAMIC_ARRAY;
    }

    /// @notice Returns true if `code` is any recognized type code byte (elementary or composite marker).
    /// @param code The code to test.
    /// @return True if the code is a valid type code.
    function isValid(uint8 code) internal pure returns (bool) {
        return isElementary(code) || isComposite(code);
    }

    /// @notice Returns true if `code` is a composite type marker (array or tuple).
    /// @param code The code to test.
    /// @return True if the code is a composite type.
    function isComposite(uint8 code) internal pure returns (bool) {
        return code == TypeCode.STATIC_ARRAY || code == TypeCode.DYNAMIC_ARRAY || code == TypeCode.TUPLE;
    }

    /// @notice Returns true if `code` is a single-byte elementary type (fully specified by one byte).
    /// @param code The code to test.
    /// @return True if the code is an elementary type.
    function isElementary(uint8 code) internal pure returns (bool) {
        // forgefmt: disable-next-item
        return (code >= TypeCode.UINT8 && code <= TypeCode.UINT256)
            || (code >= TypeCode.INT8 && code <= TypeCode.INT256)
            || (code == TypeCode.ADDRESS || code == TypeCode.BOOL || code == TypeCode.FUNCTION)
            || (code >= TypeCode.BYTES1 && code <= TypeCode.BYTES32)
            || (code == TypeCode.BYTES || code == TypeCode.STRING);
    }

    /// @notice Returns true if `code` is a signed integer type (int8 through int256).
    /// @param code The code to test.
    /// @return True if the code is a signed integer type.
    function isSigned(uint8 code) internal pure returns (bool) {
        return code >= TypeCode.INT8 && code <= TypeCode.INT256;
    }

    /// @notice Returns the physical limits of a numeric type.
    /// @param typeCode The type code to check.
    /// @return min The minimum possible value (raw bits).
    /// @return max The maximum possible value (raw bits).
    function getDomainLimits(uint8 typeCode) internal pure returns (uint256 min, uint256 max) {
        if (typeCode <= TypeCode.UINT256) {
            uint256 bits = (uint256(typeCode) + 1) * 8;
            min = 0;
            // forge-lint: disable-next-line(incorrect-shift) 2^bits bitmask
            max = bits == 256 ? type(uint256).max : (1 << bits) - 1;
        } else if (typeCode >= TypeCode.INT8 && typeCode <= TypeCode.INT256) {
            uint256 bits = (uint256(typeCode - TypeCode.INT8) + 1) * 8;
            if (bits == 256) {
                min = uint256(type(int256).min);
                max = uint256(type(int256).max);
            } else {
                // forge-lint: disable-next-line(incorrect-shift) 2^(bits-1) bitmask
                max = (1 << (bits - 1)) - 1;
                // forge-lint: disable-next-line(incorrect-shift) 2^(bits-1) bitmask
                min = uint256(-int256(1 << (bits - 1)));
            }
        } else if (typeCode == TypeCode.BOOL) {
            min = 0;
            max = 1;
        } else if (typeCode == TypeCode.ADDRESS) {
            min = 0;
            max = type(uint160).max;
        } else {
            min = 0;
            max = type(uint256).max;
        }
    }
}

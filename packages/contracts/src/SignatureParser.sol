// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { LibBytes } from "solady/utils/LibBytes.sol";

/// @title SignatureParser
/// @notice Parses strict Solidity-style function signatures and computes the selector.
/// @dev Strict mode compatible with abi.encodeWithSignature expectations:
/// - No ASCII whitespace allowed anywhere in the signature.
/// - Structure must be name(types) with the final ')' as the last byte.
/// - Function name must match [A-Za-z_][A-Za-z0-9_]*.
/// - Types are not validated here.
library SignatureParser {
    /*/////////////////////////////////////////////////////////////////////////
                                    ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the signature contains any ASCII whitespace chars.
    error SignatureContainsWhitespace();

    /// @notice Thrown when the signature does not follow the strict name(types) form.
    error MalformedSignature();

    /// @notice Thrown when the function name is empty or contains invalid chars.
    error InvalidFunctionName();

    /*/////////////////////////////////////////////////////////////////////////
                                    FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Parses a function signature and returns selector, name, and the raw types CSV.
    /// @param signature The full signature string, e.g., "transfer(address,uint256)".
    /// @return selector The 4-byte function selector computed as bytes4(keccak256(signature)).
    /// @return name The function name substring before '('.
    /// @return typesCsv The comma-separated types.
    function parse(string memory signature)
        internal
        pure
        returns (bytes4 selector, string memory name, string memory typesCsv)
    {
        bytes memory signatureBytes = bytes(signature);
        uint256 openParenIndex = _scanAndValidate(signatureBytes);

        name = string(LibBytes.slice(signatureBytes, 0, openParenIndex));
        typesCsv = string(LibBytes.slice(signatureBytes, openParenIndex + 1, signatureBytes.length - 1));
        selector = bytes4(keccak256(signatureBytes));
    }

    /// @notice Parses a function signature and returns selector and the raw types CSV.
    /// @dev Strict mode as in `parse(...)`: no whitespace, name(types), name validity.
    /// @param signature The full signature string, e.g., "transfer(address,uint256)".
    /// @return selector The 4-byte function selector computed as bytes4(keccak256(signature)).
    /// @return typesCsv The comma-separated types.
    function parseSelectorAndTypes(string memory signature)
        internal
        pure
        returns (bytes4 selector, string memory typesCsv)
    {
        bytes memory signatureBytes = bytes(signature);
        uint256 openParenIndex = _scanAndValidate(signatureBytes);

        typesCsv = string(LibBytes.slice(signatureBytes, openParenIndex + 1, signatureBytes.length - 1));
        selector = bytes4(keccak256(signatureBytes));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Scans the signature, rejects whitespace, checks trailing ')', and validates the name.
    /// @param signatureBytes The signature as bytes.
    /// @return openParenIndex The index of the opening '('.
    function _scanAndValidate(bytes memory signatureBytes) private pure returns (uint256 openParenIndex) {
        uint256 signatureLength = signatureBytes.length;
        require(signatureLength > 2, MalformedSignature());

        bool found;
        for (uint256 i; i < signatureLength; ++i) {
            bytes1 char = signatureBytes[i];
            require(
                !(char == bytes1(0x20) || char == bytes1(0x09) || char == bytes1(0x0A) || char == bytes1(0x0D)),
                SignatureContainsWhitespace()
            );
            if (!found && char == "(") {
                found = true;
                openParenIndex = i;
            }
        }
        require(found && signatureBytes[signatureLength - 1] == ")", MalformedSignature());

        uint256 nameLength = openParenIndex;
        require(nameLength != 0, InvalidFunctionName());
        bytes1 firstChar = signatureBytes[0];
        require(_isAlpha(firstChar) || firstChar == "_", InvalidFunctionName());
        for (uint256 i = 1; i < nameLength; ++i) {
            bytes1 char = signatureBytes[i];
            require(_isAlphanum(char) || char == "_", InvalidFunctionName());
        }
    }

    /// @dev Returns true if `char` is an ASCII letter (A-Z or a-z).
    function _isAlpha(bytes1 char) private pure returns (bool) {
        return (char >= bytes1(0x41) && char <= bytes1(0x5A)) || (char >= bytes1(0x61) && char <= bytes1(0x7A));
    }

    /// @dev Returns true if `char` is an ASCII alphanumeric char.
    function _isAlphanum(bytes1 char) private pure returns (bool) {
        return _isAlpha(char) || (char >= bytes1(0x30) && char <= bytes1(0x39));
    }
}

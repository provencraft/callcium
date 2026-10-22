// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LibBytes } from "./vendor/solady/utils/LibBytes.sol";

/// @title SignatureParser
/// @notice Parses strict Solidity-style function signatures and computes the selector.
/// @dev Strict mode compatible with abi.encodeWithSignature expectations:
/// - No space, tab, LF or CR anywhere in the signature.
/// - Structure must be name(types) with the final ')' as the last byte.
/// - Function name must match [A-Za-z_][A-Za-z0-9_]*.
/// - Types are not validated here.
library SignatureParser {
    /*/////////////////////////////////////////////////////////////////////////
                                    ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the signature contains a space, tab, LF or CR.
    error SignatureContainsWhitespace();

    /// @notice Thrown when the signature does not follow the strict name(types) form.
    error MalformedSignature();

    /// @notice Thrown when the function name is empty or contains invalid chars.
    error InvalidFunctionName();

    /*/////////////////////////////////////////////////////////////////////////
                                    FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Parses a function signature and returns selector and the raw types CSV.
    /// @dev Strict: no whitespace, name(types), name validity.
    /// @param signature The full signature string, for example "transfer(address,uint256)".
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
        // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the selector, the hash's first four bytes.
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

        bool found = false;
        for (uint256 i = 0; i < signatureLength; ++i) {
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
        // An empty name leaves '(' first, which the first-character check rejects.
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SignatureParser } from "src/SignatureParser.sol";

import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for SignatureParser unit tests.
abstract contract SignatureParserTest is BaseTest {
    /// @dev Asserts that `signature` parses to the expected selector, name, and types.
    function assertParsesTo(
        string memory signature,
        bytes4 expectedSelector,
        string memory expectedName,
        string memory expectedTypesCsv
    )
        internal
        pure
    {
        (bytes4 sel, string memory name, string memory typesCsv) = SignatureParser.parse(signature);
        assertEq(sel, expectedSelector);
        assertEq(name, expectedName);
        assertEq(typesCsv, expectedTypesCsv);
    }
}

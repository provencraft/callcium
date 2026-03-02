// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SignatureParserTest } from "../SignatureParser.t.sol";

import { SignatureParser } from "src/SignatureParser.sol";

contract ParseSelectorAndTypesTest is SignatureParserTest {
    function test_ReturnsCorrectSelectorAndTypes() public pure {
        (bytes4 selector, string memory typesCsv) = SignatureParser.parseSelectorAndTypes("transfer(address,uint256)");

        assertEq(selector, bytes4(keccak256("transfer(address,uint256)")));
        assertEq(typesCsv, "address,uint256");
    }

    function test_HandlesComplexNestedTypes() public pure {
        string memory sig = "execute((address,uint256)[],bytes32)";
        (bytes4 selector, string memory typesCsv) = SignatureParser.parseSelectorAndTypes(sig);

        assertEq(selector, bytes4(keccak256(bytes(sig))));
        assertEq(typesCsv, "(address,uint256)[],bytes32");
    }

    function test_MatchesParseOutput() public pure {
        string memory sig = "transferFrom(address,address,uint256)";

        (bytes4 parseSelector,, string memory parseTypesCsv) = SignatureParser.parse(sig);
        (bytes4 leanSelector, string memory leanTypesCsv) = SignatureParser.parseSelectorAndTypes(sig);

        assertEq(leanSelector, parseSelector);
        assertEq(leanTypesCsv, parseTypesCsv);
    }
}

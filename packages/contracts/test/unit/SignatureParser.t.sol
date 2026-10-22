// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { SignatureParser } from "src/SignatureParser.sol";

contract SignatureParserParseSelectorAndTypesTest is Test {
    function test_ReturnsCorrectSelectorAndTypes() public pure {
        (bytes4 selector, string memory typesCsv) = SignatureParser.parseSelectorAndTypes("transfer(address,uint256)");

        assertEq(selector, bytes4(keccak256("transfer(address,uint256)")));
        assertEq(typesCsv, "address,uint256");
    }

    function test_AcceptsUnderscoresAndDigitsInName() public pure {
        (, string memory typesCsv) = SignatureParser.parseSelectorAndTypes("_set_owner2(address)");

        assertEq(typesCsv, "address");
    }

    function test_RevertWhen_TooShort() public {
        vm.expectRevert(SignatureParser.MalformedSignature.selector);
        SignatureParser.parseSelectorAndTypes("()");
    }

    function testFuzz_RevertWhen_ContainsWhitespace(uint256 seed) public {
        bytes1[4] memory whitespace = [bytes1(0x20), bytes1(0x09), bytes1(0x0A), bytes1(0x0D)];
        bytes1 char = whitespace[bound(seed, 0, whitespace.length - 1)];

        vm.expectRevert(SignatureParser.SignatureContainsWhitespace.selector);
        SignatureParser.parseSelectorAndTypes(string(bytes.concat("transfer(address,", char, "uint256)")));
    }

    function test_RevertWhen_NoOpeningParenthesis() public {
        vm.expectRevert(SignatureParser.MalformedSignature.selector);
        SignatureParser.parseSelectorAndTypes("transfer)");
    }

    function test_RevertWhen_NoClosingParenthesis() public {
        vm.expectRevert(SignatureParser.MalformedSignature.selector);
        SignatureParser.parseSelectorAndTypes("foo(uint256");
    }

    function test_RevertWhen_NameStartsWithDigit() public {
        vm.expectRevert(SignatureParser.InvalidFunctionName.selector);
        SignatureParser.parseSelectorAndTypes("1foo(uint256)");
    }

    function test_RevertWhen_NameHasNonAsciiCharacter() public {
        vm.expectRevert(SignatureParser.InvalidFunctionName.selector);
        SignatureParser.parseSelectorAndTypes(unicode"tránsfer(uint256)");
    }
}

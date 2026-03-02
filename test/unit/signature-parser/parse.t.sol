// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { SignatureParser } from "src/SignatureParser.sol";

import { SignatureParserTest } from "../SignatureParser.t.sol";

contract ParseTest is SignatureParserTest {
    /*/////////////////////////////////////////////////////////////////////////
                             VALID SIGNATURES
    /////////////////////////////////////////////////////////////////////////*/

    function test_ParsesSimpleSignature() public pure {
        assertParsesTo("transfer(address,uint256)", bytes4(0xa9059cbb), "transfer", "address,uint256");
    }

    function test_ParsesEmptyParams() public pure {
        assertParsesTo("foo()", bytes4(keccak256(bytes("foo()"))), "foo", "");
    }

    function test_UnderscoreName() public pure {
        (bytes4 sel, string memory name, string memory typesCsv) = SignatureParser.parse("_internal(uint256)");
        assertEq(name, "_internal");
        assertEq(typesCsv, "uint256");
        assertEq(sel, bytes4(keccak256(bytes("_internal(uint256)"))));
    }

    function test_DoubleUnderscoreName() public pure {
        (, string memory name,) = SignatureParser.parse("__init__()");
        assertEq(name, "__init__");
    }

    function test_MixedCaseName() public pure {
        (, string memory name,) = SignatureParser.parse("MyFunction(address)");
        assertEq(name, "MyFunction");
    }

    function test_SelectorCaseSensitive() public pure {
        (bytes4 selLower,,) = SignatureParser.parse("transfer(address)");
        (bytes4 selUpper,,) = SignatureParser.parse("Transfer(address)");
        assertTrue(selLower != selUpper);
    }

    /*/////////////////////////////////////////////////////////////////////////
                            INVALID SIGNATURES
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_ContainsWhitespace() public {
        vm.expectRevert(SignatureParser.SignatureContainsWhitespace.selector);
        SignatureParser.parse("transfer( address,uint256)");
    }

    function test_RevertWhen_ContainsWhitespace_Trailing() public {
        vm.expectRevert(SignatureParser.SignatureContainsWhitespace.selector);
        SignatureParser.parse("transfer(address,uint256) ");
    }

    function test_RevertWhen_ContainsWhitespace_Leading() public {
        vm.expectRevert(SignatureParser.SignatureContainsWhitespace.selector);
        SignatureParser.parse(" transfer()");
    }

    function test_RevertWhen_ContainsTab() public {
        vm.expectRevert(SignatureParser.SignatureContainsWhitespace.selector);
        SignatureParser.parse("transfer(\taddress)");
    }

    function test_RevertWhen_ContainsNewline() public {
        vm.expectRevert(SignatureParser.SignatureContainsWhitespace.selector);
        SignatureParser.parse("transfer(\naddress)");
    }

    function test_RevertWhen_MalformedSignature_NoOpenParen() public {
        vm.expectRevert(SignatureParser.MalformedSignature.selector);
        SignatureParser.parse("transfer-address,uint256)");
    }

    function test_RevertWhen_MalformedSignature_NoClosingParen() public {
        vm.expectRevert(SignatureParser.MalformedSignature.selector);
        SignatureParser.parse("transfer(address,uint256");
    }

    function test_RevertWhen_MalformedSignature_TrailingChars() public {
        vm.expectRevert(SignatureParser.MalformedSignature.selector);
        SignatureParser.parse("transfer()x");
    }

    function test_RevertWhen_MalformedSignature_TooShort() public {
        vm.expectRevert(SignatureParser.MalformedSignature.selector);
        SignatureParser.parse("()");
    }

    function test_RevertWhen_InvalidFunctionName_Empty() public {
        vm.expectRevert(SignatureParser.InvalidFunctionName.selector);
        SignatureParser.parse("(address)");
    }

    function test_RevertWhen_InvalidFunctionName_StartingWithDigit() public {
        vm.expectRevert(SignatureParser.InvalidFunctionName.selector);
        SignatureParser.parse("1foo(uint256)");
    }

    function test_RevertWhen_InvalidFunctionName_IllegalChar() public {
        vm.expectRevert(SignatureParser.InvalidFunctionName.selector);
        SignatureParser.parse("foo.bar(uint256)");
    }

    function test_RevertWhen_InvalidFunctionName_Hyphen() public {
        vm.expectRevert(SignatureParser.InvalidFunctionName.selector);
        SignatureParser.parse("my-func()");
    }

    function test_DelegatesTypeValidation_ToDescriptorBuilder() public {
        (, string memory name, string memory typesCsv) = SignatureParser.parse("x(uint)");
        assertEq(name, "x");
        assertEq(typesCsv, "uint");
        vm.expectRevert(DescriptorBuilder.UnknownType.selector);
        DescriptorBuilder.fromTypes(typesCsv);
    }
}

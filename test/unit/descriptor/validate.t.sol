// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorTest } from "../Descriptor.t.sol";
import { Descriptor } from "src/Descriptor.sol";
import { TypeRule } from "src/TypeRule.sol";

contract ValidateTest is DescriptorTest {
    /*/////////////////////////////////////////////////////////////////////////
                             VALID DESCRIPTORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_StaticArrayAddressMinLength() public pure {
        // Static array of address[1]: [code:80][meta:001007][elem:40][length:0001].
        Descriptor.validate(hex"010180001007400001");
    }

    function test_StaticArrayAddressMaxLength() public pure {
        // Static array of address[65535]: [code:80][meta:fff007][elem:40][length:ffff].
        // Note: staticWords = 0xfff (max 12-bit value), but actual count is limited.
        // For maxLength test, staticWords would overflow. Using 4095 words max.
        Descriptor.validate(hex"010180fff007400fff");
    }

    function test_TupleOneField() public pure {
        // Tuple of (address): [code:90][meta:001007][fieldCount:0001][field:40].
        Descriptor.validate(hex"010190001007000140");
    }

    function test_TupleOfArrayAddress() public pure {
        // Tuple of (uint256[]): [code:90][meta:00000b][fieldCount:0001][dynArray].
        // Inner dynArray: [81][000005][40] = 5 bytes.
        // Outer tuple: nodeLength = 1+3+2+5 = 11 = 0x00b, staticWords = 0 (dynamic).
        Descriptor.validate(hex"01019000000b00018100000540");
    }

    /*/////////////////////////////////////////////////////////////////////////
                           MALFORMED DESCRIPTORS
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_RevertWhen_UnknownTypeCode(uint8 code) public {
        vm.assume(!TypeRule.isValid(code));
        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnknownTypeCode.selector, code));
        Descriptor.validate(bytes.concat(hex"0101", bytes1(code)));
    }

    /*/////////////////////////////////////////////////////////////////////////
                         NODE LENGTH AND LIMIT CHECKS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_NodeLengthTooSmallForArray() public {
        // Dynamic array with nodeLength=3 (min is ARRAY_HEADER_SIZE=4): [code:81][meta:000003][elem:40].
        vm.expectRevert(abi.encodeWithSelector(Descriptor.NodeLengthTooSmall.selector, 2, uint16(3)));
        Descriptor.validate(hex"01018100000340");
    }

    function test_RevertWhen_NodeLengthTooSmallForTuple() public {
        // Tuple with nodeLength=5 (min is TUPLE_HEADER_SIZE=6): [code:90][meta:001005][fc:0001][field:40].
        vm.expectRevert(abi.encodeWithSelector(Descriptor.NodeLengthTooSmall.selector, 2, uint16(5)));
        Descriptor.validate(hex"01019000100500014000");
    }

    function test_RevertWhen_NestedInvalidComposite() public {
        // Tuple containing a static array with length=0.
        // Outer tuple: [code:90][meta][fieldCount:0001][inner array].
        // Inner static array: [code:80][meta:000007][elem:40][length:0000].
        // Inner nodeLength=7 = 4+1+2. Outer nodeLength = TUPLE_HEADER_SIZE(6) + 7 = 13 = 0x0d.
        // Inner staticWords=0 (length=0 → 0 words). Outer staticWords=0.
        vm.expectRevert(Descriptor.InvalidArrayLength.selector);
        Descriptor.validate(hex"01019000000d000180000007400000");
    }

    function test_NestedValidComposite() public pure {
        // Tuple containing a valid static array: address[2].
        // Inner static array: [code:80][meta:002007][elem:40][length:0002].
        // nodeLength=7, staticWords=2. Outer nodeLength=6+7=13=0x0d, staticWords=2.
        Descriptor.validate(hex"01019000200d0001800020074000" hex"02");
    }
}

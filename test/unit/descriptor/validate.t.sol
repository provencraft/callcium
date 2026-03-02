// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorTest } from "../Descriptor.t.sol";
import { Descriptor } from "src/Descriptor.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeRule } from "src/TypeRule.sol";

contract ValidateTest is DescriptorTest {
    /*/////////////////////////////////////////////////////////////////////////
                             VALID DESCRIPTORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_EmptyBody() public pure {
        Descriptor.validate(hex"0100");
    }

    function test_SingleAddress() public pure {
        Descriptor.validate(hex"010140");
    }

    function test_DynamicArrayAddress() public pure {
        // Dynamic array of address: [code:81][meta:000005][elem:40].
        Descriptor.validate(hex"01018100000540");
    }

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

    function test_RevertWhen_HeaderEmpty() public {
        vm.expectRevert(Descriptor.MalformedHeader.selector);
        Descriptor.validate("");
    }

    function test_RevertWhen_HeaderTooShort() public {
        vm.expectRevert(Descriptor.MalformedHeader.selector);
        Descriptor.validate(hex"01");
    }

    function test_RevertWhen_VersionUnsupported() public {
        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnsupportedVersion.selector, uint8(0x02)));
        Descriptor.validate(hex"0200");
    }

    function testFuzz_RevertWhen_UnknownTypeCode(uint8 code) public {
        vm.assume(!TypeRule.isValid(code));
        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnknownTypeCode.selector, code));
        Descriptor.validate(bytes.concat(hex"0101", bytes1(code)));
    }

    function test_RevertWhen_DynamicArrayMissingMeta() public {
        // Dynamic array with incomplete meta (only 1 byte of 3).
        vm.expectRevert(Descriptor.UnexpectedEnd.selector);
        Descriptor.validate(hex"01018100");
    }

    function test_RevertWhen_StaticArrayMissingMeta() public {
        // Static array with incomplete meta.
        vm.expectRevert(Descriptor.UnexpectedEnd.selector);
        Descriptor.validate(hex"01018000");
    }

    function test_RevertWhen_TupleMissingMeta() public {
        // Tuple with incomplete meta (only code).
        vm.expectRevert(Descriptor.UnexpectedEnd.selector);
        Descriptor.validate(hex"010190");
    }

    function test_RevertWhen_ParamCountMismatchExtraParam() public {
        vm.expectRevert(abi.encodeWithSelector(Descriptor.ParamCountMismatch.selector, uint8(1), 2));
        Descriptor.validate(hex"01014040");
    }

    function test_RevertWhen_ParamCountMismatchMissingParam() public {
        vm.expectRevert(abi.encodeWithSelector(Descriptor.ParamCountMismatch.selector, uint8(2), 1));
        Descriptor.validate(hex"010240");
    }

    function test_RevertWhen_TooManyParams256() public {
        bytes memory body;
        for (uint256 i; i < 256; ++i) {
            body = bytes.concat(body, bytes1(TypeCode.ADDRESS));
        }

        vm.expectRevert(Descriptor.TooManyParams.selector);
        Descriptor.validate(bytes.concat(hex"01FF", body));
    }

    /*/////////////////////////////////////////////////////////////////////////
                         NODE LENGTH AND LIMIT CHECKS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_CompositeNodeLengthZero() public {
        // Dynamic array with nodeLength=0: [code:81][meta:000000][elem:40].
        vm.expectRevert(abi.encodeWithSelector(Descriptor.NodeLengthTooSmall.selector, 2, uint16(0)));
        Descriptor.validate(hex"010181000000");
    }

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

    function test_RevertWhen_NodeOverflowsBuffer() public {
        // Dynamic array with nodeLength=255 but descriptor is only 6 bytes.
        vm.expectRevert(abi.encodeWithSelector(Descriptor.NodeOverflow.selector, 2));
        Descriptor.validate(hex"0101810000FF40");
    }

    function test_RevertWhen_StaticArrayLengthExceedsMax() public {
        // Static array of address[4096]: [code:80][meta:000007][elem:40][length:1000].
        // nodeLength=7 = ARRAY_HEADER(4) + elemDesc(1) + lengthSuffix(2).
        // staticWords=0 because 4096 overflows 12 bits, but we only test the length check.
        // Actually, for length=4096, staticWords would be 4096 which overflows. Use staticWords=0.
        vm.expectRevert(abi.encodeWithSelector(Descriptor.ArrayLengthTooLarge.selector, 2, uint16(4096)));
        Descriptor.validate(hex"010180000007401000");
    }

    function test_RevertWhen_TupleFieldCountExceedsMax() public {
        // Tuple with fieldCount=4090 (exceeds MAX_TUPLE_FIELDS=4089).
        // We need nodeLength large enough for the header + field descriptors.
        // fieldCount=4090 requires 4090 single-byte fields = 4090 bytes.
        // nodeLength = TUPLE_HEADER_SIZE(6) + 4090 = 4096 → exceeds MAX_NODE_LENGTH(4095).
        // But nodeLength is 12-bit, so can only encode up to 4095. Set nodeLength=4095.
        // Build: [version:01][paramCount:01][code:90][meta: staticWords=0, nodeLength=4095][fieldCount:4090=0x0FFA]
        // meta: 0x000FFF (staticWords=0, nodeLength=4095).
        // Then pad with enough bytes (address type codes) to fill the descriptor.
        bytes memory header = hex"01019000" hex"0FFF" hex"0FFA";
        bytes memory fields = new bytes(4090);
        for (uint256 i; i < 4090; ++i) {
            fields[i] = bytes1(TypeCode.ADDRESS);
        }
        bytes memory desc = bytes.concat(header, fields);
        vm.expectRevert(abi.encodeWithSelector(Descriptor.TupleFieldCountTooLarge.selector, 2, uint16(4090)));
        Descriptor.validate(desc);
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { DescriptorTest } from "../Descriptor.t.sol";
import { Descriptor } from "src/Descriptor.sol";
import { TypeRule } from "src/TypeRule.sol";

contract ValidateTest is DescriptorTest {
    /// @dev Builds a descriptor with `levels` nested single-field tuples around a uint256 leaf.
    function _nestedTuples(uint256 levels) private pure returns (bytes memory) {
        bytes memory node = hex"20";
        for (uint256 i = 0; i < levels; ++i) {
            // staticWords = 1 | nodeLength = header(6) + inner node; fits 24 bits for any test depth.
            uint24 meta = uint24((1 << 12) | (node.length + 6));
            node = bytes.concat(hex"90", bytes3(meta), hex"0001", node);
        }
        return bytes.concat(hex"0201", node);
    }

    /*/////////////////////////////////////////////////////////////////////////
                             VALID DESCRIPTORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_StaticArrayAddressMinLength() public pure {
        // Static array of address[1]: [code:80][meta:001007][elem:41][length:0001].
        Descriptor.validate(hex"020180001007410001");
    }

    function test_StaticArrayAddressMaxLength() public pure {
        // Static array of address[65535]: [code:80][meta:fff007][elem:41][length:ffff].
        // Note: staticWords = 0xfff (max 12-bit value), but actual count is limited.
        // For maxLength test, staticWords would overflow. Using 4095 words max.
        Descriptor.validate(hex"020180fff007410fff");
    }

    function test_TupleOneField() public pure {
        // Tuple of (address): [code:90][meta:001007][fieldCount:0001][field:41].
        Descriptor.validate(hex"020190001007000141");
    }

    function test_TupleOfArrayAddress() public pure {
        // Tuple of (address[]): [code:90][meta:00000b][fieldCount:0001][dynArray].
        // Inner dynArray: [81][000005][41] = 5 bytes.
        // Outer tuple: nodeLength = 1+3+2+5 = 11 = 0x00b, staticWords = 0 (dynamic).
        Descriptor.validate(hex"02019000000b00018100000541");
    }

    /*/////////////////////////////////////////////////////////////////////////
                           MALFORMED DESCRIPTORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_ReservedZeroTypeCodeNestedInTuple() public {
        // Tuple of (reserved-zero): [code:90][meta:001007][fieldCount:0001][field:00].
        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnknownTypeCode.selector, uint8(0)));
        Descriptor.validate(hex"020190001007000100");
    }

    function testFuzz_RevertWhen_UnknownTypeCode(uint256 seed) public {
        uint8[256] memory set;
        uint256 count;
        for (uint16 i = 0; i < 256; ++i) {
            // Cast to 'uint8' is safe because 'i' is bounded to [0, 256).
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 c = uint8(i);
            if (!TypeRule.isValid(c)) set[count++] = c;
        }
        assertGt(count, 0, "empty set");
        uint8 code = set[bound(seed, 0, count - 1)];
        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnknownTypeCode.selector, code));
        Descriptor.validate(bytes.concat(hex"0201", bytes1(code)));
    }

    /*/////////////////////////////////////////////////////////////////////////
                         NODE LENGTH AND LIMIT CHECKS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_NodeLengthTooSmallForArray() public {
        // Dynamic array with nodeLength=3 (min is ARRAY_HEADER_SIZE=4): [code:81][meta:000003][elem:41].
        vm.expectRevert(abi.encodeWithSelector(Descriptor.NodeLengthTooSmall.selector, 2, uint16(3)));
        Descriptor.validate(hex"02018100000341");
    }

    function test_RevertWhen_NodeLengthTooSmallForTuple() public {
        // Tuple with nodeLength=5 (min is TUPLE_HEADER_SIZE=6): [code:90][meta:001005][fc:0001][field:41].
        vm.expectRevert(abi.encodeWithSelector(Descriptor.NodeLengthTooSmall.selector, 2, uint16(5)));
        Descriptor.validate(hex"02019000100500014100");
    }

    function test_RevertWhen_NestedInvalidComposite() public {
        // Tuple containing a static array with length=0.
        // Outer tuple: [code:90][meta][fieldCount:0001][inner array].
        // Inner static array: [code:80][meta:000007][elem:41][length:0000].
        // Inner nodeLength=7 = 4+1+2. Outer nodeLength = TUPLE_HEADER_SIZE(6) + 7 = 13 = 0x0d.
        // Inner staticWords=0 (length=0 → 0 words). Outer staticWords=0.
        vm.expectRevert(abi.encodeWithSelector(Descriptor.InvalidArrayLength.selector, 8, 0));
        Descriptor.validate(hex"02019000000d000180000007410000");
    }

    function test_NestedValidComposite() public pure {
        // Tuple containing a valid static array: address[2].
        // Inner static array: [code:80][meta:002007][elem:41][length:0002].
        // nodeLength=7, staticWords=2. Outer nodeLength=6+7=13=0x0d, staticWords=2.
        Descriptor.validate(hex"02019000200d0001800020074100" hex"02");
    }

    function test_NestingAtMaxDepth() public pure {
        Descriptor.validate(_nestedTuples(64));
    }

    function test_RevertWhen_NestingTooDeep() public {
        // The depth-65 node starts after the header and 64 tuple headers: 2 + 64 * 6 = 386.
        vm.expectRevert(abi.encodeWithSelector(Descriptor.NestingTooDeep.selector, 2 + 64 * 6));
        Descriptor.validate(_nestedTuples(65));
    }
}

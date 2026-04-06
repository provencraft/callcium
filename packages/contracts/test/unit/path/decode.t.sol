// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Path } from "src/Path.sol";

import { PathTest } from "../Path.t.sol";

// forge-lint: disable-next-item(unsafe-typecast)
contract DecodeTest is PathTest {
    /*/////////////////////////////////////////////////////////////////////////
                                   BASIC DECODE
    /////////////////////////////////////////////////////////////////////////*/

    function test_SingleStep() public pure {
        bytes memory path = hex"0000";

        uint16[] memory result = Path.decode(path);

        assertEq(result.length, 1);
        assertEq(result[0], 0);
    }

    function test_SingleStep_NonZero() public pure {
        bytes memory path = hex"0102";

        uint16[] memory result = Path.decode(path);

        assertEq(result.length, 1);
        assertEq(result[0], 258);
    }

    function test_TwoSteps() public pure {
        bytes memory path = hex"00000001";

        uint16[] memory result = Path.decode(path);

        assertEq(result.length, 2);
        assertEq(result[0], 0);
        assertEq(result[1], 1);
    }

    function test_ThreeSteps() public pure {
        bytes memory path = hex"000000010002";

        uint16[] memory result = Path.decode(path);

        assertEq(result.length, 3);
        assertEq(result[0], 0);
        assertEq(result[1], 1);
        assertEq(result[2], 2);
    }

    function test_FourSteps() public pure {
        bytes memory path = hex"0000000100020003";

        uint16[] memory result = Path.decode(path);

        assertEq(result.length, 4);
        assertEq(result[0], 0);
        assertEq(result[1], 1);
        assertEq(result[2], 2);
        assertEq(result[3], 3);
    }

    function test_MaxValues() public pure {
        bytes memory path = hex"ffff";

        uint16[] memory result = Path.decode(path);

        assertEq(result.length, 1);
        assertEq(result[0], type(uint16).max);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 ODD LENGTH HANDLING
    /////////////////////////////////////////////////////////////////////////*/

    function test_OddLength_IgnoresTrailingByte() public pure {
        bytes memory path = hex"000000";

        uint16[] memory result = Path.decode(path);

        assertEq(result.length, 1);
        assertEq(result[0], 0);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   EMPTY INPUT
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_EmptyPath() public {
        bytes memory path = "";

        vm.expectRevert(Path.EmptyPath.selector);
        Path.decode(path);
    }

    function test_RevertWhen_SingleByte() public {
        bytes memory path = hex"00";

        vm.expectRevert(Path.EmptyPath.selector);
        Path.decode(path);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    ROUND-TRIP
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_RoundTrip_SingleStep(uint16 index) public pure {
        bytes memory encoded = Path.encode(index);
        uint16[] memory decoded = Path.decode(encoded);

        assertEq(decoded.length, 1);
        assertEq(decoded[0], index);
    }

    function testFuzz_RoundTrip_FourSteps(uint16 p0, uint16 p1, uint16 p2, uint16 p3) public pure {
        bytes memory encoded = Path.encode(p0, p1, p2, p3);
        uint16[] memory decoded = Path.decode(encoded);

        assertEq(decoded.length, 4);
        assertEq(decoded[0], p0);
        assertEq(decoded[1], p1);
        assertEq(decoded[2], p2);
        assertEq(decoded[3], p3);
    }

    function testFuzz_RoundTrip_Array(uint256 length) public pure {
        length = bound(length, 1, 20);

        uint16[] memory original = new uint16[](length);
        for (uint256 i; i < length; ++i) {
            original[i] = uint16(i * 100);
        }

        bytes memory encoded = Path.encode(original);
        uint16[] memory decoded = Path.decode(encoded);

        assertEq(decoded.length, original.length);
        for (uint256 i; i < length; ++i) {
            assertEq(decoded[i], original[i]);
        }
    }
}

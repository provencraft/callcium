// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Path } from "src/Path.sol";

import { PathTest } from "../Path.t.sol";

// forge-lint: disable-next-item(unsafe-typecast)
contract AtTest is PathTest {
    /*/////////////////////////////////////////////////////////////////////////
                                     BASIC AT
    /////////////////////////////////////////////////////////////////////////*/

    function test_SingleStep_IndexZero() public pure {
        bytes memory path = hex"0005";

        uint16 result = Path.at(path, 0);

        assertEq(result, 5);
    }

    function test_TwoSteps_IndexZero() public pure {
        bytes memory path = hex"000a0014";

        uint16 result = Path.at(path, 0);

        assertEq(result, 10);
    }

    function test_TwoSteps_IndexOne() public pure {
        bytes memory path = hex"000a0014";

        uint16 result = Path.at(path, 1);

        assertEq(result, 20);
    }

    function test_FourSteps_AllIndices() public pure {
        bytes memory path = hex"0064012801f4025a";

        assertEq(Path.at(path, 0), 100);
        assertEq(Path.at(path, 1), 296);
        assertEq(Path.at(path, 2), 500);
        assertEq(Path.at(path, 3), 602);
    }

    function test_MaxValue() public pure {
        bytes memory path = hex"ffff";

        uint16 result = Path.at(path, 0);

        assertEq(result, type(uint16).max);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   BOUNDS ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_EmptyPath() public {
        bytes memory path = "";

        vm.expectRevert(abi.encodeWithSelector(Path.IndexOutOfBounds.selector, 0, 0));
        Path.at(path, 0);
    }

    function test_RevertWhen_IndexEqualsDepth() public {
        bytes memory path = hex"0000";

        vm.expectRevert(abi.encodeWithSelector(Path.IndexOutOfBounds.selector, 1, 1));
        Path.at(path, 1);
    }

    function test_RevertWhen_IndexExceedsDepth() public {
        bytes memory path = hex"00000001";

        vm.expectRevert(abi.encodeWithSelector(Path.IndexOutOfBounds.selector, 5, 2));
        Path.at(path, 5);
    }

    function test_OddLengthPath_ValidateRejectsButAtUsesFloorDepth() public {
        bytes memory oddPath = hex"0005FF";

        vm.expectRevert(Path.MalformedPath.selector);
        Path.validate(oddPath);

        assertEq(Path.at(oddPath, 0), 5);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  PROPERTY TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_MatchesDecode(uint16 p0, uint16 p1, uint16 p2, uint16 p3) public pure {
        bytes memory encoded = Path.encode(p0, p1, p2, p3);
        uint16[] memory decoded = Path.decode(encoded);

        assertEq(Path.at(encoded, 0), decoded[0]);
        assertEq(Path.at(encoded, 1), decoded[1]);
        assertEq(Path.at(encoded, 2), decoded[2]);
        assertEq(Path.at(encoded, 3), decoded[3]);
    }

    function testFuzz_ValidIndex(uint256 length, uint256 index) public pure {
        length = bound(length, 1, 20);
        index = bound(index, 0, length - 1);

        uint16[] memory path = new uint16[](length);
        for (uint256 i; i < length; ++i) {
            path[i] = uint16(i * 7);
        }

        bytes memory encoded = Path.encode(path);
        uint16 result = Path.at(encoded, index);

        assertEq(result, path[index]);
    }

    function testFuzz_RevertWhen_InvalidIndex(uint256 length, uint256 index) public {
        length = bound(length, 1, 20);
        index = bound(index, length, type(uint256).max);

        uint16[] memory path = new uint16[](length);
        for (uint256 i; i < length; ++i) {
            path[i] = uint16(i);
        }

        bytes memory encoded = Path.encode(path);

        vm.expectRevert(abi.encodeWithSelector(Path.IndexOutOfBounds.selector, index, length));
        Path.at(encoded, index);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  UNCHECKED
    /////////////////////////////////////////////////////////////////////////*/

    function test_AtUnchecked_IndexZero() public pure {
        bytes memory path = hex"0005";

        uint16 a = Path.at(path, 0);
        uint16 b = Path.atUnchecked(path, 0);

        assertEq(a, b);
    }

    function test_AtUnchecked_LastIndex() public pure {
        bytes memory path = hex"000a0014";

        uint16 a = Path.at(path, 1);
        uint16 b = Path.atUnchecked(path, 1);

        assertEq(a, b);
    }

    function testFuzz_AtUnchecked_MatchesAt(uint256 length, uint256 index) public pure {
        length = bound(length, 1, 20);
        index = bound(index, 0, length - 1);

        uint16[] memory steps = new uint16[](length);
        for (uint256 i; i < length; ++i) {
            steps[i] = uint16(i * 7);
        }

        bytes memory encoded = Path.encode(steps);

        assertEq(Path.atUnchecked(encoded, index), Path.at(encoded, index));
    }
}

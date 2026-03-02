// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Path } from "src/Path.sol";

import { PathTest } from "../Path.t.sol";

// forge-lint: disable-next-item(unsafe-typecast)
contract DepthTest is PathTest {
    /*/////////////////////////////////////////////////////////////////////////
                                    BASIC DEPTH
    /////////////////////////////////////////////////////////////////////////*/

    function test_Empty() public pure {
        bytes memory path = "";

        uint256 result = Path.depth(path);

        assertEq(result, 0);
    }

    function test_SingleStep() public pure {
        bytes memory path = hex"0000";

        uint256 result = Path.depth(path);

        assertEq(result, 1);
    }

    function test_TwoSteps() public pure {
        bytes memory path = hex"00000001";

        uint256 result = Path.depth(path);

        assertEq(result, 2);
    }

    function test_ThreeSteps() public pure {
        bytes memory path = hex"000000010002";

        uint256 result = Path.depth(path);

        assertEq(result, 3);
    }

    function test_FourSteps() public pure {
        bytes memory path = hex"0000000100020003";

        uint256 result = Path.depth(path);

        assertEq(result, 4);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 ODD LENGTH HANDLING
    /////////////////////////////////////////////////////////////////////////*/

    function test_OddLength_Truncates() public pure {
        bytes memory path = hex"000000";

        uint256 result = Path.depth(path);

        assertEq(result, 1);
    }

    function test_SingleByte() public pure {
        bytes memory path = hex"00";

        uint256 result = Path.depth(path);

        assertEq(result, 0);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  PROPERTY TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_MatchesEncodeLength(uint256 stepCount) public pure {
        stepCount = bound(stepCount, 1, 50);

        uint16[] memory path = new uint16[](stepCount);
        for (uint256 i; i < stepCount; ++i) {
            path[i] = uint16(i);
        }

        bytes memory encoded = Path.encode(path);
        uint256 result = Path.depth(encoded);

        assertEq(result, stepCount);
    }
}

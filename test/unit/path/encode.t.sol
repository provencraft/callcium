// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Path } from "src/Path.sol";

import { PathTest } from "../Path.t.sol";

// forge-lint: disable-next-item(unsafe-typecast)
contract EncodeTest is PathTest {
    /*/////////////////////////////////////////////////////////////////////////
                                 VARIADIC OVERLOADS
    /////////////////////////////////////////////////////////////////////////*/

    function test_SingleStep() public pure {
        bytes memory result = Path.encode(0);

        assertEq(result.length, 2);
        assertEq(result, hex"0000");
    }

    function test_SingleStep_NonZero() public pure {
        bytes memory result = Path.encode(258);

        assertEq(result.length, 2);
        assertEq(result, hex"0102");
    }

    function test_TwoSteps() public pure {
        bytes memory result = Path.encode(0, 1);

        assertEq(result.length, 4);
        assertEq(result, hex"00000001");
    }

    function test_TwoSteps_LargeValues() public pure {
        bytes memory result = Path.encode(256, 512);

        assertEq(result.length, 4);
        assertEq(result, hex"01000200");
    }

    function test_ThreeSteps() public pure {
        bytes memory result = Path.encode(0, 1, 2);

        assertEq(result.length, 6);
        assertEq(result, hex"000000010002");
    }

    function test_FourSteps() public pure {
        bytes memory result = Path.encode(0, 1, 2, 3);

        assertEq(result.length, 8);
        assertEq(result, hex"0000000100020003");
    }

    function test_FourSteps_MaxValues() public pure {
        bytes memory result = Path.encode(type(uint16).max, type(uint16).max, type(uint16).max, type(uint16).max);

        assertEq(result.length, 8);
        assertEq(result, hex"ffffffffffffffff");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   ARRAY OVERLOAD
    /////////////////////////////////////////////////////////////////////////*/

    function test_Array_SingleElement() public pure {
        uint16[] memory path = new uint16[](1);
        path[0] = 5;

        bytes memory result = Path.encode(path);

        assertEq(result.length, 2);
        assertEq(result, hex"0005");
    }

    function test_Array_MultipleElements() public pure {
        uint16[] memory path = new uint16[](3);
        path[0] = 0;
        path[1] = 10;
        path[2] = 255;

        bytes memory result = Path.encode(path);

        assertEq(result.length, 6);
        assertEq(result, hex"0000000a00ff");
    }

    function test_Array_FiveElements() public pure {
        uint16[] memory path = new uint16[](5);
        path[0] = 0;
        path[1] = 1;
        path[2] = 2;
        path[3] = 3;
        path[4] = 4;

        bytes memory result = Path.encode(path);

        assertEq(result.length, 10);
        assertEq(result, hex"00000001000200030004");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   EMPTY ARRAY
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_EmptyArray() public {
        uint16[] memory path = new uint16[](0);

        vm.expectRevert(Path.EmptyPath.selector);
        Path.encode(path);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                ENCODING ROUND-TRIP
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_SingleStep(uint16 index) public pure {
        bytes memory result = Path.encode(index);

        assertEq(result.length, 2);
        assertEq(uint8(result[0]), uint8(index >> 8));
        assertEq(uint8(result[1]), uint8(index));
    }

    function testFuzz_TwoSteps(uint16 p0, uint16 p1) public pure {
        bytes memory result = Path.encode(p0, p1);

        assertEq(result.length, 4);
        assertEq(uint8(result[0]), uint8(p0 >> 8));
        assertEq(uint8(result[1]), uint8(p0));
        assertEq(uint8(result[2]), uint8(p1 >> 8));
        assertEq(uint8(result[3]), uint8(p1));
    }
}

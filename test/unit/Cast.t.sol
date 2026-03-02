// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { Cast } from "src/Cast.sol";

contract CastTest is Test {
    using Cast for bytes4[];
    using Cast for uint32[];
    using Cast for int32[];

    function test_ToBytes32Array() public pure {
        bytes4[] memory input = new bytes4[](2);
        input[0] = 0x12345678;
        input[1] = 0xabcdef01;

        bytes32[] memory result = input.toBytes32Array();
        assertEq(result.length, 2);
        assertEq(result[0], bytes32(input[0]));
        assertEq(result[1], bytes32(input[1]));
    }

    function test_ToUint256Array() public pure {
        uint32[] memory input = new uint32[](2);
        input[0] = 100;
        input[1] = 200;

        uint256[] memory result = input.toUint256Array();
        assertEq(result.length, 2);
        assertEq(result[0], 100);
        assertEq(result[1], 200);
    }

    function test_ToInt256Array() public pure {
        int32[] memory input = new int32[](2);
        input[0] = -1;
        input[1] = 1;

        int256[] memory result = input.toInt256Array();
        assertEq(result.length, 2);
        assertEq(result[0], -1);
        assertEq(result[1], 1);
    }
}

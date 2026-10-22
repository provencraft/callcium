// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Path } from "src/Path.sol";

contract PathEncodeTest is Test {
    function test_FourSteps() public pure {
        bytes memory result = Path.encode(0, 1, 2, 3);

        assertEq(result.length, 8);
        assertEq(result, hex"0000000100020003");
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

    function test_RevertWhen_EmptyArray() public {
        uint16[] memory path = new uint16[](0);

        vm.expectRevert(Path.EmptyPath.selector);
        Path.encode(path);
    }
}

contract PathValidateTest is Test {
    function test_RevertWhen_EmptyPath() public {
        bytes memory path = new bytes(0);
        vm.expectRevert(Path.EmptyPath.selector);
        Path.validate(path);
    }
}

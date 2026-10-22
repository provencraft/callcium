// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Be16 } from "src/Be16.sol";

contract Be16WriteTest is Test {
    function test_RevertWhen_OutOfBounds() public {
        bytes memory data = new bytes(2);
        vm.expectRevert(Be16.OutOfBounds.selector);
        Be16.write(data, 1, 1);
    }
}

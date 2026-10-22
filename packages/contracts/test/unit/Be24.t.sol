// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Be24 } from "src/Be24.sol";

contract Be24WriteTest is Test {
    function test_RevertWhen_OutOfBounds() public {
        bytes memory data = new bytes(3);
        vm.expectRevert(Be24.OutOfBounds.selector);
        Be24.write(data, 1, 1);
    }
}

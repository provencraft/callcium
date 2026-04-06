// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorTest } from "../Descriptor.t.sol";
import { Descriptor } from "src/Descriptor.sol";

contract VersionTest is DescriptorTest {
    function test_ReturnsHeaderVersion() public pure {
        assertEq(Descriptor.version(hex"01"), 1);
    }

    function test_RevertWhen_MalformedHeader() public {
        vm.expectRevert(Descriptor.MalformedHeader.selector);
        Descriptor.version("");
    }
}

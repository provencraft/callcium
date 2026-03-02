// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorTest } from "../Descriptor.t.sol";
import { Descriptor } from "src/Descriptor.sol";

contract ParamCountTest is DescriptorTest {
    function test_ReturnsHeaderCount() public pure {
        assertEq(Descriptor.paramCount(hex"0103"), 3);
    }

    function test_RevertWhen_MalformedHeader() public {
        vm.expectRevert(Descriptor.MalformedHeader.selector);
        Descriptor.paramCount(hex"01");
    }
}

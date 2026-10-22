// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Descriptor } from "src/Descriptor.sol";

contract DescriptorValidateMetaTest is Test {
    function test_RevertWhen_NodeLengthDiffersFromSpan() public {
        // Tuple of (uint256,uint256) declaring nodeLength 9 over fields spanning 8:
        // [code:90][meta:002009][fieldCount:0002][fields:2020][trailing:20].
        vm.expectRevert(abi.encodeWithSelector(Descriptor.NodeLengthMismatch.selector, 2));
        Descriptor.validateMeta(hex"0201900020090002202020");
    }

    function test_RevertWhen_InnerNodeDisagreesNamesTheInnerNode() public {
        // Tuple of ((uint256,bytes)) whose inner tuple, at offset 8, declares staticWords 2:
        // [code:90][meta:00000e][fieldCount:0001][inner:90 002008 0002 2070].
        vm.expectRevert(abi.encodeWithSelector(Descriptor.StaticWordsMismatch.selector, 8));
        Descriptor.validateMeta(hex"02019000000e00019000200800022070");
    }

    function test_RevertWhen_ArrayElementDisagreesNamesTheElement() public {
        // Dynamic array of (uint256,bytes) whose element, at offset 6, declares staticWords 2:
        // [code:81][meta:00000c][element:90 002008 0002 2070].
        vm.expectRevert(abi.encodeWithSelector(Descriptor.StaticWordsMismatch.selector, 6));
        Descriptor.validateMeta(hex"02018100000c9000200800022070");
    }
}

contract DescriptorInspectTest is Test {
    function test_RevertWhen_OffsetOutOfBounds() public {
        bytes memory desc = hex"020141";
        vm.expectRevert(Descriptor.UnexpectedEnd.selector);
        Descriptor.inspect(desc, 3);
    }
}

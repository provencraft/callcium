// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorTest } from "../Descriptor.t.sol";

import { DescriptorFormat as DF } from "src/DescriptorFormat.sol";
import { TypeDesc } from "src/TypeDesc.sol";

contract TypeDescErrorsTest is DescriptorTest {
    function test_RevertWhen_ArrayProductTooLarge() public {
        // Inner: address[DF.MAX_STATIC_ARRAY_LENGTH] has staticWords = DF.MAX_STATIC_ARRAY_LENGTH.
        bytes memory inner = TypeDesc.array_(TypeDesc.address_(), uint16(DF.MAX_STATIC_ARRAY_LENGTH));
        // Outer: length 2 causes 2 * DF.MAX_STATIC_ARRAY_LENGTH > DF.MAX_STATIC_WORDS.
        uint256 product = DF.MAX_STATIC_ARRAY_LENGTH * 2;
        vm.expectRevert(abi.encodeWithSelector(TypeDesc.ArrayProductTooLarge.selector, product, DF.MAX_STATIC_WORDS));
        TypeDesc.array_(inner, 2);
    }

    function test_RevertWhen_NodeLengthTooLarge() public {
        // Craft an oversized element descriptor to exceed DF.MAX_NODE_LENGTH in a composite node.
        bytes memory huge = new bytes(DF.MAX_NODE_LENGTH);
        // Array header (4 bytes) + element descriptor (4095) = 4099.
        uint256 nodeLength = DF.ARRAY_HEADER_SIZE + DF.MAX_NODE_LENGTH;
        vm.expectRevert(abi.encodeWithSelector(TypeDesc.NodeLengthTooLarge.selector, nodeLength, DF.MAX_NODE_LENGTH));
        TypeDesc.array_(huge);
    }
}

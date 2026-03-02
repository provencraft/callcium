// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorBuilderTest } from "../DescriptorBuilder.t.sol";
import { Descriptor } from "src/Descriptor.sol";
import { DescriptorBuilder, DescriptorDraft } from "src/DescriptorBuilder.sol";
import { TypeDesc } from "src/TypeDesc.sol";

contract AddTest is DescriptorBuilderTest {
    function test_RevertWhen_TooManyParams() public {
        DescriptorDraft memory draft = DescriptorBuilder.create();
        for (uint256 i; i < 255; ++i) {
            draft = draft.add(TypeDesc.address_());
        }

        vm.expectRevert(Descriptor.TooManyParams.selector);
        draft.add(TypeDesc.address_());
    }
}

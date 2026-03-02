// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorTest } from "../Descriptor.t.sol";
import { TypeDesc } from "src/TypeDesc.sol";

contract TypeDescStructTest is DescriptorTest {
    function test_Struct_SingleField() public pure {
        bytes memory s = TypeDesc.struct_(TypeDesc.address_());
        bytes memory t = TypeDesc.tuple_(TypeDesc.address_());
        assertEq(keccak256(s), keccak256(t));
    }

    function test_Struct_MultipleFields() public pure {
        bytes memory s = TypeDesc.struct_(TypeDesc.address_(), TypeDesc.uintN_(16));
        bytes memory t = TypeDesc.tuple_(TypeDesc.address_(), TypeDesc.uintN_(16));
        assertEq(keccak256(s), keccak256(t));
    }

    function test_Struct_MatchesTuple() public pure {
        bytes memory s = TypeDesc.struct_(TypeDesc.address_(), TypeDesc.uintN_(16), TypeDesc.bytesN_(3));
        bytes memory t = TypeDesc.tuple_(TypeDesc.address_(), TypeDesc.uintN_(16), TypeDesc.bytesN_(3));
        assertEq(keccak256(s), keccak256(t));
    }
}

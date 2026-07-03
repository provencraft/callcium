// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Descriptor } from "src/Descriptor.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { Path } from "src/Path.sol";
import { TypeCode } from "src/TypeCode.sol";

import { DescriptorTest } from "../Descriptor.t.sol";

contract WalkPathTest is DescriptorTest {
    using Descriptor for bytes;

    function test_NoQuantifier_ZeroLength() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256");

        (Descriptor.TypeInfo memory t, uint256 length) = desc.walkPath(_path(0));

        assertEq(t.code, TypeCode.UINT256);
        assertEq(length, 0);
    }

    function test_QuantifierOverStaticArray_ReturnsDeclaredLength() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");

        (Descriptor.TypeInfo memory t, uint256 length) = desc.walkPath(_path(0, Path.ALL));

        assertEq(t.code, TypeCode.UINT256);
        assertEq(length, 3);
    }

    function test_AllSentinels_ReturnDeclaredLength() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address[7]");

        (, uint256 all) = desc.walkPath(_path(0, Path.ALL));
        (, uint256 any) = desc.walkPath(_path(0, Path.ANY));
        (, uint256 allOrEmpty) = desc.walkPath(_path(0, Path.ALL_OR_EMPTY));

        assertEq(all, 7);
        assertEq(any, 7);
        assertEq(allOrEmpty, 7);
    }

    function test_QuantifierOverDynamicArray_ZeroLength() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");

        (Descriptor.TypeInfo memory t, uint256 length) = desc.walkPath(_path(0, Path.ALL));

        assertEq(t.code, TypeCode.UINT256);
        assertEq(length, 0);
    }

    function test_ConcreteIndexIntoStaticArray_ZeroLength() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");

        (, uint256 length) = desc.walkPath(_path(0, 1));

        assertEq(length, 0);
    }

    function test_QuantifierUnderTuple_ReturnsDeclaredLength() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256[5])");

        (Descriptor.TypeInfo memory t, uint256 length) = desc.walkPath(_path(0, 1, Path.ALL));

        assertEq(t.code, TypeCode.UINT256);
        assertEq(length, 5);
    }

    function test_SuffixAfterQuantifier_ReturnsLengthAndFieldType() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)[4]");

        (Descriptor.TypeInfo memory t, uint256 length) = desc.walkPath(_path(0, Path.ALL, 1));

        assertEq(t.code, TypeCode.UINT256);
        assertEq(length, 4);
    }
}

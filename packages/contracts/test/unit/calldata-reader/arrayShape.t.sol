// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CalldataReader } from "src/CalldataReader.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { TypeCode } from "src/TypeCode.sol";

import { CalldataReaderTest } from "../CalldataReader.t.sol";

// forge-lint: disable-next-item(unsafe-typecast, named-struct-fields)
contract ArrayShapeTest is CalldataReaderTest {
    /*/////////////////////////////////////////////////////////////////////////
                               DYNAMIC ARRAY + STATIC ELEM
    /////////////////////////////////////////////////////////////////////////*/

    function test_DynamicArrayStaticElem() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(uint256,uint256)[]");
        TwoUints[] memory arr = new TwoUints[](3);
        arr[0] = TwoUints(1, 2);
        arr[1] = TwoUints(3, 4);
        arr[2] = TwoUints(5, 6);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.ArrayShape memory shape = harness.arrayShape(desc, callData, _path(0), cfg);

        assertFalse(shape.elementIsDynamic);
        assertEq(shape.elementStaticSize, 64);
        assertEq(shape.elementTypeCode, TypeCode.TUPLE);
        assertEq(shape.length, 3);
        assertEq(shape.dataOffset, shape.compositeBase + 32);
    }

    /*/////////////////////////////////////////////////////////////////////////
                               DYNAMIC ARRAY + DYNAMIC ELEM
    /////////////////////////////////////////////////////////////////////////*/

    function test_DynamicArrayDynamicElem() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes[]");
        bytes[] memory arr = new bytes[](2);
        arr[0] = hex"0102";
        arr[1] = hex"030405";
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.ArrayShape memory shape = harness.arrayShape(desc, callData, _path(0), cfg);

        assertTrue(shape.elementIsDynamic);
        assertEq(shape.elementStaticSize, 0);
        assertEq(shape.elementTypeCode, TypeCode.BYTES);
        assertEq(shape.length, 2);
        assertEq(shape.headsOffset, shape.compositeBase);
    }

    /*/////////////////////////////////////////////////////////////////////////
                               STATIC ARRAY + STATIC ELEM
    /////////////////////////////////////////////////////////////////////////*/

    function test_StaticArrayStaticElem() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");
        uint256[3] memory arr = [uint256(10), 20, 30];
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.ArrayShape memory shape = harness.arrayShape(desc, callData, _path(0), cfg);

        assertFalse(shape.elementIsDynamic);
        assertEq(shape.elementStaticSize, 32);
        assertEq(shape.elementTypeCode, TypeCode.UINT256);
        assertEq(shape.length, 3);
        assertEq(shape.dataOffset, 4);
    }

    /*/////////////////////////////////////////////////////////////////////////
                               STATIC ARRAY + DYNAMIC ELEM
    /////////////////////////////////////////////////////////////////////////*/

    function test_StaticArrayDynamicElem() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("string[2]");
        string[2] memory arr = ["hello", "world"];
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.ArrayShape memory shape = harness.arrayShape(desc, callData, _path(0), cfg);

        assertTrue(shape.elementIsDynamic);
        assertEq(shape.elementStaticSize, 0);
        assertEq(shape.elementTypeCode, TypeCode.STRING);
        assertEq(shape.length, 2);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              NON-ARRAY REJECTION
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_NotArray() public {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, uint256(42));

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NotComposite.selector, TypeCode.UINT256));
        harness.arrayShape(desc, callData, _path(0), cfg);
    }
}

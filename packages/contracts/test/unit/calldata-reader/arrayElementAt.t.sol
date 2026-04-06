// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CalldataReader } from "src/CalldataReader.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { TypeCode } from "src/TypeCode.sol";

import { CalldataReaderTest } from "../CalldataReader.t.sol";

// forge-lint: disable-next-item(unsafe-typecast, named-struct-fields)
contract ArrayElementAtTest is CalldataReaderTest {
    /*/////////////////////////////////////////////////////////////////////////
                                  STATIC ELEMENTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_StaticElemStride() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(uint256,uint256)[]");
        TwoUints[] memory arr = new TwoUints[](3);
        arr[0] = TwoUints(100, 200);
        arr[1] = TwoUints(300, 400);
        arr[2] = TwoUints(500, 600);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.ArrayShape memory shape = harness.arrayShape(desc, callData, _path(0), cfg);
        CalldataReader.Location memory elem1 = harness.arrayElementAt(shape, 1, callData);

        assertEq(elem1.head, shape.dataOffset + 64);
        assertEq(elem1.typeInfo.code, TypeCode.TUPLE);
        assertFalse(elem1.typeInfo.isDynamic);
        assertEq(elem1.typeInfo.staticSize, 64);

        CalldataReader.Location memory elem1Field0 = harness.locate(desc, callData, _path(0, 1, 0), cfg);
        bytes32 word = harness.loadScalar(elem1Field0, callData);
        assertEq(uint256(word), 300);
    }

    function test_StaticArrayStaticElem() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");
        uint256[3] memory arr = [uint256(111), 222, 333];
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.ArrayShape memory shape = harness.arrayShape(desc, callData, _path(0), cfg);
        CalldataReader.Location memory elem2 = harness.arrayElementAt(shape, 2, callData);

        assertEq(elem2.head, shape.dataOffset + 64);

        bytes32 word = harness.loadScalar(elem2, callData);
        assertEq(uint256(word), 333);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 DYNAMIC ELEMENTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_DynamicElemStride() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes[]");
        bytes[] memory arr = new bytes[](3);
        arr[0] = hex"01";
        arr[1] = hex"0203";
        arr[2] = hex"040506";
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.ArrayShape memory shape = harness.arrayShape(desc, callData, _path(0), cfg);
        CalldataReader.Location memory elem2 = harness.arrayElementAt(shape, 2, callData);

        assertEq(elem2.head, shape.headsOffset + 64);
        assertEq(elem2.typeInfo.code, TypeCode.BYTES);
        assertTrue(elem2.typeInfo.isDynamic);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  OUT OF BOUNDS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_IndexOutOfBounds() public {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");
        uint256[] memory arr = new uint256[](2);
        arr[0] = 1;
        arr[1] = 2;
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.ArrayShape memory shape = harness.arrayShape(desc, callData, _path(0), cfg);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.ArrayIndexOutOfBounds.selector, 5, 2));
        harness.arrayElementAt(shape, 5, callData);
    }
}

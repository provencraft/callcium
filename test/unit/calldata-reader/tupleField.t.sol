// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CalldataReader } from "src/CalldataReader.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeDesc } from "src/TypeDesc.sol";

import { CalldataReaderTest } from "../CalldataReader.t.sol";

// forge-lint: disable-next-item(unsafe-typecast, named-struct-fields)
contract TupleFieldTest is CalldataReaderTest {
    struct NestedTuple {
        SimpleTuple inner;
        uint256 outer;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   STATIC TUPLES
    /////////////////////////////////////////////////////////////////////////*/

    function test_StaticTuple_FirstAndSecondField() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), uint256(42));

        CalldataReader.Location memory tupleLoc = harness.locate(desc, callData, _path(0), cfg);

        CalldataReader.Location memory addressField = harness.tupleField(desc, tupleLoc, 0, callData);
        CalldataReader.Location memory uint256Field = harness.tupleField(desc, tupleLoc, 1, callData);

        CalldataReader.Location memory expectedAddress = harness.locate(desc, callData, _path(0, 0), cfg);
        CalldataReader.Location memory expectedUint256 = harness.locate(desc, callData, _path(0, 1), cfg);

        _assertLocationMatches(addressField, expectedAddress);
        assertEq(addressField.typeInfo.code, TypeCode.ADDRESS);

        _assertLocationMatches(uint256Field, expectedUint256);
        assertEq(uint256Field.typeInfo.code, TypeCode.UINT256);

        bytes32 addressWord = harness.loadScalar(addressField, callData);
        bytes32 uint256Word = harness.loadScalar(uint256Field, callData);
        assertEq(address(uint160(uint256(addressWord))), address(1));
        assertEq(uint256(uint256Word), 42);
    }

    function test_StaticTuple_ThreeFields_MiddleAccess() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256,bool)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), uint256(42), true);

        CalldataReader.Location memory tupleLoc = harness.locate(desc, callData, _path(0), cfg);

        CalldataReader.Location memory addressField = harness.tupleField(desc, tupleLoc, 0, callData);
        CalldataReader.Location memory uint256Field = harness.tupleField(desc, tupleLoc, 1, callData);
        CalldataReader.Location memory boolField = harness.tupleField(desc, tupleLoc, 2, callData);

        assertEq(addressField.typeInfo.code, TypeCode.ADDRESS);
        assertEq(uint256Field.typeInfo.code, TypeCode.UINT256);
        assertEq(boolField.typeInfo.code, TypeCode.BOOL);

        assertEq(uint256(harness.loadScalar(uint256Field, callData)), 42);
        assertEq(uint256(harness.loadScalar(boolField, callData)), 1);
    }

    function test_StaticTuple_SingleField() public view {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.tuple_(TypeDesc.uint256_())).build();
        bytes memory callData = abi.encodeWithSelector(SELECTOR, uint256(42));

        CalldataReader.Location memory tupleLoc = harness.locate(desc, callData, _path(0), cfg);
        CalldataReader.Location memory field = harness.tupleField(desc, tupleLoc, 0, callData);

        CalldataReader.Location memory expected = harness.locate(desc, callData, _path(0, 0), cfg);
        _assertLocationMatches(field, expected);
        assertEq(uint256(harness.loadScalar(field, callData)), 42);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   DYNAMIC TUPLES
    /////////////////////////////////////////////////////////////////////////*/

    function test_DynamicTuple_StaticAndDynamicFields() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256[])");

        uint256[] memory arr = new uint256[](2);
        arr[0] = 10;
        arr[1] = 20;
        AddressWithArray memory value = AddressWithArray(address(1), arr);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, value);

        CalldataReader.Location memory tupleLoc = harness.locate(desc, callData, _path(0), cfg);

        CalldataReader.Location memory addressField = harness.tupleField(desc, tupleLoc, 0, callData);
        CalldataReader.Location memory arrayField = harness.tupleField(desc, tupleLoc, 1, callData);

        CalldataReader.Location memory expectedAddress = harness.locate(desc, callData, _path(0, 0), cfg);
        CalldataReader.Location memory expectedArray = harness.locate(desc, callData, _path(0, 1), cfg);

        _assertLocationMatches(addressField, expectedAddress);
        assertEq(addressField.typeInfo.code, TypeCode.ADDRESS);

        _assertLocationMatches(arrayField, expectedArray);
        assertEq(arrayField.typeInfo.code, TypeCode.DYNAMIC_ARRAY);

        bytes32 addressWord = harness.loadScalar(addressField, callData);
        assertEq(address(uint160(uint256(addressWord))), address(1));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   NESTED TUPLES
    /////////////////////////////////////////////////////////////////////////*/

    function test_NestedTuple_InnerField() public view {
        bytes memory innerDesc = TypeDesc.tuple_(TypeDesc.address_(), TypeDesc.uint256_());
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.tuple_(innerDesc, TypeDesc.uint256_())).build();

        NestedTuple memory value = NestedTuple(SimpleTuple(address(1), 42), 100);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, value);

        CalldataReader.Location memory outerLoc = harness.locate(desc, callData, _path(0), cfg);
        CalldataReader.Location memory innerLoc = harness.tupleField(desc, outerLoc, 0, callData);

        assertEq(innerLoc.typeInfo.code, TypeCode.TUPLE);
        assertFalse(innerLoc.typeInfo.isDynamic);

        CalldataReader.Location memory innerAddress = harness.tupleField(desc, innerLoc, 0, callData);
        CalldataReader.Location memory innerUint = harness.tupleField(desc, innerLoc, 1, callData);

        assertEq(innerAddress.typeInfo.code, TypeCode.ADDRESS);
        assertEq(innerUint.typeInfo.code, TypeCode.UINT256);

        assertEq(address(uint160(uint256(harness.loadScalar(innerAddress, callData)))), address(1));
        assertEq(uint256(harness.loadScalar(innerUint, callData)), 42);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                TUPLES IN ARRAYS
    /////////////////////////////////////////////////////////////////////////*/

    function test_ArrayOfStaticTuples() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)[]");

        SimpleTuple[] memory arr = new SimpleTuple[](2);
        arr[0] = SimpleTuple(address(1), 11);
        arr[1] = SimpleTuple(address(2), 22);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.ArrayShape memory shape = harness.arrayShape(desc, callData, _path(0), cfg);

        for (uint256 i; i < shape.length; ++i) {
            CalldataReader.Location memory elem = harness.arrayElementAt(shape, i, callData);
            CalldataReader.Location memory addressField = harness.tupleField(desc, elem, 0, callData);
            CalldataReader.Location memory uint256Field = harness.tupleField(desc, elem, 1, callData);

            CalldataReader.Location memory expectedAddress = harness.locate(desc, callData, _path(0, uint16(i), 0), cfg);
            CalldataReader.Location memory expectedUint256 = harness.locate(desc, callData, _path(0, uint16(i), 1), cfg);

            _assertLocationMatches(addressField, expectedAddress);
            _assertLocationMatches(uint256Field, expectedUint256);
        }
    }

    function test_ArrayOfDynamicTuples() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,bytes)[]");

        AddressWithBytes[] memory arr = new AddressWithBytes[](2);
        arr[0] = AddressWithBytes(address(1), hex"0102");
        arr[1] = AddressWithBytes(address(2), hex"030405");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.ArrayShape memory shape = harness.arrayShape(desc, callData, _path(0), cfg);

        for (uint256 i; i < shape.length; ++i) {
            CalldataReader.Location memory elem = harness.arrayElementAt(shape, i, callData);
            CalldataReader.Location memory addressField = harness.tupleField(desc, elem, 0, callData);
            CalldataReader.Location memory bytesField = harness.tupleField(desc, elem, 1, callData);

            CalldataReader.Location memory expectedAddress = harness.locate(desc, callData, _path(0, uint16(i), 0), cfg);
            CalldataReader.Location memory expectedBytes = harness.locate(desc, callData, _path(0, uint16(i), 1), cfg);

            _assertLocationMatches(addressField, expectedAddress);
            _assertLocationMatches(bytesField, expectedBytes);
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 INVALID ACCESS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_NotTuple() public {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, uint256(42));

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NotComposite.selector, TypeCode.UINT256));
        harness.tupleField(desc, loc, 0, callData);
    }

    function test_RevertWhen_FieldOutOfRange() public {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), uint256(2));

        CalldataReader.Location memory tupleLoc = harness.locate(desc, callData, _path(0), cfg);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.TupleFieldOutOfBounds.selector, 2, 2));
        harness.tupleField(desc, tupleLoc, 2, callData);
    }
}

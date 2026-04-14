// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CalldataReader } from "src/CalldataReader.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeDesc } from "src/TypeDesc.sol";

import { CalldataReaderTest } from "../CalldataReader.t.sol";

// forge-lint: disable-next-item(unsafe-typecast, named-struct-fields)
contract LoadScalarTest is CalldataReaderTest {
    /*/////////////////////////////////////////////////////////////////////////
                                    ELEMENTARY TYPES
    /////////////////////////////////////////////////////////////////////////*/

    function test_Uint256() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, 42);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(uint256(word), 42);
    }

    function test_Address() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("address");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(address(uint160(uint256(word))), address(1));
    }

    function test_Bool() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("bool");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, true);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(uint256(word), 1);
    }

    function test_Bytes32() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes32");
        bytes32 expected = keccak256("test");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, expected);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(word, expected);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  DYNAMIC TYPES
    /////////////////////////////////////////////////////////////////////////*/

    function test_Bytes_ReturnsOffset() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, hex"01020304");

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(uint256(word), 32);
    }

    function test_String_ReturnsOffset() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("string");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, "hello");

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(uint256(word), 32);
    }

    function test_DynamicArray_ReturnsOffset() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");
        uint256[] memory arr = new uint256[](3);
        arr[0] = 1;
        arr[1] = 2;
        arr[2] = 3;
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(uint256(word), 32);
    }

    function test_DynamicTuple_ReturnsOffset() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256[])");

        uint256[] memory arr = new uint256[](2);
        arr[0] = 10;
        arr[1] = 20;
        AddressWithArray memory t = AddressWithArray(address(1), arr);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, t);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(uint256(word), 32);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                NESTED ELEMENTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_DynamicArrayElement() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");
        uint256[] memory arr = new uint256[](3);
        arr[0] = 100;
        arr[1] = 200;
        arr[2] = 300;
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(uint256(word), 200);
    }

    function test_StaticTupleField() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), 42);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(uint256(word), 42);
    }

    function test_DynamicTupleStaticField() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256[])");
        uint256[] memory arr = new uint256[](2);
        arr[0] = 10;
        arr[1] = 20;
        AddressWithArray memory t = AddressWithArray(address(1), arr);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, t);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(address(uint160(uint256(word))), address(1));
    }

    /*/////////////////////////////////////////////////////////////////////////
                              COMPOSITE REJECTION
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_StaticArray() public {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");
        uint256[3] memory arr = [uint256(1), 2, 3];
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NotScalar.selector, TypeCode.STATIC_ARRAY));
        harness.loadScalar(loc, callData);
    }

    function test_RevertWhen_StaticTuple() public {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), 42);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NotScalar.selector, TypeCode.TUPLE));
        harness.loadScalar(loc, callData);
    }

    function test_RevertWhen_StaticArrayLen1() public {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[1]");
        uint256[1] memory arr = [uint256(1)];
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NotScalar.selector, TypeCode.STATIC_ARRAY));
        harness.loadScalar(loc, callData);
    }

    function test_RevertWhen_StaticTupleLen1() public {
        bytes memory desc = DescriptorBuilder.create().add(TypeDesc.tuple_(TypeDesc.uint256_())).build();
        bytes memory callData = abi.encodeWithSelector(SELECTOR, 42);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NotScalar.selector, TypeCode.TUPLE));
        harness.loadScalar(loc, callData);
    }

    function test_RevertWhen_CalldataOutOfBounds() public {
        CalldataReader.Location memory loc;
        loc.head = 4;
        loc.base = 4;
        loc.typeInfo.code = TypeCode.UINT256;
        loc.typeInfo.isDynamic = false;
        loc.typeInfo.staticSize = 32;

        bytes memory callData = abi.encodeWithSelector(SELECTOR);

        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
        harness.loadScalar(loc, callData);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                VALUE ROUND-TRIP
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_Uint256(uint256 value) public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, value);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(uint256(word), value);
    }

    function testFuzz_Address(address value) public view {
        bytes memory desc = DescriptorBuilder.fromTypes("address");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, value);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(address(uint160(uint256(word))), value);
    }

    function testFuzz_ArrayElement(uint256 index, uint256 value) public view {
        index = bound(index, 0, 9);
        uint256[] memory arr = new uint256[](10);
        arr[index] = value;

        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, uint16(index)), cfg);
        bytes32 word = harness.loadScalar(loc, callData);

        assertEq(uint256(word), value);
    }
}

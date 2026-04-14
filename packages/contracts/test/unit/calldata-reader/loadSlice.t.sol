// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { LibBytes } from "solady/utils/LibBytes.sol";
import { CalldataReader } from "src/CalldataReader.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { TypeCode } from "src/TypeCode.sol";

import { CalldataReaderTest } from "../CalldataReader.t.sol";

// forge-lint: disable-next-item(unsafe-typecast, named-struct-fields)
contract LoadSliceTest is CalldataReaderTest {
    /*/////////////////////////////////////////////////////////////////////////
                                    TOP-LEVEL
    /////////////////////////////////////////////////////////////////////////*/

    function test_Bytes() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, hex"010203");

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(loc, callData);

        _assertSlice(callData, slice, hex"010203");
    }

    function test_String() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("string");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, "hello");

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(loc, callData);

        _assertSlice(callData, slice, bytes("hello"));
    }

    function test_EmptyBytes() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, bytes(""));

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(loc, callData);

        assertEq(slice.length, 0);
        assertEq(_sliceToBytes(callData, slice).length, 0);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                      NESTED
    /////////////////////////////////////////////////////////////////////////*/

    function test_BytesInsideTuple() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,bytes)");
        AddressWithBytes memory tuple = AddressWithBytes(address(1), hex"0102");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, tuple);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1), cfg);
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(loc, callData);

        _assertSlice(callData, slice, hex"0102");
    }

    function test_BytesInsideDynamicArray() public view {
        bytes[] memory elems = new bytes[](3);
        elems[0] = bytes("");
        elems[1] = hex"01";
        elems[2] = hex"010203";

        bytes memory desc = DescriptorBuilder.fromTypes("bytes[]");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, elems);

        for (uint16 i; i < 3; ++i) {
            CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, i), cfg);
            CalldataReader.DynamicSlice memory slice = harness.loadSlice(loc, callData);
            _assertSlice(callData, slice, elems[i]);
        }
    }

    function test_MultipleTopLevelBytes() public view {
        bytes memory b0 = hex"01";
        bytes memory b1 = hex"0203";
        bytes memory b2 = hex"040506";

        bytes memory desc = DescriptorBuilder.fromTypes("bytes,bytes,bytes");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, b0, b1, b2);

        CalldataReader.Location memory loc0 = harness.locate(desc, callData, _path(0), cfg);
        _assertSlice(callData, harness.loadSlice(loc0, callData), b0);

        CalldataReader.Location memory loc1 = harness.locate(desc, callData, _path(1), cfg);
        _assertSlice(callData, harness.loadSlice(loc1, callData), b1);

        CalldataReader.Location memory loc2 = harness.locate(desc, callData, _path(2), cfg);
        _assertSlice(callData, harness.loadSlice(loc2, callData), b2);
    }

    function test_DynamicArray() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");
        uint256[] memory array = new uint256[](3);
        array[0] = 1;
        array[1] = 2;
        array[2] = 3;
        bytes memory callData = abi.encodeWithSelector(SELECTOR, array);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(loc, callData);

        assertEq(slice.length, 3);
        assertEq(uint256(LibBytes.load(callData, slice.dataOffset)), 1);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   EDGE CASES
    /////////////////////////////////////////////////////////////////////////*/

    function test_WordAlignedLength() public view {
        bytes memory payload32 = new bytes(32);
        bytes memory payload64 = new bytes(64);
        for (uint256 i; i < 32; ++i) {
            payload32[i] = bytes1(uint8(i));
        }
        for (uint256 i; i < 64; ++i) {
            payload64[i] = bytes1(uint8(i));
        }

        bytes memory desc = DescriptorBuilder.fromTypes("bytes,bytes");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, payload32, payload64);

        CalldataReader.Location memory loc0 = harness.locate(desc, callData, _path(0), cfg);
        _assertSlice(callData, harness.loadSlice(loc0, callData), payload32);

        CalldataReader.Location memory loc1 = harness.locate(desc, callData, _path(1), cfg);
        _assertSlice(callData, harness.loadSlice(loc1, callData), payload64);
    }

    function test_NonAlignedLength() public view {
        bytes memory payload31 = new bytes(31);
        bytes memory payload33 = new bytes(33);
        for (uint256 i; i < 31; ++i) {
            payload31[i] = 0x01;
        }
        for (uint256 i; i < 33; ++i) {
            payload33[i] = 0x02;
        }

        bytes memory desc = DescriptorBuilder.fromTypes("bytes,bytes");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, payload31, payload33);

        CalldataReader.Location memory loc0 = harness.locate(desc, callData, _path(0), cfg);
        _assertSlice(callData, harness.loadSlice(loc0, callData), payload31);

        CalldataReader.Location memory loc1 = harness.locate(desc, callData, _path(1), cfg);
        _assertSlice(callData, harness.loadSlice(loc1, callData), payload33);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 INVALID SLICES
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_Elementary() public {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, uint256(42));

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NoCalldataLength.selector, TypeCode.UINT256));
        harness.loadSlice(loc, callData);
    }

    function test_RevertWhen_CalldataOutOfBounds_LengthOverflows() public {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes");
        bytes memory callData = abi.encodePacked(SELECTOR, uint256(0x20), type(uint256).max);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
        harness.loadSlice(loc, callData);
    }

    function test_RevertWhen_CalldataOutOfBounds_OffsetPastEnd() public {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes");
        bytes memory callData = abi.encodePacked(SELECTOR, uint256(0xFFFF));

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
        harness.loadSlice(loc, callData);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                SLICE ROUND-TRIP
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_Bytes(uint256 length) public view {
        length = bound(length, 0, 256);
        bytes memory payload = new bytes(length);
        for (uint256 i; i < length; ++i) {
            payload[i] = bytes1(uint8(i));
        }

        bytes memory desc = DescriptorBuilder.fromTypes("bytes");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, payload);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(loc, callData);

        _assertSlice(callData, slice, payload);
    }

    function testFuzz_BytesInsideTuple(uint256 length) public view {
        length = bound(length, 0, 128);
        bytes memory payload = new bytes(length);
        for (uint256 i; i < length; ++i) {
            payload[i] = bytes1(uint8(1));
        }

        bytes memory desc = DescriptorBuilder.fromTypes("(address,bytes)");
        AddressWithBytes memory tuple = AddressWithBytes(address(1), payload);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, tuple);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1), cfg);
        CalldataReader.DynamicSlice memory slice = harness.loadSlice(loc, callData);

        _assertSlice(callData, slice, payload);
    }
}

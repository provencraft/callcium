// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CalldataReader } from "src/CalldataReader.sol";
import { Descriptor } from "src/Descriptor.sol";
import { DescriptorBuilder, DescriptorDraft } from "src/DescriptorBuilder.sol";
import { DescriptorFormat as DF } from "src/DescriptorFormat.sol";

import { Path } from "src/Path.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeDesc } from "src/TypeDesc.sol";

import { CalldataReaderTest } from "../CalldataReader.t.sol";

// forge-lint: disable-next-item(unsafe-typecast, named-struct-fields)
contract LocateTest is CalldataReaderTest {
    /*/////////////////////////////////////////////////////////////////////////
                                    ELEMENTARY TYPES
    /////////////////////////////////////////////////////////////////////////*/

    function test_SingleAddress() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("address");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        assertEq(loc.head, 4);
        assertEq(loc.base, 4);
        assertEq(loc.descOffset, 2);
        assertEq(loc.typeInfo.code, TypeCode.ADDRESS);
        assertEq(loc.typeInfo.isDynamic, false);
        assertEq(loc.typeInfo.staticSize, 32);
    }

    function test_SingleUint256() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, 42);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        assertEq(loc.head, 4);
        assertEq(loc.typeInfo.code, TypeCode.UINT256);
        assertEq(loc.typeInfo.isDynamic, false);
        assertEq(loc.typeInfo.staticSize, 32);
    }

    function test_MultipleElementaryTypes_SecondParam() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("address,uint256,bool");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), 42, true);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(1), cfg);

        assertEq(loc.head, 36);
        assertEq(loc.descOffset, 3);
        assertEq(loc.typeInfo.code, TypeCode.UINT256);
    }

    function test_MultipleElementaryTypes_ThirdParam() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("address,uint256,bool");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), 42, true);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(2), cfg);

        assertEq(loc.head, 68);
        assertEq(loc.descOffset, 4);
        assertEq(loc.typeInfo.code, TypeCode.BOOL);
    }

    function test_SingleBytes() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, hex"01020304");

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        assertEq(loc.head, 4);
        assertEq(loc.typeInfo.code, TypeCode.BYTES);
        assertEq(loc.typeInfo.isDynamic, true);
        assertEq(loc.typeInfo.staticSize, 0);
    }

    function test_SingleString() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("string");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, "hello");

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        assertEq(loc.head, 4);
        assertEq(loc.typeInfo.code, TypeCode.STRING);
        assertEq(loc.typeInfo.isDynamic, true);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                      STRUCTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_StaticStruct_Root() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), 42);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        assertEq(loc.head, 4);
        assertEq(loc.typeInfo.code, TypeCode.TUPLE);
        assertEq(loc.typeInfo.isDynamic, false);
        assertEq(loc.typeInfo.staticSize, 64);
    }

    function test_StaticStruct_FirstField() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), 42);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 0), cfg);

        assertEq(loc.head, 4);
        // First field at offset: header(2) + tupleHeader(6) = 8.
        assertEq(loc.descOffset, 8);
        assertEq(loc.typeInfo.code, TypeCode.ADDRESS);
    }

    function test_StaticStruct_SecondField() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), 42);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1), cfg);

        assertEq(loc.head, 36);
        assertEq(loc.typeInfo.code, TypeCode.UINT256);
    }

    function test_DynamicStruct_Root() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,bytes)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), hex"0102");

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        assertEq(loc.head, 4);
        assertEq(loc.typeInfo.code, TypeCode.TUPLE);
        assertEq(loc.typeInfo.isDynamic, true);
        assertEq(loc.typeInfo.staticSize, 0);
    }

    function test_DynamicStruct_StaticField() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,bytes)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), hex"0102");

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 0), cfg);

        assertEq(loc.typeInfo.code, TypeCode.ADDRESS);
    }

    function test_DynamicStruct_DynamicField() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,bytes)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), hex"0102");

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1), cfg);

        assertEq(loc.typeInfo.code, TypeCode.BYTES);
        assertEq(loc.typeInfo.isDynamic, true);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                      ARRAYS
    /////////////////////////////////////////////////////////////////////////*/

    function test_StaticArrayStaticElem_Root() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");
        uint256[3] memory arr = [uint256(1), 2, 3];
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        assertEq(loc.head, 4);
        assertEq(loc.typeInfo.code, TypeCode.STATIC_ARRAY);
        assertEq(loc.typeInfo.isDynamic, false);
        assertEq(loc.typeInfo.staticSize, 96);
    }

    function test_StaticArrayStaticElem_Element() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");
        uint256[3] memory arr = [uint256(1), 2, 3];
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1), cfg);

        assertEq(loc.head, 36);
        // Element at offset: header(2) + code(1) + meta(3) = 6.
        assertEq(loc.descOffset, 6);
        assertEq(loc.typeInfo.code, TypeCode.UINT256);
    }

    function test_StaticArrayDynamicElem_Element() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes[2]");
        bytes[] memory arr = new bytes[](2);
        arr[0] = hex"AA";
        arr[1] = hex"BB";
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1), cfg);

        assertEq(loc.typeInfo.code, TypeCode.BYTES);
        assertEq(loc.typeInfo.isDynamic, true);
    }

    function test_DynamicArrayStaticElem_Root() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");
        uint256[] memory arr = new uint256[](3);
        arr[0] = 1;
        arr[1] = 2;
        arr[2] = 3;
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        assertEq(loc.head, 4);
        assertEq(loc.typeInfo.code, TypeCode.DYNAMIC_ARRAY);
        assertEq(loc.typeInfo.isDynamic, true);
    }

    function test_DynamicArrayStaticElem_Element() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");
        uint256[] memory arr = new uint256[](3);
        arr[0] = 1;
        arr[1] = 2;
        arr[2] = 3;
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1), cfg);

        // Element at offset: header(2) + code(1) + meta(3) = 6.
        assertEq(loc.descOffset, 6);
        assertEq(loc.typeInfo.code, TypeCode.UINT256);
    }

    function test_DynamicArrayDynamicElem_Element() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes[]");
        bytes[] memory arr = new bytes[](2);
        arr[0] = hex"AA";
        arr[1] = hex"BB";
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1), cfg);

        assertEq(loc.typeInfo.code, TypeCode.BYTES);
        assertEq(loc.typeInfo.isDynamic, true);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 NESTED STRUCTURES
    /////////////////////////////////////////////////////////////////////////*/

    function test_TupleInsideArray() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)[]");

        SimpleTuple[] memory tarr = new SimpleTuple[](2);
        tarr[0] = SimpleTuple(address(1), 100);
        tarr[1] = SimpleTuple(address(2), 200);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, tarr);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 0, 1), cfg);

        assertEq(loc.typeInfo.code, TypeCode.UINT256);
    }

    function test_ArrayInsideStruct() public view {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256[])");
        uint256[] memory arr = new uint256[](2);
        arr[0] = 10;
        arr[1] = 20;
        AddressWithArray memory t = AddressWithArray(address(1), arr);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, t);

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 1, 0), cfg);

        assertEq(loc.typeInfo.code, TypeCode.UINT256);
    }

    function test_ThreeLevelNesting() public view {
        bytes memory innermost = TypeDesc.tuple_(TypeDesc.address_());
        bytes memory middle = TypeDesc.tuple_(innermost);
        bytes memory outer = TypeDesc.tuple_(middle);
        bytes memory desc = DescriptorBuilder.create().add(outer).build();
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 0, 0, 0), cfg);

        assertEq(loc.typeInfo.code, TypeCode.ADDRESS);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                CONFIG & OVERLOADS
    /////////////////////////////////////////////////////////////////////////*/

    function test_BaseOffset0_RawAbi() public {
        bytes memory desc = DescriptorBuilder.fromTypes("address");
        bytes memory callData = abi.encode(address(1));

        cfg.baseOffset = 0;
        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0), cfg);

        assertEq(loc.head, 0);
        assertEq(loc.base, 0);
        assertEq(loc.typeInfo.code, TypeCode.ADDRESS);
    }

    function test_MaxDepthAtLimit() public view {
        bytes memory innermost = TypeDesc.tuple_(TypeDesc.address_());
        bytes memory middle = TypeDesc.tuple_(innermost);
        bytes memory outer = TypeDesc.tuple_(middle);
        bytes memory desc = DescriptorBuilder.create().add(outer).build();
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(0, 0, 0, 0), cfg);

        assertEq(loc.typeInfo.code, TypeCode.ADDRESS);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  INVALID INPUTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_BadDescriptorVersionZero() public {
        bytes memory desc = hex"0001";
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));

        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnsupportedVersion.selector, uint8(0)));
        harness.locate(desc, callData, _path(0), cfg);
    }

    function test_RevertWhen_BadDescriptorVersionTwo() public {
        bytes memory desc = hex"0201";
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));

        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnsupportedVersion.selector, uint8(2)));
        harness.locate(desc, callData, _path(0), cfg);
    }

    function test_RevertWhen_DescriptorTooSmall() public {
        bytes memory desc = hex"01";
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));

        vm.expectRevert(Descriptor.MalformedHeader.selector);
        harness.locate(desc, callData, _path(0), cfg);
    }

    function test_RevertWhen_PathEmpty() public {
        bytes memory desc = DescriptorBuilder.fromTypes("address");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));
        bytes memory emptyPath = "";

        vm.expectRevert(Path.MalformedPath.selector);
        harness.locate(desc, callData, emptyPath, cfg);
    }

    function test_RevertWhen_PathOddLength() public {
        bytes memory desc = DescriptorBuilder.fromTypes("address");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));
        bytes memory oddPath = hex"00";

        vm.expectRevert(Path.MalformedPath.selector);
        harness.locate(desc, callData, oddPath, cfg);
    }

    function test_RevertWhen_ArgIndexOutOfBounds() public {
        bytes memory desc = DescriptorBuilder.fromTypes("address,uint256");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), 42);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.ArgIndexOutOfBounds.selector, 2, 2));
        harness.locate(desc, callData, _path(2), cfg);
    }

    function test_RevertWhen_TupleFieldOutOfBounds() public {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1), 42);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.TupleFieldOutOfBounds.selector, 2, 2));
        harness.locate(desc, callData, _path(0, 2), cfg);
    }

    function test_RevertWhen_StaticArrayIndexOutOfBounds() public {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");
        uint256[3] memory arr = [uint256(1), 2, 3];
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.ArrayIndexOutOfBounds.selector, 3, 3));
        harness.locate(desc, callData, _path(0, 3), cfg);
    }

    function test_RevertWhen_DynamicArrayIndexOutOfBounds() public {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");
        uint256[] memory arr = new uint256[](2);
        arr[0] = 1;
        arr[1] = 2;
        bytes memory callData = abi.encodeWithSelector(SELECTOR, arr);

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.ArrayIndexOutOfBounds.selector, 2, 2));
        harness.locate(desc, callData, _path(0, 2), cfg);
    }

    function test_RevertWhen_CalldataOutOfBounds() public {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");
        bytes memory callData = abi.encodeWithSelector(SELECTOR);

        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
        harness.locate(desc, callData, _path(0, 0), cfg);
    }

    function test_RevertWhen_NotCompositeElementary() public {
        bytes memory desc = DescriptorBuilder.fromTypes("address");
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.NotComposite.selector, TypeCode.ADDRESS));
        harness.locate(desc, callData, _path(0, 0), cfg);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                PROPERTY TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_RevertWhen_BadDescriptorVersion(uint8 ver) public {
        vm.assume(ver != DF.VERSION);
        bytes memory desc = abi.encodePacked(ver, uint8(1), TypeCode.ADDRESS);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, address(1));

        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnsupportedVersion.selector, ver));
        harness.locate(desc, callData, _path(0), cfg);
    }

    function testFuzz_ValidParamIndex_MixedTypes(uint256 paramCount, uint256 index) public view {
        paramCount = bound(paramCount, 1, 8);
        index = bound(index, 0, paramCount - 1);

        // forgefmt: disable-next-item
        bytes[4] memory typeDescs = [TypeDesc.address_(), TypeDesc.uint256_(), TypeDesc.bool_(), TypeDesc.bytes32_()];
        uint8[4] memory typeCodes = [TypeCode.ADDRESS, TypeCode.UINT256, TypeCode.BOOL, TypeCode.BYTES32];

        DescriptorDraft memory draft = DescriptorBuilder.create();
        for (uint256 i; i < paramCount; ++i) {
            draft = draft.add(typeDescs[i % 4]);
        }
        bytes memory desc = draft.build();
        bytes memory callData = abi.encodePacked(SELECTOR, new bytes(32 * paramCount));

        CalldataReader.Location memory loc = harness.locate(desc, callData, _path(uint16(index)), cfg);

        assertEq(loc.head, 4 + index * 32);
        assertEq(loc.typeInfo.code, typeCodes[index % 4]);
    }

    function testFuzz_RevertWhen_ArgIndexOutOfBounds(uint256 argCount, uint256 index) public {
        argCount = bound(argCount, 1, 10);
        index = bound(index, argCount, type(uint16).max);

        DescriptorDraft memory draft = DescriptorBuilder.create();
        for (uint8 i; i < argCount; ++i) {
            draft = draft.add(TypeDesc.address_());
        }
        bytes memory desc = draft.build();

        address[] memory addrs = new address[](argCount);
        bytes memory callData = abi.encodeWithSelector(SELECTOR, _encodeAddresses(addrs));

        vm.expectRevert(abi.encodeWithSelector(CalldataReader.ArgIndexOutOfBounds.selector, index, argCount));
        harness.locate(desc, callData, _path(uint16(index)), cfg);
    }
}

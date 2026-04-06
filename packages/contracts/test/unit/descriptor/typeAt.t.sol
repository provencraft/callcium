// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Descriptor } from "src/Descriptor.sol";
import { DescriptorBuilder, DescriptorDraft } from "src/DescriptorBuilder.sol";
import { DescriptorFormat as DF } from "src/DescriptorFormat.sol";

import { Path } from "src/Path.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeDesc } from "src/TypeDesc.sol";

import { DescriptorTest } from "../Descriptor.t.sol";

// forge-lint: disable-next-item(unsafe-typecast)
contract TypeAtTest is DescriptorTest {
    using Descriptor for bytes;

    /*/////////////////////////////////////////////////////////////////////////
                                    ELEMENTARY TYPES
    /////////////////////////////////////////////////////////////////////////*/

    function test_SingleAddress() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0));

        assertEq(t.code, TypeCode.ADDRESS);
        assertEq(t.isDynamic, false);
        assertEq(t.staticSize, 32);
    }

    function test_SingleUint256() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0));

        assertEq(t.code, TypeCode.UINT256);
        assertEq(t.isDynamic, false);
        assertEq(t.staticSize, 32);
    }

    function test_MultipleElementaryTypes_SecondParam() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address,uint256,bool");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(1));

        assertEq(t.code, TypeCode.UINT256);
    }

    function test_MultipleElementaryTypes_ThirdParam() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address,uint256,bool");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(2));

        assertEq(t.code, TypeCode.BOOL);
    }

    function test_SingleBytes() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0));

        assertEq(t.code, TypeCode.BYTES);
        assertEq(t.isDynamic, true);
        assertEq(t.staticSize, 0);
    }

    function test_SingleString() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("string");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0));

        assertEq(t.code, TypeCode.STRING);
        assertEq(t.isDynamic, true);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                      STRUCTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_StaticStruct_Root() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0));

        assertEq(t.code, TypeCode.TUPLE);
        assertEq(t.isDynamic, false);
        assertEq(t.staticSize, 64);
    }

    function test_StaticStruct_FirstField() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0, 0));

        assertEq(t.code, TypeCode.ADDRESS);
    }

    function test_StaticStruct_SecondField() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0, 1));

        assertEq(t.code, TypeCode.UINT256);
    }

    function test_DynamicStruct_Root() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,bytes)");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0));

        assertEq(t.code, TypeCode.TUPLE);
        assertEq(t.isDynamic, true);
        assertEq(t.staticSize, 0);
    }

    function test_DynamicStruct_StaticField() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,bytes)");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0, 0));

        assertEq(t.code, TypeCode.ADDRESS);
    }

    function test_DynamicStruct_DynamicField() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,bytes)");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0, 1));

        assertEq(t.code, TypeCode.BYTES);
        assertEq(t.isDynamic, true);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                      ARRAYS
    /////////////////////////////////////////////////////////////////////////*/

    function test_StaticArrayStaticElem_Root() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0));

        assertEq(t.code, TypeCode.STATIC_ARRAY);
        assertEq(t.isDynamic, false);
        assertEq(t.staticSize, 96);
    }

    function test_StaticArrayStaticElem_Element() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0, 1));

        assertEq(t.code, TypeCode.UINT256);
    }

    function test_StaticArrayDynamicElem_Root() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes[2]");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0));

        assertEq(t.code, TypeCode.STATIC_ARRAY);
        assertEq(t.isDynamic, true);
        assertEq(t.staticSize, 0);
    }

    function test_StaticArrayDynamicElem_Element() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes[2]");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0, 1));

        assertEq(t.code, TypeCode.BYTES);
        assertEq(t.isDynamic, true);
    }

    function test_DynamicArrayStaticElem_Root() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[]");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0));

        assertEq(t.code, TypeCode.DYNAMIC_ARRAY);
        assertEq(t.isDynamic, true);
    }

    function test_DynamicArrayDynamicElem_Root() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes[]");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0));

        assertEq(t.code, TypeCode.DYNAMIC_ARRAY);
        assertEq(t.isDynamic, true);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 NESTED STRUCTURES
    /////////////////////////////////////////////////////////////////////////*/

    function test_TupleInsideArray() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)[2]");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0, 0, 1));

        assertEq(t.code, TypeCode.UINT256);
    }

    function test_ArrayInsideStruct() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256[3])");

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0, 1, 0));

        assertEq(t.code, TypeCode.UINT256);
    }

    function test_ThreeLevelNesting() public pure {
        bytes memory innermost = TypeDesc.tuple_(TypeDesc.address_());
        bytes memory middle = TypeDesc.tuple_(innermost);
        bytes memory outer = TypeDesc.tuple_(middle);
        bytes memory desc = DescriptorBuilder.create().add(outer).build();

        Descriptor.TypeInfo memory t = desc.typeAt(_path(0, 0, 0, 0));

        assertEq(t.code, TypeCode.ADDRESS);
    }

    function test_MixedRootParams() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address,uint256[],(bool,bytes32)");

        assertEq(desc.typeAt(_path(0)).code, TypeCode.ADDRESS);
        assertEq(desc.typeAt(_path(1)).code, TypeCode.DYNAMIC_ARRAY);
        assertEq(desc.typeAt(_path(2)).code, TypeCode.TUPLE);
        assertEq(desc.typeAt(_path(2, 0)).code, TypeCode.BOOL);
        assertEq(desc.typeAt(_path(2, 1)).code, TypeCode.BYTES32);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  INVALID INPUTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_BadDescriptorVersionZero() public {
        bytes memory desc = hex"0001";

        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnsupportedVersion.selector, uint8(0)));
        desc.typeAt(_path(0));
    }

    function test_RevertWhen_BadDescriptorVersionTwo() public {
        bytes memory desc = hex"0201";

        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnsupportedVersion.selector, uint8(2)));
        desc.typeAt(_path(0));
    }

    function test_RevertWhen_DescriptorTooSmall() public {
        bytes memory desc = hex"01";

        vm.expectRevert(Descriptor.MalformedHeader.selector);
        desc.typeAt(_path(0));
    }

    function test_RevertWhen_PathEmpty() public {
        bytes memory desc = DescriptorBuilder.fromTypes("address");
        bytes memory emptyPath = "";

        vm.expectRevert(Path.MalformedPath.selector);
        desc.typeAt(emptyPath);
    }

    function test_RevertWhen_PathOddLength() public {
        bytes memory desc = DescriptorBuilder.fromTypes("address");
        bytes memory oddPath = hex"00";

        vm.expectRevert(Path.MalformedPath.selector);
        desc.typeAt(oddPath);
    }

    function test_RevertWhen_ArgIndexOutOfBounds() public {
        bytes memory desc = DescriptorBuilder.fromTypes("address,uint256");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.ArgIndexOutOfBounds.selector, 2, 2));
        desc.typeAt(_path(2));
    }

    function test_RevertWhen_TupleFieldOutOfBounds() public {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.TupleFieldOutOfBounds.selector, 2, 2));
        desc.typeAt(_path(0, 2));
    }

    function test_RevertWhen_StaticArrayIndexOutOfBounds() public {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[3]");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.ArrayIndexOutOfBounds.selector, 3, 3));
        desc.typeAt(_path(0, 3));
    }

    function test_RevertWhen_NotCompositeElementary() public {
        bytes memory desc = DescriptorBuilder.fromTypes("address");

        vm.expectRevert(abi.encodeWithSelector(Descriptor.NotComposite.selector, TypeCode.ADDRESS));
        desc.typeAt(_path(0, 0));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                PROPERTY TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_RevertWhen_BadDescriptorVersion(uint8 ver) public {
        vm.assume(ver != DF.VERSION);
        bytes memory desc = abi.encodePacked(ver, uint8(1), TypeCode.ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(Descriptor.UnsupportedVersion.selector, ver));
        desc.typeAt(_path(0));
    }

    function testFuzz_ValidParamIndex_MixedTypes(uint256 paramCount, uint256 index) public pure {
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

        assertEq(desc.typeAt(_path(uint16(index))).code, typeCodes[index % 4]);
    }

    function testFuzz_RevertWhen_ArgIndexOutOfBounds(uint256 argCount, uint256 index) public {
        argCount = bound(argCount, 1, 10);
        index = bound(index, argCount, type(uint16).max);

        DescriptorDraft memory draft = DescriptorBuilder.create();
        for (uint8 i; i < argCount; ++i) {
            draft = draft.add(TypeDesc.address_());
        }
        bytes memory desc = draft.build();

        vm.expectRevert(abi.encodeWithSelector(Descriptor.ArgIndexOutOfBounds.selector, index, argCount));
        desc.typeAt(_path(uint16(index)));
    }
}

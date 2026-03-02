// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorBuilderTest } from "../DescriptorBuilder.t.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { TypeDesc } from "src/TypeDesc.sol";

contract FromTypesTest is DescriptorBuilderTest {
    /*/////////////////////////////////////////////////////////////////////////
                                ELEMENTARY TYPES
    /////////////////////////////////////////////////////////////////////////*/

    function test_EmptyString() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("");
        bytes memory expected = DescriptorBuilder.create().build();
        assertEq(desc, expected);
    }

    function test_SingleAddress() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.address_()).build();
        assertEq(desc, expected);
    }

    function test_SingleBool() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("bool");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.bool_()).build();
        assertEq(desc, expected);
    }

    function test_SingleString() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("string");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.string_()).build();
        assertEq(desc, expected);
    }

    function test_SingleBytes() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.bytes_()).build();
        assertEq(desc, expected);
    }

    function test_SingleFunction() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("function");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.function_()).build();
        assertEq(desc, expected);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                SIZED TYPES
    /////////////////////////////////////////////////////////////////////////*/

    function test_Uint8() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint8");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.uintN_(8)).build();
        assertEq(desc, expected);
    }

    function test_Uint256() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.uint256_()).build();
        assertEq(desc, expected);
    }

    function test_Int8() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("int8");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.intN_(8)).build();
        assertEq(desc, expected);
    }

    function test_Int256() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("int256");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.int256_()).build();
        assertEq(desc, expected);
    }

    function test_Bytes1() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes1");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.bytesN_(1)).build();
        assertEq(desc, expected);
    }

    function test_Bytes32() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("bytes32");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.bytes32_()).build();
        assertEq(desc, expected);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              MULTIPLE PARAMS
    /////////////////////////////////////////////////////////////////////////*/

    function test_MultipleParams() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address,uint256");
        // forgefmt: disable-next-item
        bytes memory expected = DescriptorBuilder.create()
            .add(TypeDesc.address_())
            .add(TypeDesc.uint256_())
            .build();
        assertEq(desc, expected);
    }

    function test_ThreeParams() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address,uint256,bool");
        // forgefmt: disable-next-item
        bytes memory expected = DescriptorBuilder.create()
            .add(TypeDesc.address_())
            .add(TypeDesc.uint256_())
            .add(TypeDesc.bool_())
            .build();
        assertEq(desc, expected);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  ARRAYS
    /////////////////////////////////////////////////////////////////////////*/

    function test_DynamicArray() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address[]");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.address_())).build();
        assertEq(desc, expected);
    }

    function test_StaticArray() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address[5]");
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.address_(), 5)).build();
        assertEq(desc, expected);
    }

    function test_NestedDynamicArray() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[][]");
        bytes memory expected =
            DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.array_(TypeDesc.uint256_()))).build();
        assertEq(desc, expected);
    }

    function test_MixedNestedArray() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint256[][3]");
        bytes memory expected =
            DescriptorBuilder.create().add(TypeDesc.array_(TypeDesc.array_(TypeDesc.uint256_()), 3)).build();
        assertEq(desc, expected);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  TUPLES
    /////////////////////////////////////////////////////////////////////////*/

    function test_SimpleTuple() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)");
        bytes memory expected =
            DescriptorBuilder.create().add(TypeDesc.tuple_(TypeDesc.address_(), TypeDesc.uint256_())).build();
        assertEq(desc, expected);
    }

    function test_TupleArray() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256)[]");
        bytes memory tupleDesc = TypeDesc.tuple_(TypeDesc.address_(), TypeDesc.uint256_());
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.array_(tupleDesc)).build();
        assertEq(desc, expected);
    }

    function test_TupleStaticArray() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(bool,bytes32)[2]");
        bytes memory tupleDesc = TypeDesc.tuple_(TypeDesc.bool_(), TypeDesc.bytes32_());
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.array_(tupleDesc, 2)).build();
        assertEq(desc, expected);
    }

    function test_NestedTuple() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,(uint256,bool))");
        bytes memory innerTuple = TypeDesc.tuple_(TypeDesc.uint256_(), TypeDesc.bool_());
        bytes memory expected = DescriptorBuilder.create().add(TypeDesc.tuple_(TypeDesc.address_(), innerTuple)).build();
        assertEq(desc, expected);
    }

    function test_TupleWithArray() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("(address,uint256[])");
        bytes memory expected = DescriptorBuilder.create()
            .add(TypeDesc.tuple_(TypeDesc.address_(), TypeDesc.array_(TypeDesc.uint256_()))).build();
        assertEq(desc, expected);
    }

    /*/////////////////////////////////////////////////////////////////////////
                            COMPLEX SIGNATURES
    /////////////////////////////////////////////////////////////////////////*/

    function test_ComplexSignature() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("address[],(uint256,bool),bytes");
        bytes memory tupleDesc = TypeDesc.tuple_(TypeDesc.uint256_(), TypeDesc.bool_());
        // forgefmt: disable-next-item
        bytes memory expected = DescriptorBuilder.create()
            .add(TypeDesc.array_(TypeDesc.address_()))
            .add(tupleDesc)
            .add(TypeDesc.bytes_())
            .build();
        assertEq(desc, expected);
    }

    function test_AllUintSizes() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("uint8,uint16,uint24,uint32,uint64,uint128,uint256");
        // forgefmt: disable-next-item
        bytes memory expected = DescriptorBuilder.create()
            .add(TypeDesc.uintN_(8))
            .add(TypeDesc.uintN_(16))
            .add(TypeDesc.uintN_(24))
            .add(TypeDesc.uintN_(32))
            .add(TypeDesc.uintN_(64))
            .add(TypeDesc.uintN_(128))
            .add(TypeDesc.uint256_())
            .build();
        assertEq(desc, expected);
    }

    function test_AllIntSizes() public pure {
        bytes memory desc = DescriptorBuilder.fromTypes("int8,int16,int24,int32,int64,int128,int256");
        // forgefmt: disable-next-item
        bytes memory expected = DescriptorBuilder.create()
            .add(TypeDesc.intN_(8))
            .add(TypeDesc.intN_(16))
            .add(TypeDesc.intN_(24))
            .add(TypeDesc.intN_(32))
            .add(TypeDesc.intN_(64))
            .add(TypeDesc.intN_(128))
            .add(TypeDesc.int256_())
            .build();
        assertEq(desc, expected);
    }

    /*/////////////////////////////////////////////////////////////////////////
                            MALFORMED TYPE STRINGS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_EmptyTuple() public {
        vm.expectRevert(TypeDesc.InvalidLength.selector);
        DescriptorBuilder.fromTypes("()");
    }

    function test_RevertWhen_UnknownType() public {
        vm.expectRevert(DescriptorBuilder.UnknownType.selector);
        DescriptorBuilder.fromTypes("foo");
    }

    function test_RevertWhen_InvalidUintSize() public {
        vm.expectRevert(DescriptorBuilder.UnknownType.selector);
        DescriptorBuilder.fromTypes("uint7");
    }

    function test_RevertWhen_InvalidIntSize() public {
        vm.expectRevert(DescriptorBuilder.UnknownType.selector);
        DescriptorBuilder.fromTypes("int7");
    }

    function test_RevertWhen_InvalidBytesSize() public {
        vm.expectRevert(DescriptorBuilder.UnknownType.selector);
        DescriptorBuilder.fromTypes("bytes33");
    }

    function test_RevertWhen_UnmatchedParenthesis() public {
        vm.expectRevert(DescriptorBuilder.MalformedTypeString.selector);
        DescriptorBuilder.fromTypes("(address,uint256");
    }

    function test_RevertWhen_UnmatchedBracket() public {
        vm.expectRevert(DescriptorBuilder.MalformedTypeString.selector);
        DescriptorBuilder.fromTypes("uint256[");
    }

    function test_RevertWhen_ExtraClosingParenthesis() public {
        vm.expectRevert(DescriptorBuilder.MalformedTypeString.selector);
        DescriptorBuilder.fromTypes("address)");
    }

    function test_RevertWhen_TrailingComma() public {
        vm.expectRevert(DescriptorBuilder.MalformedTypeString.selector);
        DescriptorBuilder.fromTypes("address,");
    }

    function test_RevertWhen_LeadingComma() public {
        vm.expectRevert(DescriptorBuilder.MalformedTypeString.selector);
        DescriptorBuilder.fromTypes(",address");
    }

    function test_RevertWhen_DoubleComma() public {
        vm.expectRevert(DescriptorBuilder.MalformedTypeString.selector);
        DescriptorBuilder.fromTypes("address,,uint256");
    }
}

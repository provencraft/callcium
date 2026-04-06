// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorTest } from "../Descriptor.t.sol";
import { Descriptor } from "src/Descriptor.sol";
import { DescriptorFormat as DF } from "src/DescriptorFormat.sol";
import { TypeCode } from "src/TypeCode.sol";

// forge-lint: disable-next-item(unsafe-typecast)
contract AtTest is DescriptorTest {
    /*/////////////////////////////////////////////////////////////////////////
                                    BASIC AT
    /////////////////////////////////////////////////////////////////////////*/

    function test_ReturnsFirstParamOffset() public pure {
        bytes memory desc = hex"010140";
        assertEq(Descriptor.at(desc, 0), DF.HEADER_SIZE);
    }

    function test_ReturnsSecondParamOffset() public pure {
        bytes memory desc = hex"01024000";
        assertEq(Descriptor.at(desc, 1), DF.HEADER_SIZE + DF.TYPECODE_SIZE);
    }

    function test_SkipsDynamicArray() public pure {
        // Dynamic array of address (nodeLength=5) followed by address.
        bytes memory desc = hex"01028100000540" hex"40";
        assertEq(
            Descriptor.at(desc, 1),
            DF.HEADER_SIZE + DF.ARRAY_HEADER_SIZE + DF.TYPECODE_SIZE /* elem code */
        );
    }

    function test_SkipsStaticArray() public pure {
        // Static array of address[3] (nodeLength=7) followed by address.
        bytes memory desc = hex"010280003007400003" hex"40";
        assertEq(
            Descriptor.at(desc, 1),
            DF.HEADER_SIZE + DF.ARRAY_HEADER_SIZE + DF.TYPECODE_SIZE /* elem code */ + DF.ARRAY_LENGTH_SIZE
        );
    }

    function test_SkipsTuple() public pure {
        // Tuple of (address, uint8) with nodeLength=8, followed by address.
        bytes memory desc = hex"01029000200800024000" hex"40";
        assertEq(Descriptor.at(desc, 1), DF.HEADER_SIZE + DF.TUPLE_HEADER_SIZE + DF.TYPECODE_SIZE + DF.TYPECODE_SIZE);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  OUT OF BOUNDS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_IndexOutOfBounds() public {
        bytes memory desc = hex"010140";
        vm.expectRevert(abi.encodeWithSelector(Descriptor.ParamIndexOutOfBounds.selector, 1, 1));
        Descriptor.at(desc, 1);
    }

    function test_RevertWhen_IndexOutOfBoundsZeroParams() public {
        bytes memory desc = hex"0100";
        vm.expectRevert(abi.encodeWithSelector(Descriptor.ParamIndexOutOfBounds.selector, 0, 0));
        Descriptor.at(desc, 0);
    }

    function testFuzz_RevertWhen_IndexOutOfBounds(uint8 paramCount, uint256 index) public {
        paramCount = uint8(bound(paramCount, 1, 10));
        index = bound(index, paramCount, type(uint16).max);

        bytes memory body;
        for (uint256 i; i < paramCount; ++i) {
            body = bytes.concat(body, bytes1(TypeCode.ADDRESS));
        }
        bytes memory desc = bytes.concat(hex"01", bytes1(paramCount), body);

        vm.expectRevert(abi.encodeWithSelector(Descriptor.ParamIndexOutOfBounds.selector, index, paramCount));
        Descriptor.at(desc, index);
    }

    /*/////////////////////////////////////////////////////////////////////////
                            UNCHECKED EQUIVALENCE
    /////////////////////////////////////////////////////////////////////////*/

    function test_AtUnchecked_IndexZero() public pure {
        bytes memory desc = hex"010140";

        uint256 a = Descriptor.at(desc, 0);
        uint256 b = Descriptor.atUnchecked(desc, 0);

        assertEq(a, b);
    }

    function test_AtUnchecked_LastIndex() public pure {
        bytes memory desc = hex"01024000";

        uint256 a = Descriptor.at(desc, 1);
        uint256 b = Descriptor.atUnchecked(desc, 1);

        assertEq(a, b);
    }

    function testFuzz_AtUnchecked_MatchesAt(uint256 paramCount, uint256 index) public pure {
        paramCount = bound(paramCount, 1, 10);
        index = bound(index, 0, paramCount - 1);

        bytes memory body;
        for (uint256 i; i < paramCount; ++i) {
            body = bytes.concat(body, bytes1(TypeCode.ADDRESS));
        }
        bytes memory desc = bytes.concat(hex"01", bytes1(uint8(paramCount)), body);

        assertEq(Descriptor.atUnchecked(desc, index), Descriptor.at(desc, index));
    }
}

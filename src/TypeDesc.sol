// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Be16 } from "./Be16.sol";
import { Be24 } from "./Be24.sol";
import { DescriptorFormat as DF } from "./DescriptorFormat.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";

library TypeDesc {
    /*/////////////////////////////////////////////////////////////////////////
                                     ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a provided type descriptor is empty.
    error EmptyType();

    /// @notice Thrown when a provided length is invalid.
    error InvalidLength();

    /// @notice Thrown when tuple field count exceeds the maximum.
    error TupleFieldCountTooLarge(uint256 count, uint256 max);

    /// @notice Thrown when static array length exceeds the maximum.
    error ArrayLengthTooLarge(uint256 length, uint256 max);

    /// @notice Thrown when static array product (length * elemStaticWords) exceeds the maximum.
    error ArrayProductTooLarge(uint256 product, uint256 max);

    /// @notice Thrown when descriptor node length exceeds the maximum.
    error NodeLengthTooLarge(uint256 nodeLength, uint256 max);

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Builds an address type descriptor.
    /// @return Type descriptor bytes for address.
    function address_() internal pure returns (bytes memory) {
        return _elementary(TypeCode.ADDRESS);
    }

    /// @notice Builds a bool type descriptor.
    /// @return Type descriptor bytes for bool.
    function bool_() internal pure returns (bytes memory) {
        return _elementary(TypeCode.BOOL);
    }

    /// @notice Builds a function pointer type descriptor.
    /// @return Type descriptor bytes for function.
    function function_() internal pure returns (bytes memory) {
        return _elementary(TypeCode.FUNCTION);
    }

    /// @notice Builds a uint256 type descriptor.
    /// @return Type descriptor bytes for uint256.
    function uint256_() internal pure returns (bytes memory) {
        return _elementary(TypeCode.UINT256);
    }

    /// @notice Builds an int256 type descriptor.
    /// @return Type descriptor bytes for int256.
    function int256_() internal pure returns (bytes memory) {
        return _elementary(TypeCode.INT256);
    }

    /// @notice Builds a dynamic bytes type descriptor.
    /// @return Type descriptor bytes for bytes.
    function bytes_() internal pure returns (bytes memory) {
        return _elementary(TypeCode.BYTES);
    }

    /// @notice Builds a string type descriptor.
    /// @return Type descriptor bytes for string.
    function string_() internal pure returns (bytes memory) {
        return _elementary(TypeCode.STRING);
    }

    /// @notice Builds a uintN type descriptor.
    /// @param bits The bit width of the unsigned integer.
    /// @return Type descriptor bytes for uintN.
    function uintN_(uint16 bits) internal pure returns (bytes memory) {
        return _elementary(TypeCode.uintN(bits));
    }

    /// @notice Builds an intN type descriptor.
    /// @param bits The bit width of the signed integer.
    /// @return Type descriptor bytes for intN.
    function intN_(uint16 bits) internal pure returns (bytes memory) {
        return _elementary(TypeCode.intN(bits));
    }

    /// @notice Builds a bytesN type descriptor.
    /// @param length The byte length for bytesN in [1,32].
    /// @return Type descriptor bytes for bytesN.
    function bytesN_(uint8 length) internal pure returns (bytes memory) {
        return _elementary(TypeCode.bytesN(length));
    }

    /// @notice Builds a bytes32 type descriptor.
    /// @return Type descriptor bytes for bytes32.
    function bytes32_() internal pure returns (bytes memory) {
        return _elementary(TypeCode.bytesN(32));
    }

    /// @notice Builds an enum type descriptor backed by an unsigned integer of `bits`.
    /// @dev Alias for `uintN_(bits)`. Enums are represented as uints in descriptors.
    /// @param bits The bit width of the enum.
    /// @return Type descriptor bytes for enum.
    function enum_(uint16 bits) internal pure returns (bytes memory) {
        return uintN_(bits);
    }

    /// @notice Builds a default enum type descriptor backed by an 8-bit uint.
    /// @return Type descriptor bytes for enum.
    function enum_() internal pure returns (bytes memory) {
        return uintN_(8);
    }

    /// @notice Builds a dynamic array type descriptor for the given element type.
    /// @dev Format: [DYNAMIC_ARRAY][meta][elemDesc]. Sizes per DescriptorFormat.
    /// @param elemDesc The element type descriptor.
    /// @return desc The type descriptor bytes for T[].
    function array_(bytes memory elemDesc) internal pure returns (bytes memory desc) {
        require(elemDesc.length != 0, EmptyType());

        uint256 elemLength = elemDesc.length;
        uint256 nodeLength = DF.ARRAY_HEADER_SIZE + elemLength;
        require(nodeLength <= DF.MAX_NODE_LENGTH, NodeLengthTooLarge(nodeLength, DF.MAX_NODE_LENGTH));

        desc = new bytes(nodeLength);

        // Type code.
        desc[0] = bytes1(TypeCode.DYNAMIC_ARRAY);

        // Meta: staticWords=0 (dynamic), nodeLength <= MAX_NODE_LENGTH (12 bits).
        // forge-lint: disable-next-line(unsafe-typecast)
        uint24 meta = uint24(nodeLength);
        Be24.write(desc, DF.TYPECODE_SIZE, meta);

        // Element descriptor.
        uint256 cursor = DF.ARRAY_HEADER_SIZE;
        for (uint256 i; i < elemLength; ++i) {
            unchecked {
                desc[cursor++] = elemDesc[i];
            }
        }
    }

    /// @notice Builds a static array type descriptor for the given element type.
    /// @dev Format: [STATIC_ARRAY][meta][elemDesc][length]. Sizes per DescriptorFormat.
    /// @param elemDesc The element type descriptor.
    /// @param length The fixed array length.
    /// @return desc The type descriptor bytes for T[length].
    function array_(bytes memory elemDesc, uint16 length) internal pure returns (bytes memory desc) {
        require(length != 0, InvalidLength());
        require(elemDesc.length != 0, EmptyType());
        require(length <= DF.MAX_STATIC_ARRAY_LENGTH, ArrayLengthTooLarge(length, DF.MAX_STATIC_ARRAY_LENGTH));

        uint256 elemLength = elemDesc.length;
        uint256 nodeLength = DF.ARRAY_HEADER_SIZE + elemLength + DF.ARRAY_LENGTH_SIZE;
        require(nodeLength <= DF.MAX_NODE_LENGTH, NodeLengthTooLarge(nodeLength, DF.MAX_NODE_LENGTH));

        // Extract element's staticWords.
        uint16 elemStaticWords = _extractStaticWords(elemDesc);

        // Compute array's staticWords.
        uint16 staticWords;
        if (elemStaticWords == 0) {
            staticWords = 0;
        } else {
            uint256 product = uint256(length) * uint256(elemStaticWords);
            require(product <= DF.MAX_STATIC_WORDS, ArrayProductTooLarge(product, DF.MAX_STATIC_WORDS));
            // forge-lint: disable-next-line(unsafe-typecast)
            staticWords = uint16(product);
        }

        desc = new bytes(nodeLength);

        // Type code.
        desc[0] = bytes1(TypeCode.STATIC_ARRAY);

        // Meta: staticWords(12) | nodeLength(12), both <= 4095.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint24 meta = (uint24(staticWords) << 12) | uint24(nodeLength);
        Be24.write(desc, DF.TYPECODE_SIZE, meta);

        // Element descriptor.
        uint256 cursor = DF.ARRAY_HEADER_SIZE;
        for (uint256 i; i < elemLength; ++i) {
            unchecked {
                desc[cursor++] = elemDesc[i];
            }
        }

        // Big-endian uint16 length.
        Be16.write(desc, cursor, length);
    }

    /// @notice Builds a tuple type descriptor.
    /// @dev Format: [TUPLE][meta][fieldCount][fields...]. Sizes per DescriptorFormat.
    /// @param fields The array of field type descriptors.
    /// @return desc The type descriptor bytes for tuple.
    function tuple_(bytes[] memory fields) internal pure returns (bytes memory desc) {
        uint256 fieldCount = fields.length;
        require(fieldCount != 0, InvalidLength());
        require(fieldCount <= DF.MAX_TUPLE_FIELDS, TupleFieldCountTooLarge(fieldCount, DF.MAX_TUPLE_FIELDS));

        // Calculate total size and staticWords.
        uint256 totalFieldsLength;
        uint256 sumStaticWords;
        bool anyDynamic;
        for (uint256 i; i < fieldCount; ++i) {
            bytes memory f = fields[i];
            uint256 fieldLength = f.length;
            require(fieldLength != 0, EmptyType());
            totalFieldsLength += fieldLength;

            uint16 fieldStaticWords = _extractStaticWords(f);
            if (fieldStaticWords == 0) anyDynamic = true;
            else sumStaticWords += fieldStaticWords;
        }

        uint256 nodeLength = DF.TUPLE_HEADER_SIZE + totalFieldsLength;
        require(nodeLength <= DF.MAX_NODE_LENGTH, NodeLengthTooLarge(nodeLength, DF.MAX_NODE_LENGTH));

        // Compute tuple's staticWords.
        uint16 staticWords;
        if (anyDynamic) {
            staticWords = 0;
        } else {
            require(sumStaticWords <= DF.MAX_STATIC_WORDS, ArrayProductTooLarge(sumStaticWords, DF.MAX_STATIC_WORDS));
            // forge-lint: disable-next-line(unsafe-typecast)
            staticWords = uint16(sumStaticWords);
        }

        // Allocate exact size.
        desc = new bytes(nodeLength);

        // Type code.
        desc[0] = bytes1(TypeCode.TUPLE);

        // Meta: staticWords(12) | nodeLength(12), both <= 4095.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint24 meta = (uint24(staticWords) << 12) | uint24(nodeLength);
        Be24.write(desc, DF.TYPECODE_SIZE, meta);

        // forge-lint: disable-next-line(unsafe-typecast)
        Be16.write(desc, DF.TUPLE_FIELDCOUNT_OFFSET, uint16(fieldCount));

        // Copy field descriptors.
        uint256 cursor = DF.TUPLE_HEADER_SIZE;
        for (uint256 i; i < fieldCount; ++i) {
            bytes memory f = fields[i];
            uint256 fieldLength = f.length;
            for (uint256 j; j < fieldLength; ++j) {
                unchecked {
                    desc[cursor++] = f[j];
                }
            }
        }
    }

    function tuple_(bytes memory f1) internal pure returns (bytes memory desc) {
        bytes[] memory fields = new bytes[](1);
        fields[0] = f1;
        return tuple_(fields);
    }

    function tuple_(bytes memory f1, bytes memory f2) internal pure returns (bytes memory desc) {
        bytes[] memory fields = new bytes[](2);
        fields[0] = f1;
        fields[1] = f2;
        return tuple_(fields);
    }

    function tuple_(bytes memory f1, bytes memory f2, bytes memory f3) internal pure returns (bytes memory desc) {
        bytes[] memory fields = new bytes[](3);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](4);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](5);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](6);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](7);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        fields[6] = f7;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](8);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        fields[6] = f7;
        fields[7] = f8;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](9);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        fields[6] = f7;
        fields[7] = f8;
        fields[8] = f9;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](10);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        fields[6] = f7;
        fields[7] = f8;
        fields[8] = f9;
        fields[9] = f10;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](11);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        fields[6] = f7;
        fields[7] = f8;
        fields[8] = f9;
        fields[9] = f10;
        fields[10] = f11;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11,
        bytes memory f12
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](12);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        fields[6] = f7;
        fields[7] = f8;
        fields[8] = f9;
        fields[9] = f10;
        fields[10] = f11;
        fields[11] = f12;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11,
        bytes memory f12,
        bytes memory f13
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](13);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        fields[6] = f7;
        fields[7] = f8;
        fields[8] = f9;
        fields[9] = f10;
        fields[10] = f11;
        fields[11] = f12;
        fields[12] = f13;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11,
        bytes memory f12,
        bytes memory f13,
        bytes memory f14
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](14);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        fields[6] = f7;
        fields[7] = f8;
        fields[8] = f9;
        fields[9] = f10;
        fields[10] = f11;
        fields[11] = f12;
        fields[12] = f13;
        fields[13] = f14;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11,
        bytes memory f12,
        bytes memory f13,
        bytes memory f14,
        bytes memory f15
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](15);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        fields[6] = f7;
        fields[7] = f8;
        fields[8] = f9;
        fields[9] = f10;
        fields[10] = f11;
        fields[11] = f12;
        fields[12] = f13;
        fields[13] = f14;
        fields[14] = f15;
        return tuple_(fields);
    }

    function tuple_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11,
        bytes memory f12,
        bytes memory f13,
        bytes memory f14,
        bytes memory f15,
        bytes memory f16
    )
        internal
        pure
        returns (bytes memory desc)
    {
        bytes[] memory fields = new bytes[](16);
        fields[0] = f1;
        fields[1] = f2;
        fields[2] = f3;
        fields[3] = f4;
        fields[4] = f5;
        fields[5] = f6;
        fields[6] = f7;
        fields[7] = f8;
        fields[8] = f9;
        fields[9] = f10;
        fields[10] = f11;
        fields[11] = f12;
        fields[12] = f13;
        fields[13] = f14;
        fields[14] = f15;
        fields[15] = f16;
        return tuple_(fields);
    }

    /// @notice Builds a tuple struct descriptor.
    /// @dev An ergonomic alias for tuple; it forwards to the canonical implementation.
    /// @param fields The array of field type descriptors.
    /// @return desc The type descriptor bytes for struct.
    function struct_(bytes[] memory fields) internal pure returns (bytes memory) {
        return tuple_(fields);
    }

    function struct_(bytes memory f1) internal pure returns (bytes memory) {
        return tuple_(f1);
    }

    function struct_(bytes memory f1, bytes memory f2) internal pure returns (bytes memory) {
        return tuple_(f1, f2);
    }

    function struct_(bytes memory f1, bytes memory f2, bytes memory f3) internal pure returns (bytes memory) {
        return tuple_(f1, f2, f3);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6, f7);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6, f7, f8);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6, f7, f8, f9);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6, f7, f8, f9, f10);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11,
        bytes memory f12
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11,
        bytes memory f12,
        bytes memory f13
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11,
        bytes memory f12,
        bytes memory f13,
        bytes memory f14
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11,
        bytes memory f12,
        bytes memory f13,
        bytes memory f14,
        bytes memory f15
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15);
    }

    function struct_(
        bytes memory f1,
        bytes memory f2,
        bytes memory f3,
        bytes memory f4,
        bytes memory f5,
        bytes memory f6,
        bytes memory f7,
        bytes memory f8,
        bytes memory f9,
        bytes memory f10,
        bytes memory f11,
        bytes memory f12,
        bytes memory f13,
        bytes memory f14,
        bytes memory f15,
        bytes memory f16
    )
        internal
        pure
        returns (bytes memory)
    {
        return tuple_(f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15, f16);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Wraps a single type code byte into a bytes memory descriptor.
    /// @param code The type code.
    /// @return desc Single-byte type descriptor.
    function _elementary(uint8 code) private pure returns (bytes memory desc) {
        desc = new bytes(1);
        desc[0] = bytes1(code);
    }

    /// @dev Extracts staticWords from a type descriptor.
    /// @param typeDesc The type descriptor bytes.
    /// @return staticWords Static size in 32-byte words (0 means dynamic).
    function _extractStaticWords(bytes memory typeDesc) private pure returns (uint16) {
        uint8 code = uint8(typeDesc[0]);

        // Elementary types: staticWords = 1 (32 bytes) except for bytes/string which are dynamic.
        if (TypeRule.isElementary(code)) return (code == TypeCode.BYTES || code == TypeCode.STRING) ? 0 : 1;

        // Composite types: meta is 24-bit, shift by 12 yields 12 bits.
        uint24 meta = Be24.readUnchecked(typeDesc, 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(meta >> DF.META_STATIC_WORDS_SHIFT);
    }
}

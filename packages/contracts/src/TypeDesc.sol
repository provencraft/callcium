// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Be16 } from "./Be16.sol";
import { Be24 } from "./Be24.sol";
import { DescriptorFormat as DF } from "./DescriptorFormat.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";

/// @title TypeDesc
/// @notice Constructors for type descriptor nodes.
library TypeDesc {
    /*/////////////////////////////////////////////////////////////////////////
                                     ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a provided type descriptor is empty.
    error EmptyType();

    /// @notice Thrown when a tuple field count falls outside the range the format allows.
    error InvalidTupleFieldCount(uint256 count, uint256 max);

    /// @notice Thrown when a static array length falls outside the range the format allows.
    error InvalidArrayLength(uint256 length, uint256 max);

    /// @notice Thrown when a node's static word count exceeds the maximum.
    error StaticWordsTooLarge(uint256 staticWords, uint256 max);

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

        desc[0] = bytes1(TypeCode.DYNAMIC_ARRAY);

        // A dynamic array declares no static words, so meta carries nodeLength alone.
        // forge-lint: disable-next-line(unsafe-typecast) bounded by the `NodeLengthTooLarge` check above.
        uint24 meta = uint24(nodeLength);
        Be24.write(desc, DF.TYPECODE_SIZE, meta);

        uint256 cursor = DF.ARRAY_HEADER_SIZE;
        for (uint256 i = 0; i < elemLength; ++i) {
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
        // forgefmt: disable-next-item
        require(
            length != 0 && length <= DF.MAX_STATIC_ARRAY_LENGTH,
            InvalidArrayLength(length, DF.MAX_STATIC_ARRAY_LENGTH)
        );
        require(elemDesc.length != 0, EmptyType());

        uint256 elemLength = elemDesc.length;
        uint256 nodeLength = DF.ARRAY_HEADER_SIZE + elemLength + DF.ARRAY_LENGTH_SIZE;
        require(nodeLength <= DF.MAX_NODE_LENGTH, NodeLengthTooLarge(nodeLength, DF.MAX_NODE_LENGTH));

        uint16 elemStaticWords = _extractStaticWords(elemDesc);

        uint16 staticWords;
        if (elemStaticWords == 0) {
            staticWords = 0;
        } else {
            uint256 product = uint256(length) * uint256(elemStaticWords);
            require(product <= DF.MAX_STATIC_WORDS, StaticWordsTooLarge(product, DF.MAX_STATIC_WORDS));
            // forge-lint: disable-next-line(unsafe-typecast) bounded by the `StaticWordsTooLarge` check above.
            staticWords = uint16(product);
        }

        desc = new bytes(nodeLength);

        desc[0] = bytes1(TypeCode.STATIC_ARRAY);

        // Meta packs staticWords and nodeLength, each bounded by its DescriptorFormat maximum.
        // forge-lint: disable-next-line(unsafe-typecast) bounded by the `NodeLengthTooLarge` check above.
        uint24 meta = (uint24(staticWords) << 12) | uint24(nodeLength);
        Be24.write(desc, DF.TYPECODE_SIZE, meta);

        uint256 cursor = DF.ARRAY_HEADER_SIZE;
        for (uint256 i = 0; i < elemLength; ++i) {
            unchecked {
                desc[cursor++] = elemDesc[i];
            }
        }

        Be16.write(desc, cursor, length);
    }

    /// @notice Builds a tuple type descriptor.
    /// @dev Format: [TUPLE][meta][fieldCount][fields...]. Sizes per DescriptorFormat.
    /// @param fields The array of field type descriptors.
    /// @return desc The type descriptor bytes for tuple.
    function tuple_(bytes[] memory fields) internal pure returns (bytes memory desc) {
        uint256 fieldCount = fields.length;
        // forgefmt: disable-next-item
        require(
            fieldCount != 0 && fieldCount <= DF.MAX_TUPLE_FIELDS,
            InvalidTupleFieldCount(fieldCount, DF.MAX_TUPLE_FIELDS)
        );

        // Calculate total size and staticWords.
        uint256 totalFieldsLength = 0;
        uint256 sumStaticWords = 0;
        bool anyDynamic = false;
        for (uint256 i = 0; i < fieldCount; ++i) {
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

        uint16 staticWords;
        if (anyDynamic) {
            staticWords = 0;
        } else {
            require(sumStaticWords <= DF.MAX_STATIC_WORDS, StaticWordsTooLarge(sumStaticWords, DF.MAX_STATIC_WORDS));
            // forge-lint: disable-next-line(unsafe-typecast) bounded by the `StaticWordsTooLarge` check above.
            staticWords = uint16(sumStaticWords);
        }

        desc = new bytes(nodeLength);

        desc[0] = bytes1(TypeCode.TUPLE);

        // Meta packs staticWords and nodeLength, each bounded by its DescriptorFormat maximum.
        // forge-lint: disable-next-line(unsafe-typecast) bounded by the `NodeLengthTooLarge` check above.
        uint24 meta = (uint24(staticWords) << 12) | uint24(nodeLength);
        Be24.write(desc, DF.TYPECODE_SIZE, meta);

        // forge-lint: disable-next-line(unsafe-typecast) bounded by the `InvalidTupleFieldCount` check above.
        Be16.write(desc, DF.TUPLE_FIELDCOUNT_OFFSET, uint16(fieldCount));

        // Copy field descriptors.
        uint256 cursor = DF.TUPLE_HEADER_SIZE;
        for (uint256 i = 0; i < fieldCount; ++i) {
            bytes memory f = fields[i];
            uint256 fieldLength = f.length;
            for (uint256 j = 0; j < fieldLength; ++j) {
                unchecked {
                    desc[cursor++] = f[j];
                }
            }
        }
    }

    function tuple_(bytes memory f1, bytes memory f2) internal pure returns (bytes memory desc) {
        bytes[] memory fields = new bytes[](2);
        fields[0] = f1;
        fields[1] = f2;
        return tuple_(fields);
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

        if (TypeRule.isElementary(code)) return (code == TypeCode.BYTES || code == TypeCode.STRING) ? 0 : 1;

        uint24 meta = Be24.readUnchecked(typeDesc, 1);
        // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the meta's static words.
        return uint16(meta >> DF.META_STATIC_WORDS_SHIFT);
    }
}

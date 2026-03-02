// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Be16 } from "./Be16.sol";
import { Be24 } from "./Be24.sol";
import { DescriptorFormat as DF } from "./DescriptorFormat.sol";
import { Path } from "./Path.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";

/// @title Descriptor
/// @notice Validation and lightweight views for parameter descriptors.
library Descriptor {
    /// @notice Minimal type view at a resolved descriptor node.
    struct TypeInfo {
        /// TypeCode at the node (elementary or composite).
        uint8 code;
        /// True if the type has dynamic ABI encoding.
        bool isDynamic;
        /// ABI head size in bytes; 0 if dynamic.
        uint32 staticSize;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                     ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the descriptor is too short to contain a valid header.
    error MalformedHeader();

    /// @notice Thrown when the descriptor version is not supported.
    error UnsupportedVersion(uint8 version);

    /// @notice Thrown when parsing reaches end of descriptor unexpectedly.
    error UnexpectedEnd();

    /// @notice Thrown when an unrecognized type code is encountered.
    error UnknownTypeCode(uint8 code);

    /// @notice Thrown when a static array has zero length.
    error InvalidArrayLength();

    /// @notice Thrown when a tuple has zero fields.
    error InvalidTupleFieldCount();

    /// @notice Thrown when the declared param count does not match the parsed count.
    error ParamCountMismatch(uint8 declared, uint256 parsed);

    /// @notice Thrown when the descriptor contains more than 255 top-level parameters.
    error TooManyParams();

    /// @notice Thrown when accessing a top-level parameter index out of bounds.
    error ParamIndexOutOfBounds(uint256 index, uint256 count);

    /// @notice Thrown when the argument index in a path is out of bounds.
    error ArgIndexOutOfBounds(uint256 argIndex, uint256 argCount);

    /// @notice Thrown when the tuple field index is out of bounds.
    error TupleFieldOutOfBounds(uint256 fieldIndex, uint256 fieldCount);

    /// @notice Thrown when the array index is out of bounds.
    error ArrayIndexOutOfBounds(uint256 elementIndex, uint256 length);

    /// @notice Thrown when a composite type is expected but a different type is found.
    error NotComposite(uint8 typeCode);

    /// @notice Thrown when a composite node's declared length is smaller than its header.
    error NodeLengthTooSmall(uint256 offset, uint16 nodeLength);

    /// @notice Thrown when a composite node overflows the descriptor buffer.
    error NodeOverflow(uint256 offset);

    /// @notice Thrown when a static array length exceeds the format maximum.
    error ArrayLengthTooLarge(uint256 offset, uint16 length);

    /// @notice Thrown when a tuple field count exceeds the format maximum.
    error TupleFieldCountTooLarge(uint256 offset, uint16 fieldCount);

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the descriptor format version.
    /// @param self The descriptor.
    /// @return The version byte.
    function version(bytes memory self) internal pure returns (uint8) {
        require(self.length >= 1, MalformedHeader());
        return uint8(self[DF.HEADER_VERSION_OFFSET]);
    }

    /// @notice Returns the declared top-level parameter count from the header.
    /// @param self The descriptor.
    /// @return The number of top-level parameters declared in the header.
    function paramCount(bytes memory self) internal pure returns (uint8) {
        require(self.length >= DF.HEADER_SIZE, MalformedHeader());
        return uint8(self[DF.HEADER_PARAMCOUNT_OFFSET]);
    }

    /// @notice Validates the descriptor.
    /// @param self The descriptor to validate.
    function validate(bytes memory self) internal pure {
        uint8 formatVersion = version(self);
        require(formatVersion == DF.VERSION, UnsupportedVersion(formatVersion));

        uint8 declaredCount = paramCount(self);

        uint256 cursor = DF.HEADER_SIZE;
        uint256 parsedCount;
        uint256 descLength = self.length;
        while (cursor < descLength) {
            cursor = _validateNode(self, cursor);
            unchecked {
                ++parsedCount;
            }
            require(parsedCount <= type(uint8).max, TooManyParams());
        }

        require(parsedCount == declaredCount, ParamCountMismatch(declaredCount, parsedCount));
    }

    /// @notice Decodes the 3-byte composite metadata at offset.
    /// @param self The descriptor bytes.
    /// @param offset Offset of the meta bytes (after the type code).
    /// @return staticWords Static size in 32-byte words (0 means dynamic).
    /// @return nodeLength Total bytes for this node's descriptor subtree.
    function decodeMeta(
        bytes memory self,
        uint256 offset
    )
        internal
        pure
        returns (uint16 staticWords, uint16 nodeLength)
    {
        // meta is 24-bit: staticWords(12) | nodeLength(12), both fit in uint16.
        uint24 meta = Be24.read(self, offset);
        // forge-lint: disable-next-line(unsafe-typecast)
        staticWords = uint16(meta >> DF.META_STATIC_WORDS_SHIFT);
        // forge-lint: disable-next-line(unsafe-typecast)
        nodeLength = uint16(meta & DF.META_NODE_LENGTH_MASK);
    }

    /// @notice Inspects type descriptor at offset. Returns code, dynamic/static info, and next offset.
    /// @param self The descriptor bytes.
    /// @param offset Start offset of a type descriptor within `self`.
    /// @return code The type code byte.
    /// @return isDynamic True if the type has dynamic ABI encoding.
    /// @return staticSize ABI head size in bytes (0 if dynamic).
    /// @return next Byte offset immediately after this node in the descriptor.
    function inspect(
        bytes memory self,
        uint256 offset
    )
        internal
        pure
        returns (uint8 code, bool isDynamic, uint32 staticSize, uint256 next)
    {
        require(offset < self.length, UnexpectedEnd());
        code = uint8(self[offset]);

        // Elementary types: no header, derive from type code.
        if (TypeRule.isElementary(code)) {
            return TypeRule.hasCalldataLength(code)
                ? (code, true, 0, offset + DF.TYPECODE_SIZE)
                : (code, false, 32, offset + DF.TYPECODE_SIZE);
        }

        // Unknown type codes revert before attempting to read composite meta.
        require(TypeRule.isComposite(code), UnknownTypeCode(code));

        // Composite types: read 3-byte meta after type code.
        require(offset + DF.TYPECODE_SIZE + DF.COMPOSITE_META_SIZE <= self.length, UnexpectedEnd());
        (uint16 staticWords, uint16 nodeLength) = decodeMeta(self, offset + DF.TYPECODE_SIZE);

        // Validate nodeLength covers at least the composite header.
        uint256 minHeader = (code == TypeCode.TUPLE) ? DF.TUPLE_HEADER_SIZE : DF.ARRAY_HEADER_SIZE;
        require(nodeLength >= minHeader, NodeLengthTooSmall(offset, nodeLength));
        require(offset + nodeLength <= self.length, NodeOverflow(offset));

        isDynamic = (staticWords == 0);
        staticSize = isDynamic ? 0 : uint32(staticWords) << 5;
        next = offset + nodeLength;
    }

    /// @notice Returns the descriptor offset of the i-th top-level parameter.
    /// @param self The descriptor bytes.
    /// @param index Top-level parameter index.
    /// @return startOffset Byte offset of the parameter's type descriptor.
    function at(bytes memory self, uint256 index) internal pure returns (uint256 startOffset) {
        uint256 count = paramCount(self);
        require(index < count, ParamIndexOutOfBounds(index, count));
        startOffset = DF.HEADER_SIZE;
        for (uint256 i; i < index; ++i) {
            (,,, startOffset) = inspect(self, startOffset);
        }
    }

    /// @notice Returns the descriptor offset of the i-th top-level parameter without bounds checks.
    /// @param self The descriptor bytes.
    /// @param index Top-level parameter index.
    /// @return startOffset Byte offset of the parameter's type descriptor.
    function atUnchecked(bytes memory self, uint256 index) internal pure returns (uint256 startOffset) {
        startOffset = DF.HEADER_SIZE;
        for (uint256 i; i < index; ++i) {
            (,,, startOffset) = inspect(self, startOffset);
        }
    }

    /// @notice Returns the field count for a tuple at `tupleOffset`.
    /// @param self The descriptor bytes.
    /// @param tupleOffset Offset of a tuple node within `self`.
    /// @return The number of fields in the tuple.
    function tupleFieldCount(bytes memory self, uint256 tupleOffset) internal pure returns (uint16) {
        // Ensure header is present.
        require(tupleOffset + DF.TUPLE_HEADER_SIZE <= self.length, UnexpectedEnd());
        return Be16.readUnchecked(self, tupleOffset + DF.TUPLE_FIELDCOUNT_OFFSET);
    }

    /// @notice Returns the descriptor offset of the `fieldIndex`-th tuple field.
    /// @dev Does not perform bounds checks on `fieldIndex`.
    /// @param self The descriptor bytes.
    /// @param tupleOffset Offset of a tuple node within `self`.
    /// @param fieldIndex Field index (0-based).
    /// @return fieldDescOffset Byte offset of the field's type descriptor.
    function tupleFieldOffset(
        bytes memory self,
        uint256 tupleOffset,
        uint16 fieldIndex
    )
        internal
        pure
        returns (uint256 fieldDescOffset)
    {
        fieldDescOffset = tupleOffset + DF.TUPLE_HEADER_SIZE;
        for (uint256 j; j < fieldIndex; ++j) {
            uint256 next;
            (,,, next) = inspect(self, fieldDescOffset);
            unchecked {
                fieldDescOffset = next;
            }
        }
    }

    /// @notice Returns the fixed length for a static array node at `arrayOffset`.
    /// @param self The descriptor bytes.
    /// @param arrayOffset Offset of a static array node within `self`.
    /// @return The fixed element count of the static array.
    function staticArrayLength(bytes memory self, uint256 arrayOffset) internal pure returns (uint16) {
        uint256 elementDescOffset = arrayOffset + DF.ARRAY_HEADER_SIZE;
        (,,, uint256 elementDescEnd) = inspect(self, elementDescOffset);
        require(elementDescEnd + DF.ARRAY_LENGTH_SIZE <= self.length, UnexpectedEnd());

        uint16 fixedLength = Be16.readUnchecked(self, elementDescEnd);
        require(fixedLength != 0, InvalidArrayLength());
        return fixedLength;
    }

    /// @notice Returns the type info (type code + static/dynamic info) at path.
    /// @dev The first path element is the argument index.
    /// @param self The descriptor bytes.
    /// @param path Path encoded as big-endian uint16 steps.
    /// @return The type info at the resolved path.
    function typeAt(bytes memory self, bytes memory path) internal pure returns (TypeInfo memory) {
        // Validate descriptor version and resolve top-level argument.
        uint8 formatVersion = version(self);
        require(formatVersion == DF.VERSION, UnsupportedVersion(formatVersion));
        uint256 argIndex = Path.atUnchecked(path, 0);
        uint256 argCount = paramCount(self);
        require(argIndex < argCount, ArgIndexOutOfBounds(argIndex, argCount));
        uint256 descOffset = atUnchecked(self, argIndex);

        // Descend through subsequent path steps.
        uint256 depth = Path.validate(path);
        for (uint256 stepIndex = 1; stepIndex < depth; ++stepIndex) {
            uint256 childIndex = Path.atUnchecked(path, stepIndex);
            uint8 code = uint8(self[descOffset]);

            if (code == TypeCode.TUPLE) {
                uint256 fieldCount = tupleFieldCount(self, descOffset);
                require(childIndex < fieldCount, TupleFieldOutOfBounds(childIndex, fieldCount));
                // forge-lint: disable-next-line(unsafe-typecast)
                descOffset = tupleFieldOffset(self, descOffset, uint16(childIndex));
            } else if (code == TypeCode.STATIC_ARRAY) {
                uint256 arrayLength = staticArrayLength(self, descOffset);
                require(childIndex < arrayLength, ArrayIndexOutOfBounds(childIndex, arrayLength));
                descOffset += DF.ARRAY_HEADER_SIZE;
            } else if (code == TypeCode.DYNAMIC_ARRAY) {
                descOffset += DF.ARRAY_HEADER_SIZE;
            } else {
                revert NotComposite(code);
            }
        }

        (uint8 finalCode, bool isDynamic, uint32 staticSize,) = inspect(self, descOffset);
        return TypeInfo({ code: finalCode, isDynamic: isDynamic, staticSize: staticSize });
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Validates a descriptor node recursively and returns the offset after it.
    function _validateNode(bytes memory self, uint256 offset) private pure returns (uint256 next) {
        uint8 code;
        (code,,, next) = inspect(self, offset);

        if (code == TypeCode.TUPLE) {
            uint16 fields = tupleFieldCount(self, offset);
            require(fields > 0, InvalidTupleFieldCount());
            require(fields <= DF.MAX_TUPLE_FIELDS, TupleFieldCountTooLarge(offset, fields));
            uint256 child = offset + DF.TUPLE_HEADER_SIZE;
            for (uint256 i; i < fields; ++i) {
                child = _validateNode(self, child);
            }
        } else if (code == TypeCode.STATIC_ARRAY) {
            // Validate element type recursively.
            uint256 elemEnd = _validateNode(self, offset + DF.ARRAY_HEADER_SIZE);
            // Read and validate the length suffix after the element descriptor.
            require(elemEnd + DF.ARRAY_LENGTH_SIZE <= self.length, UnexpectedEnd());
            uint16 length = Be16.readUnchecked(self, elemEnd);
            require(length > 0, InvalidArrayLength());
            require(length <= DF.MAX_STATIC_ARRAY_LENGTH, ArrayLengthTooLarge(offset, length));
        } else if (code == TypeCode.DYNAMIC_ARRAY) {
            // Validate element type recursively.
            _validateNode(self, offset + DF.ARRAY_HEADER_SIZE);
        }
    }
}

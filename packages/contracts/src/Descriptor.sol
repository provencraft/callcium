// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Be16 } from "./Be16.sol";
import { DescriptorFormat as DF } from "./DescriptorFormat.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";
import { LibBytes } from "./vendor/solady/utils/LibBytes.sol";

/// @title Descriptor
/// @notice Validation and lightweight views for parameter descriptors.
library Descriptor {
    /// @notice Composite node metadata that disagrees with the node's children.
    enum MetaFault {
        None,
        NodeLength,
        StaticWords
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

    /// @notice Thrown when a static array length falls outside the range the format allows.
    /// @param offset The offset of the array node.
    /// @param length The declared length.
    error InvalidArrayLength(uint256 offset, uint256 length);

    /// @notice Thrown when a tuple field count falls outside the range the format allows.
    /// @param offset The offset of the tuple node.
    /// @param fieldCount The declared field count.
    error InvalidTupleFieldCount(uint256 offset, uint256 fieldCount);

    /// @notice Thrown when the declared param count does not match the parsed count.
    error ParamCountMismatch(uint8 declared, uint256 parsed);

    /// @notice Thrown when the descriptor contains more than 255 top-level parameters.
    error TooManyParams();

    /// @notice Thrown when accessing a top-level parameter index out of bounds.
    error ParamIndexOutOfBounds(uint256 index, uint256 count);

    /// @notice Thrown when the tuple field index is out of bounds.
    error TupleFieldOutOfBounds(uint256 fieldIndex, uint256 fieldCount);

    /// @notice Thrown when the static array index is out of bounds.
    error StaticArrayIndexOutOfBounds(uint256 elementIndex, uint256 length);

    /// @notice Thrown when a composite type is expected but a different type is found.
    error NotComposite(uint8 typeCode);

    /// @notice Thrown when a composite node's declared length is smaller than its header.
    error NodeLengthTooSmall(uint256 offset, uint16 nodeLength);

    /// @notice Thrown when a composite node overflows the descriptor buffer.
    error NodeOverflow(uint256 offset);

    /// @notice Thrown when composite nesting exceeds the maximum depth.
    error NestingTooDeep(uint256 offset);

    /// @notice Thrown when a composite node's length differs from the span of its children.
    /// @param offset The offset of the node.
    error NodeLengthMismatch(uint256 offset);

    /// @notice Thrown when a composite node's static word count differs from its type's ABI head size.
    /// @param offset The offset of the node.
    error StaticWordsMismatch(uint256 offset);

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

        uint256 cursor = DF.HEADER_SIZE;
        uint256 parsedCount = 0;
        uint256 descLength = self.length;
        while (cursor < descLength) {
            cursor = _validateNode(self, cursor, 1);
            unchecked {
                ++parsedCount;
            }
            require(parsedCount <= DF.MAX_PARAMS, TooManyParams());
        }

        uint8 declaredCount = paramCount(self);
        require(parsedCount == declaredCount, ParamCountMismatch(declaredCount, parsedCount));
    }

    /// @notice Validates every composite node's metadata against its children (DV-1, DV-2).
    /// @dev The descriptor must be well-formed.
    /// @param self The descriptor to validate.
    function validateMeta(bytes memory self) internal pure {
        (MetaFault fault, uint256 offset) = tryValidateMeta(self);
        require(fault != MetaFault.NodeLength, NodeLengthMismatch(offset));
        require(fault != MetaFault.StaticWords, StaticWordsMismatch(offset));
    }

    /// @notice Finds the first composite node whose metadata disagrees with its children (DV-1, DV-2).
    /// @dev The descriptor must be well-formed. A node's children are checked before the node.
    /// @param self The descriptor to check.
    /// @return fault The disagreement, or none when every node agrees.
    /// @return offset The offset of the node at fault, or zero when there is none.
    function tryValidateMeta(bytes memory self) internal pure returns (MetaFault fault, uint256 offset) {
        uint256 cursor = DF.HEADER_SIZE;
        uint256 count = paramCount(self);
        for (uint256 i = 0; i < count; ++i) {
            uint256 span;
            (fault, offset, span,) = _walkMeta(self, cursor);
            if (fault != MetaFault.None) return (fault, offset);
            cursor += span;
        }
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

        // One word covers the type code and, for composites, the meta after it.
        uint256 word = uint256(LibBytes.load(self, offset));
        // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the type code.
        code = uint8(word >> (256 - 8 * DF.TYPECODE_SIZE));

        // Elementary types: no header, derive from type code.
        if (TypeRule.isElementary(code)) {
            return TypeRule.hasCalldataLength(code)
                ? (code, true, 0, offset + DF.TYPECODE_SIZE)
                : (code, false, 32, offset + DF.TYPECODE_SIZE);
        }

        // Unknown type codes revert before attempting to read composite meta.
        require(TypeRule.isComposite(code), UnknownTypeCode(code));

        require(offset + DF.TYPECODE_SIZE + DF.COMPOSITE_META_SIZE <= self.length, UnexpectedEnd());
        // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: `meta`.
        uint24 meta = uint24(word >> (256 - 8 * (DF.TYPECODE_SIZE + DF.COMPOSITE_META_SIZE)));
        // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the meta's static words.
        uint16 staticWords = uint16(meta >> DF.META_STATIC_WORDS_SHIFT);
        // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the meta's node length.
        uint16 nodeLength = uint16(meta & DF.META_NODE_LENGTH_MASK);

        // Validate nodeLength covers at least the composite header.
        uint256 minHeader = (code == TypeCode.TUPLE) ? DF.TUPLE_HEADER_SIZE : DF.ARRAY_HEADER_SIZE;
        require(nodeLength >= minHeader, NodeLengthTooSmall(offset, nodeLength));
        require(offset + nodeLength <= self.length, NodeOverflow(offset));

        isDynamic = (staticWords == 0);
        staticSize = isDynamic ? 0 : uint32(staticWords) << 5;
        next = offset + nodeLength;
    }

    /// @notice Returns the field count for a tuple at `tupleOffset`.
    /// @param self The descriptor bytes.
    /// @param tupleOffset Offset of a tuple node within `self`.
    /// @return The number of fields in the tuple.
    function tupleFieldCount(bytes memory self, uint256 tupleOffset) internal pure returns (uint16) {
        require(tupleOffset + DF.TUPLE_HEADER_SIZE <= self.length, UnexpectedEnd());
        return Be16.readUnchecked(self, tupleOffset + DF.TUPLE_FIELDCOUNT_OFFSET);
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
        require(fixedLength != 0, InvalidArrayLength(arrayOffset, fixedLength));
        return fixedLength;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Validates a descriptor node recursively and returns the offset after it.
    function _validateNode(bytes memory self, uint256 offset, uint256 depth) private pure returns (uint256 next) {
        uint8 code;
        (code,,, next) = inspect(self, offset);

        // Only composites nest; a leaf below the deepest allowed composite is fine.
        if (TypeRule.isComposite(code)) require(depth <= DF.MAX_NESTING_DEPTH, NestingTooDeep(offset));

        if (code == TypeCode.TUPLE) {
            uint16 fields = tupleFieldCount(self, offset);
            require(fields > 0 && fields <= DF.MAX_TUPLE_FIELDS, InvalidTupleFieldCount(offset, fields));
            uint256 child = offset + DF.TUPLE_HEADER_SIZE;
            for (uint256 i = 0; i < fields; ++i) {
                child = _validateNode(self, child, depth + 1);
            }
        } else if (code == TypeCode.STATIC_ARRAY) {
            uint256 elemEnd = _validateNode(self, offset + DF.ARRAY_HEADER_SIZE, depth + 1);
            // Read and validate the length suffix after the element descriptor.
            require(elemEnd + DF.ARRAY_LENGTH_SIZE <= self.length, UnexpectedEnd());
            uint16 length = Be16.readUnchecked(self, elemEnd);
            require(length > 0 && length <= DF.MAX_STATIC_ARRAY_LENGTH, InvalidArrayLength(offset, length));
        } else if (code == TypeCode.DYNAMIC_ARRAY) {
            _validateNode(self, offset + DF.ARRAY_HEADER_SIZE, depth + 1);
        }
    }

    /// @dev Walks the node at `offset` by the spans of its children. Returns the span and the static word count of the
    /// node's type, or the first node whose metadata disagrees with its children.
    function _walkMeta(
        bytes memory self,
        uint256 offset
    )
        private
        pure
        returns (MetaFault fault, uint256 faultOffset, uint256 span, uint256 staticWords)
    {
        (uint8 code, bool isDynamic, uint32 staticSize, uint256 next) = inspect(self, offset);
        if (TypeRule.isElementary(code)) return (MetaFault.None, 0, DF.TYPECODE_SIZE, isDynamic ? 0 : 1);

        uint256 childSpan;
        uint256 childWords;
        if (code == TypeCode.TUPLE) {
            uint256 fieldCount = tupleFieldCount(self, offset);
            span = DF.TUPLE_HEADER_SIZE;
            bool hasDynamicField = false;
            for (uint256 i = 0; i < fieldCount; ++i) {
                (fault, faultOffset, childSpan, childWords) = _walkMeta(self, offset + span);
                if (fault != MetaFault.None) return (fault, faultOffset, 0, 0);
                span += childSpan;
                staticWords += childWords;
                if (childWords == 0) hasDynamicField = true;
            }
            if (hasDynamicField) staticWords = 0;
        } else {
            (fault, faultOffset, childSpan, childWords) = _walkMeta(self, offset + DF.ARRAY_HEADER_SIZE);
            if (fault != MetaFault.None) return (fault, faultOffset, 0, 0);
            span = DF.ARRAY_HEADER_SIZE + childSpan;
            if (code == TypeCode.STATIC_ARRAY) {
                staticWords = childWords * Be16.readUnchecked(self, offset + span);
                span += DF.ARRAY_LENGTH_SIZE;
            }
        }
        if (span != next - offset) return (MetaFault.NodeLength, offset, 0, 0);
        if (staticWords != staticSize / 32) return (MetaFault.StaticWords, offset, 0, 0);
    }
}

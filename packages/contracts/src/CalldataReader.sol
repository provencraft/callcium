// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Descriptor } from "./Descriptor.sol";
import { DescriptorFormat as DF } from "./DescriptorFormat.sol";

import { Path } from "./Path.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";
import { LibBytes } from "solady/utils/LibBytes.sol";

/// @title CalldataReader
/// @notice Descriptor-guided calldata traversal by path indices.
library CalldataReader {
    /// @notice Reader configuration for traversal.
    struct Config {
        /// 0 or 4 are typical values (4 when parsing calldata with a selector; 0 for raw ABI blobs).
        uint256 baseOffset;
    }

    /// @notice A resolved position within calldata for a node.
    /// @dev We use "node" for the conceptual element in the ABI type tree, and "Location" for
    /// the struct that points to that node (offsets, descriptor, and minimal type info).
    struct Location {
        /// Byte offset in calldata for the head slot of the node.
        uint256 head;
        /// Composite start for composite-relative offsets.
        uint256 base;
        /// Descriptor offset for the type at this node.
        uint256 descOffset;
        /// Minimal type info.
        Descriptor.TypeInfo typeInfo;
    }

    /// @notice View of a dynamic sequence payload.
    struct DynamicSlice {
        /// Payload start (after length word for bytes/string/arrays).
        uint256 dataOffset;
        /// Logical length (bytes for bytes/string, elements for arrays).
        uint256 length;
    }

    /// @notice Basic structural info for arrays.
    struct ArrayShape {
        /// True if element type has dynamic ABI encoding.
        bool elementIsDynamic;
        /// Element ABI head size in bytes; 0 if dynamic.
        uint32 elementStaticSize;
        /// Element type code.
        uint8 elementTypeCode;
        /// Element count (dynamic arrays) or fixed length for static arrays.
        uint256 length;
        /// Start of per-element heads (for dynamic elements).
        uint256 headsOffset;
        /// Start of inline element data (for static elements).
        uint256 dataOffset;
        /// Composite base used for interpreting per-element offsets.
        uint256 compositeBase;
        /// Descriptor offset for the element type.
        uint256 elementDescOffset;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                       ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the path exceeds the maximum allowed depth.
    error PathTooDeep(uint256 depth, uint256 maxDepth);

    /// @notice Thrown when the argument index is out of bounds.
    /// @param argIndex The provided argument index.
    /// @param argCount The declared argument count.
    error ArgIndexOutOfBounds(uint256 argIndex, uint256 argCount);

    /// @notice Thrown when the tuple field index is out of bounds.
    /// @param fieldIndex The provided field index.
    /// @param fieldCount The tuple field count.
    error TupleFieldOutOfBounds(uint256 fieldIndex, uint256 fieldCount);

    /// @notice Thrown when the array index is out of bounds.
    /// @param elementIndex The provided array element index.
    /// @param length The array length.
    error ArrayIndexOutOfBounds(uint256 elementIndex, uint256 length);

    /// @notice Thrown when a scalar word is expected but a non-scalar type is found.
    error NotScalar(uint8 typeCode);

    /// @notice Thrown when a type with calldata length is expected but a different type is found.
    error NoCalldataLength(uint8 typeCode);

    /// @notice Thrown when a composite type is expected but a different type is found.
    error NotComposite(uint8 typeCode);

    /// @notice Thrown on generic bounds failures.
    error CalldataOutOfBounds();

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Resolves a path to a calldata location.
    /// @dev The first path element is the argument index.
    /// @param desc Descriptor bytes.
    /// @param callData Full calldata buffer for the function call.
    /// @param path Path encoded as big-endian uint16 steps.
    /// @param config Traversal config.
    /// @return Resolved location for the path target.
    function locate(
        bytes memory desc,
        bytes calldata callData,
        bytes memory path,
        Config memory config
    )
        internal
        pure
        returns (Location memory)
    {
        // Validate descriptor version and argument index.
        uint8 formatVersion = Descriptor.version(desc);
        require(formatVersion == DF.VERSION, Descriptor.UnsupportedVersion(formatVersion));
        uint256 argIndex = Path.atUnchecked(path, 0);
        uint256 argCount = Descriptor.paramCount(desc);
        require(argIndex < argCount, ArgIndexOutOfBounds(argIndex, argCount));

        // Resolve head position for argument. Iterating manually because we need both descOffset and head.
        uint256 descOffset = DF.HEADER_SIZE;
        uint256 head = config.baseOffset;
        for (uint256 i; i < argIndex; ++i) {
            (, bool paramIsDynamic, uint32 paramStaticSize, uint256 paramDescEnd) = Descriptor.inspect(desc, descOffset);
            unchecked {
                head += paramIsDynamic ? 32 : uint256(paramStaticSize);
                descOffset = paramDescEnd;
            }
        }
        uint256 base = config.baseOffset;

        // Descend through subsequent steps if any.
        uint256 depth = Path.validate(path);
        for (uint256 stepIndex = 1; stepIndex < depth; ++stepIndex) {
            uint256 childIndex = Path.atUnchecked(path, stepIndex);
            (descOffset, head, base) = _descend(desc, descOffset, head, base, childIndex, callData);
        }

        // Build final TypeView from descriptor at descOffset.
        (uint8 code, bool isDynamic, uint32 staticSize,) = Descriptor.inspect(desc, descOffset);

        return Location({
            head: head,
            base: base,
            descOffset: descOffset,
            typeInfo: Descriptor.TypeInfo({ code: code, isDynamic: isDynamic, staticSize: staticSize })
        });
    }

    /// @notice Returns array shape (length, static/dynamic, offsets) for a target array at path.
    /// @dev The first path element is the argument index.
    /// @param desc The descriptor bytes.
    /// @param callData The calldata buffer.
    /// @param path Path encoded as big-endian uint16 steps.
    /// @param config Traversal configuration.
    /// @return The resolved array shape.
    function arrayShape(
        bytes memory desc,
        bytes calldata callData,
        bytes memory path,
        Config memory config
    )
        internal
        pure
        returns (ArrayShape memory)
    {
        Location memory location = locate(desc, callData, path, config);
        return arrayShape(desc, callData, location);
    }

    /// @notice Returns array shape for a target array at a resolved location.
    /// @param desc The descriptor bytes.
    /// @param callData The calldata buffer.
    /// @param location The resolved location of the array.
    /// @return The resolved array shape.
    function arrayShape(
        bytes memory desc,
        bytes calldata callData,
        Location memory location
    )
        internal
        pure
        returns (ArrayShape memory)
    {
        uint8 code = location.typeInfo.code;
        require(code == TypeCode.STATIC_ARRAY || code == TypeCode.DYNAMIC_ARRAY, NotComposite(code));

        // Use index=0 for _descendArrayMeta; validation passes since fixedLength >= 1 for static arrays.
        (
            uint256 elementDescOffset,
            uint8 elementTypeCode,
            bool elementIsDynamic,
            uint32 elementStaticSize,
            uint256 fixedLength
        ) = _descendArrayMeta(desc, location.descOffset, code, 0);

        if (code == TypeCode.DYNAMIC_ARRAY) {
            (uint256 arrayBase, uint256 length) = _dynamicArrayBaseAndLength(callData, location.base, location.head);

            if (elementIsDynamic) {
                return ArrayShape({
                    elementIsDynamic: true,
                    elementStaticSize: 0,
                    elementTypeCode: elementTypeCode,
                    length: length,
                    headsOffset: arrayBase + 32,
                    dataOffset: 0,
                    compositeBase: arrayBase + 32,
                    elementDescOffset: elementDescOffset
                });
            } else {
                return ArrayShape({
                    elementIsDynamic: false,
                    elementStaticSize: elementStaticSize,
                    elementTypeCode: elementTypeCode,
                    length: length,
                    headsOffset: 0,
                    dataOffset: arrayBase + 32,
                    compositeBase: arrayBase,
                    elementDescOffset: elementDescOffset
                });
            }
        }

        // Static array: fixedLength already read by _descendArrayMeta.
        if (elementIsDynamic) {
            uint256 arrayBase = location.base + uint256(_calldataload(callData, location.head));
            return ArrayShape({
                elementIsDynamic: true,
                elementStaticSize: 0,
                elementTypeCode: elementTypeCode,
                length: fixedLength,
                headsOffset: arrayBase,
                dataOffset: 0,
                compositeBase: arrayBase,
                elementDescOffset: elementDescOffset
            });
        } else {
            return ArrayShape({
                elementIsDynamic: false,
                elementStaticSize: elementStaticSize,
                elementTypeCode: elementTypeCode,
                length: fixedLength,
                headsOffset: 0,
                dataOffset: location.head,
                compositeBase: location.base,
                elementDescOffset: elementDescOffset
            });
        }
    }

    /// @notice Loads a scalar value from calldata at the resolved location.
    /// @dev For elementary types this returns the value. For dynamic types this returns the offset word.
    /// @param location The resolved location.
    /// @param callData The calldata buffer.
    /// @return The 32-byte scalar value at the location.
    function loadScalar(Location memory location, bytes calldata callData) internal pure returns (bytes32) {
        // forgefmt: disable-next-item
        require(
            location.typeInfo.isDynamic || (location.typeInfo.staticSize == 32 && TypeRule.isElementary(location.typeInfo.code)),
            NotScalar(location.typeInfo.code)
        );
        return _calldataload(callData, location.head);
    }

    /// @notice Resolves a dynamic sequence into its slice.
    /// @dev Returns the data offset and byte length of the dynamic content.
    /// @param location The resolved location.
    /// @param callData The calldata buffer.
    /// @return The dynamic slice (data offset and length).
    function loadSlice(Location memory location, bytes calldata callData) internal pure returns (DynamicSlice memory) {
        uint8 code = location.typeInfo.code;
        require(TypeRule.hasCalldataLength(code), NoCalldataLength(code));

        uint256 payloadBase = location.base + uint256(_calldataload(callData, location.head));
        uint256 length = uint256(_calldataload(callData, payloadBase));

        uint256 dataOffset = payloadBase + 32;
        uint256 callDataLength = callData.length;

        require(dataOffset <= callDataLength && length <= callDataLength - dataOffset, CalldataOutOfBounds());

        return DynamicSlice({ dataOffset: dataOffset, length: length });
    }

    /// @notice Returns a location for the element at `elementIndex` within a precomputed array shape.
    /// @param shape The precomputed array shape from `arrayShape()`.
    /// @param elementIndex Element index (0-based).
    /// @param callData The calldata buffer.
    /// @return The resolved location of the element.
    function arrayElementAt(
        ArrayShape memory shape,
        uint256 elementIndex,
        bytes calldata callData
    )
        internal
        pure
        returns (Location memory)
    {
        require(elementIndex < shape.length, ArrayIndexOutOfBounds(elementIndex, shape.length));

        uint256 head;
        uint256 base;
        unchecked {
            if (!shape.elementIsDynamic) {
                head = shape.dataOffset + elementIndex * uint256(shape.elementStaticSize);
                base = shape.compositeBase;
            } else {
                head = shape.headsOffset + (elementIndex << 5);
                base = shape.headsOffset;
            }
        }

        require(head + 32 <= callData.length, CalldataOutOfBounds());

        return Location({
            head: head,
            base: base,
            descOffset: shape.elementDescOffset,
            typeInfo: Descriptor.TypeInfo({
                code: shape.elementTypeCode,
                isDynamic: shape.elementIsDynamic,
                staticSize: shape.elementIsDynamic ? 0 : shape.elementStaticSize
            })
        });
    }

    /// @notice Gets a location for a tuple field by 0-based field index.
    /// @param desc The descriptor bytes.
    /// @param location The resolved tuple location.
    /// @param fieldIndex Tuple field index (0-based).
    /// @param callData The calldata buffer.
    /// @return The resolved location of the tuple field.
    function tupleField(
        bytes memory desc,
        Location memory location,
        uint16 fieldIndex,
        bytes calldata callData
    )
        internal
        pure
        returns (Location memory)
    {
        (uint8 parentCode,,,) = Descriptor.inspect(desc, location.descOffset);
        require(parentCode == TypeCode.TUPLE, NotComposite(parentCode));

        // forgefmt: disable-next-item
        (uint256 newDescOffset, uint256 newHead, uint256 newBase) = _descend(
            desc, location.descOffset, location.head, location.base, fieldIndex, callData
        );

        (uint8 code, bool isDynamic, uint32 staticSize,) = Descriptor.inspect(desc, newDescOffset);

        return Location({
            head: newHead,
            base: newBase,
            descOffset: newDescOffset,
            typeInfo: Descriptor.TypeInfo({ code: code, isDynamic: isDynamic, staticSize: staticSize })
        });
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Loads 32 bytes from calldata with bounds check.
    function _calldataload(bytes calldata data, uint256 offset) private pure returns (bytes32 word) {
        require(offset + 32 <= data.length, CalldataOutOfBounds());
        word = LibBytes.loadCalldata(data, offset);
    }

    /// @dev Resolves dynamic array header: computes array base and reads length.
    function _dynamicArrayBaseAndLength(
        bytes calldata callData,
        uint256 base,
        uint256 head
    )
        private
        pure
        returns (uint256 arrayBase, uint256 length)
    {
        arrayBase = base + uint256(_calldataload(callData, head));
        length = uint256(_calldataload(callData, arrayBase));
    }

    /// @dev Extracts element metadata for arrays. Validates index for static arrays.
    function _descendArrayMeta(
        bytes memory desc,
        uint256 descOffset,
        uint8 code,
        uint256 elementIndex
    )
        private
        pure
        returns (
            uint256 elementDescOffset,
            uint8 elementTypeCode,
            bool elementIsDynamic,
            uint32 elementStaticSize,
            uint256 fixedLength
        )
    {
        elementDescOffset = descOffset + DF.ARRAY_HEADER_SIZE;
        (elementTypeCode, elementIsDynamic, elementStaticSize,) = Descriptor.inspect(desc, elementDescOffset);

        if (code == TypeCode.STATIC_ARRAY) {
            fixedLength = Descriptor.staticArrayLength(desc, descOffset);
            require(elementIndex < fixedLength, ArrayIndexOutOfBounds(elementIndex, fixedLength));
        }
    }

    /// @dev Descends one path step, updating descriptor offset, head, and base.
    function _descend(
        bytes memory desc,
        uint256 descOffset,
        uint256 head,
        uint256 base,
        uint256 childIndex,
        bytes calldata callData
    )
        private
        pure
        returns (uint256 newDescOffset, uint256 newHead, uint256 newBase)
    {
        (uint8 code, bool isDynamic,,) = Descriptor.inspect(desc, descOffset);

        if (code == TypeCode.TUPLE) {
            uint256 fieldCount = Descriptor.tupleFieldCount(desc, descOffset);
            require(childIndex < fieldCount, TupleFieldOutOfBounds(childIndex, fieldCount));

            // tupleBase anchors offset resolution for dynamic children; cursor tracks the
            // head position and advances past preceding fields to reach the target field.
            uint256 tupleBase;
            uint256 cursor;
            if (isDynamic) {
                tupleBase = base + uint256(_calldataload(callData, head));
                cursor = tupleBase;
            } else {
                tupleBase = base;
                cursor = head;
            }

            uint256 fieldDescOffset = descOffset + DF.TUPLE_HEADER_SIZE;
            for (uint256 i; i < childIndex; ++i) {
                uint8 fieldCode = uint8(desc[fieldDescOffset]);
                uint256 fieldNodeLength;
                uint256 headContrib;

                if (TypeRule.isElementary(fieldCode)) {
                    headContrib = 32;
                    fieldNodeLength = 1;
                } else {
                    (uint16 fieldStaticWords, uint16 nodeLength) = Descriptor.decodeMeta(desc, fieldDescOffset + 1);
                    fieldNodeLength = nodeLength;
                    // Dynamic fields (staticWords == 0) still occupy one 32-byte head slot for their offset pointer.
                    uint256 words = fieldStaticWords == 0 ? 1 : uint256(fieldStaticWords);
                    headContrib = words << 5;
                }

                unchecked {
                    cursor += headContrib;
                    fieldDescOffset += fieldNodeLength;
                }
            }

            return (fieldDescOffset, cursor, tupleBase);
        }

        // Dynamic array: follow offset to array base, read length from calldata.
        // forgefmt: disable-next-item
        if (code == TypeCode.DYNAMIC_ARRAY) {
            (uint256 elementDescOffset,, bool elementIsDynamic, uint32 elementStaticSize,) = _descendArrayMeta(
                desc, descOffset, code, childIndex
            );

            (uint256 arrayBase, uint256 length) = _dynamicArrayBaseAndLength(callData, base, head);
            require(childIndex < length, ArrayIndexOutOfBounds(childIndex, length));

            unchecked {
                uint256 headsBase = arrayBase + 32;
                uint256 elementHead = elementIsDynamic
                    ? (headsBase + (childIndex << 5))
                    : (headsBase + childIndex * uint256(elementStaticSize));

                // For dynamic elements, per-element offsets are relative to the heads section.
                // (arrayBase + 32), not arrayBase. For static elements, no offset indirection is used.
                return (elementDescOffset, elementHead, elementIsDynamic ? headsBase : arrayBase);
            }
        }

        // Static array: dynamic elements use offset, static elements are inline.
        // forgefmt: disable-next-item
        if (code == TypeCode.STATIC_ARRAY) {
            (uint256 elementDescOffset,, bool elementIsDynamic, uint32 elementStaticSize,) = _descendArrayMeta(
                desc, descOffset, code, childIndex
            );

            if (elementIsDynamic) {
                uint256 arrayBase = base + uint256(_calldataload(callData, head));
                unchecked {
                    return (elementDescOffset, arrayBase + (childIndex << 5), arrayBase);
                }
            } else {
                unchecked {
                    return (elementDescOffset, head + childIndex * uint256(elementStaticSize), base);
                }
            }
        }

        revert NotComposite(code);
    }
}

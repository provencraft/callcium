// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title DescriptorFormat
/// @notice Layout constants for the descriptor binary format.
library DescriptorFormat {
    /*/////////////////////////////////////////////////////////////////////////
                                     VERSION
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Current descriptor format version.
    uint8 internal constant VERSION = 0x01;

    /*/////////////////////////////////////////////////////////////////////////
                               DESCRIPTOR HEADER
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Size of the `version` field in bytes.
    uint256 internal constant HEADER_VERSION_SIZE = 1;

    /// @dev Size of the `paramCount` field in bytes.
    uint256 internal constant HEADER_PARAMCOUNT_SIZE = 1;

    /// @dev Byte offset of `version` within the descriptor header.
    uint256 internal constant HEADER_VERSION_OFFSET = 0;

    /// @dev Byte offset of `paramCount` within the descriptor header.
    uint256 internal constant HEADER_PARAMCOUNT_OFFSET = HEADER_VERSION_OFFSET + HEADER_VERSION_SIZE;

    /// @dev Descriptor header size: version (1) + paramCount (1).
    uint256 internal constant HEADER_SIZE = HEADER_PARAMCOUNT_OFFSET + HEADER_PARAMCOUNT_SIZE;

    /*/////////////////////////////////////////////////////////////////////////
                                COMPOSITE METADATA
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Size of the 1-byte type code prefix that precedes composite meta/elementary types.
    uint256 internal constant TYPECODE_SIZE = 1;

    /// @dev Composite metadata size: 3 bytes (staticWords:12, nodeLength:12).
    uint256 internal constant COMPOSITE_META_SIZE = 3;

    /// @dev Size of the tuple `fieldCount` field in bytes (big-endian uint16).
    uint256 internal constant TUPLE_FIELDCOUNT_SIZE = 2;

    /// @dev Bit shift for staticWords within the 24-bit composite meta.
    uint256 internal constant META_STATIC_WORDS_SHIFT = 12;

    /// @dev Mask for nodeLength within the 24-bit composite meta.
    uint256 internal constant META_NODE_LENGTH_MASK = 0x0FFF;

    /*/////////////////////////////////////////////////////////////////////////
                                COMPOSITE HEADERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Array header size: typeCode (1) + meta (3).
    uint256 internal constant ARRAY_HEADER_SIZE = TYPECODE_SIZE + COMPOSITE_META_SIZE;

    /// @dev Tuple header size: typeCode (1) + meta (3) + fieldCount (2, big-endian).
    uint256 internal constant TUPLE_HEADER_SIZE = TYPECODE_SIZE + COMPOSITE_META_SIZE + TUPLE_FIELDCOUNT_SIZE;

    /// @dev Offset from the start of a tuple node where the 2-byte `fieldCount` is stored.
    uint256 internal constant TUPLE_FIELDCOUNT_OFFSET = TYPECODE_SIZE + COMPOSITE_META_SIZE;

    /// @dev Static array length suffix size (big-endian uint16).
    uint256 internal constant ARRAY_LENGTH_SIZE = 2;

    /*/////////////////////////////////////////////////////////////////////////
                                     LIMITS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Upper bound of the `staticWords` meta field (12 bits).
    /// Represents the maximum static footprint in 32-byte words (~128KB).
    uint256 internal constant MAX_STATIC_WORDS = 4095;

    /// @dev Upper bound of the `nodeLength` meta field (12 bits).
    /// Represents the total encoded size of a node in bytes.
    uint256 internal constant MAX_NODE_LENGTH = 4095;

    /// @dev Early cap on tuple field count.
    /// The node length check still applies afterward.
    uint256 internal constant MAX_TUPLE_FIELDS = MAX_NODE_LENGTH - TUPLE_HEADER_SIZE;

    /// @dev Cap for the static array length suffix.
    /// The suffix is `uint16` but intentionally restricted to 12 bits (4095) for uniformity with other limits and to
    /// bound arrays of dynamic elements.
    uint256 internal constant MAX_STATIC_ARRAY_LENGTH = 4095;
}

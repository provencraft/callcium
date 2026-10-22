// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title PolicyFormat
/// @notice Layout constants for the policy binary format.
library PolicyFormat {
    /*/////////////////////////////////////////////////////////////////////////
                                 POLICY HEADER
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Byte offset of the composite header byte within the policy.
    uint256 internal constant POLICY_HEADER_OFFSET = 0;

    /// @dev Size of the header field in bytes.
    uint256 internal constant POLICY_HEADER_SIZE = 1;

    /// @dev Policy format major version (header bits 7-5).
    uint8 internal constant MAJOR = 3;

    /// @dev Lowest policy format minor version, the minor of a blob that uses no extension (header bits 4-1).
    uint8 internal constant MINOR = 0;

    /// @dev Highest minor version this release implements.
    uint8 internal constant SUPPORTED_MINOR = MINOR;

    /// @dev Bit shift of the major version within the header byte.
    uint8 internal constant MAJOR_SHIFT = 5;

    /// @dev Bit shift of the minor version within the header byte.
    uint8 internal constant MINOR_SHIFT = 1;

    /// @dev Mask to extract the minor version after its shift.
    uint8 internal constant MINOR_MASK = 0x0F;

    /// @dev Header flag: policy targets raw ABI calldata without a selector.
    uint8 internal constant FLAG_NO_SELECTOR = 0x01;

    /// @dev Byte offset of `selector` within the policy header.
    uint256 internal constant POLICY_SELECTOR_OFFSET = POLICY_HEADER_OFFSET + POLICY_HEADER_SIZE;

    /// @dev Size of the `selector` field in bytes.
    uint256 internal constant POLICY_SELECTOR_SIZE = 4;

    /// @dev Byte offset of `descLength` within the policy header.
    uint256 internal constant POLICY_DESC_LENGTH_OFFSET = POLICY_SELECTOR_OFFSET + POLICY_SELECTOR_SIZE;

    /// @dev Size of the `descLength` field in bytes.
    uint256 internal constant POLICY_DESC_LENGTH_SIZE = 2;

    /// @dev Byte offset of the embedded descriptor within the policy.
    uint256 internal constant POLICY_DESC_OFFSET = POLICY_DESC_LENGTH_OFFSET + POLICY_DESC_LENGTH_SIZE;

    /// @dev Fixed prefix size before the descriptor: header(1) + selector(4) + descLength(2).
    uint256 internal constant POLICY_HEADER_PREFIX = POLICY_DESC_OFFSET;

    /// @dev Size of the `groupCount` field in bytes.
    uint256 internal constant POLICY_GROUP_COUNT_SIZE = 1;

    /*/////////////////////////////////////////////////////////////////////////
                                  GROUP HEADER
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Byte offset of `ruleCount` within the group header.
    uint256 internal constant GROUP_RULECOUNT_OFFSET = 0;

    /// @dev Size of the `ruleCount` field in bytes.
    uint256 internal constant GROUP_RULECOUNT_SIZE = 2;

    /// @dev Byte offset of `groupSize` within the group header.
    uint256 internal constant GROUP_SIZE_OFFSET = GROUP_RULECOUNT_SIZE;

    /// @dev Size of the `groupSize` field in bytes.
    uint256 internal constant GROUP_SIZE_SIZE = 4;

    /// @dev Group header size: ruleCount(2) + groupSize(4).
    uint256 internal constant GROUP_HEADER_SIZE = GROUP_RULECOUNT_SIZE + GROUP_SIZE_SIZE;

    /*/////////////////////////////////////////////////////////////////////////
                                     SCOPES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Context scope (execution environment properties).
    uint8 internal constant SCOPE_CONTEXT = 0x00;

    /// @dev Calldata scope (argument path traversal).
    uint8 internal constant SCOPE_CALLDATA = 0x01;

    /// @dev Loop scope (a body of rules over each element of an array).
    uint8 internal constant SCOPE_LOOP = 0x02;

    /*/////////////////////////////////////////////////////////////////////////
                                  QUANTIFIERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Universal quantifier: the body holds for every element.
    uint8 internal constant QUANTIFIER_ALL = 0x01;

    /// @dev Existential quantifier: the body holds for some element.
    uint8 internal constant QUANTIFIER_ANY = 0x02;

    /*/////////////////////////////////////////////////////////////////////////
                                   RULE FIELDS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Size of the `ruleSize` field in bytes.
    uint256 internal constant RULE_SIZE_SIZE = 2;

    /// @dev Byte offset of `scope` within a rule.
    uint256 internal constant RULE_SCOPE_OFFSET = RULE_SIZE_SIZE;

    /// @dev Size of the `scope` field in bytes.
    uint256 internal constant RULE_SCOPE_SIZE = 1;

    /// @dev Byte offset of `depth` within a rule.
    uint256 internal constant RULE_DEPTH_OFFSET = RULE_SCOPE_OFFSET + RULE_SCOPE_SIZE;

    /// @dev Size of the `depth` field in bytes.
    uint256 internal constant RULE_DEPTH_SIZE = 1;

    /// @dev Byte offset of the path array within a rule.
    uint256 internal constant RULE_PATH_OFFSET = RULE_DEPTH_OFFSET + RULE_DEPTH_SIZE;

    /// @dev Size of each path step in bytes.
    uint256 internal constant PATH_STEP_SIZE = 2;

    /// @dev Size of a context property ID in bytes.
    uint256 internal constant PROPERTY_ID_SIZE = 2;

    /// @dev Byte offset of `quantifier` within a loop rule.
    uint256 internal constant RULE_QUANTIFIER_OFFSET = RULE_SCOPE_OFFSET + RULE_SCOPE_SIZE;

    /// @dev Size of the `quantifier` field in bytes.
    uint256 internal constant RULE_QUANTIFIER_SIZE = 1;

    /// @dev Byte offset of `depth` within a loop rule.
    uint256 internal constant LOOP_DEPTH_OFFSET = RULE_QUANTIFIER_OFFSET + RULE_QUANTIFIER_SIZE;

    /// @dev Size of the `opCode` field in bytes.
    uint256 internal constant RULE_OPCODE_SIZE = 1;

    /// @dev Size of the `dataLength` field in bytes.
    uint256 internal constant RULE_DATALENGTH_SIZE = 2;

    /*/////////////////////////////////////////////////////////////////////////
                                  COMPILED HINT
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Size of the hint header field in bytes.
    uint256 internal constant HINT_HEADER_SIZE = 1;

    /// @dev Size of a hop entry: delta(4) + index(2) + meta(2).
    uint256 internal constant HINT_HOP_SIZE = 8;

    /// @dev Byte offset of `index` within a hop entry.
    uint256 internal constant HINT_HOP_INDEX_OFFSET = 4;

    /// @dev Byte offset of `meta` within a hop entry.
    uint256 internal constant HINT_HOP_META_OFFSET = 6;

    /// @dev Size of the quantifier frame fields following its hops: arrayDelta(4) + count(2) + meta(2).
    uint256 internal constant HINT_FRAME_PREFIX_SIZE = 8;

    /// @dev Byte offset of `count` within a quantifier frame.
    uint256 internal constant HINT_FRAME_COUNT_OFFSET = 4;

    /// @dev Byte offset of `meta` within a quantifier frame.
    uint256 internal constant HINT_FRAME_META_OFFSET = 6;

    /// @dev Size of the hint target block: targetDelta(4) + targetMeta(2) + typeCode(1).
    uint256 internal constant HINT_TARGET_SIZE = 7;

    /// @dev Byte offset of `targetMeta` within a hint target block.
    uint256 internal constant HINT_TARGET_META_OFFSET = 4;

    /// @dev Byte offset of `typeCode` within a hint target block.
    uint256 internal constant HINT_TARGET_TYPECODE_OFFSET = 6;

    /// @dev Span of the hint target block together with the operator fields that follow it.
    uint256 internal constant HINT_TARGET_OPERATOR_SIZE = HINT_TARGET_SIZE + RULE_OPCODE_SIZE + RULE_DATALENGTH_SIZE;

    /// @dev Mask for the hop count within a hint header byte.
    uint8 internal constant HINT_HOP_COUNT_MASK = 0x3F;

    /// @dev Mask for the reserved bits of a hint header byte.
    uint8 internal constant HINT_HEADER_RESERVED_MASK = 0xC0;

    /// @dev Hop index value marking a crossing that selects no element.
    uint16 internal constant HINT_NO_INDEX = 0xFFFF;

    /// @dev First path step and hop index value the format reserves.
    uint16 internal constant PATH_MARKER_BASE = 0xFF00;

    /// @dev Meta bit marking a dynamic element type.
    uint16 internal constant HINT_META_ELEM_DYNAMIC = 0x8000;

    /// @dev Meta bit marking a dynamic array node.
    uint16 internal constant HINT_META_DYNAMIC_ARRAY = 0x4000;

    /// @dev Mask for the element head size in words within a meta word.
    uint16 internal constant HINT_META_STRIDE_MASK = 0x0FFF;

    /// @dev Mask for the reserved bits of a meta word.
    uint16 internal constant HINT_META_RESERVED_MASK = 0x3000;

    /*/////////////////////////////////////////////////////////////////////////
                             CONTEXT PROPERTY IDS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev msg.sender (address).
    uint16 internal constant CTX_MSG_SENDER = 0x0000;

    /// @dev msg.value (uint256).
    uint16 internal constant CTX_MSG_VALUE = 0x0001;

    /// @dev block.timestamp (uint256).
    uint16 internal constant CTX_BLOCK_TIMESTAMP = 0x0002;

    /// @dev block.number (uint256).
    uint16 internal constant CTX_BLOCK_NUMBER = 0x0003;

    /// @dev block.chainid (uint256).
    uint16 internal constant CTX_CHAIN_ID = 0x0004;

    /// @dev tx.origin (address).
    uint16 internal constant CTX_TX_ORIGIN = 0x0005;

    /// @dev block.basefee (uint256).
    uint16 internal constant CTX_BASE_FEE = 0x0006;

    /// @dev tx.gasprice (uint256).
    uint16 internal constant CTX_GAS_PRICE = 0x0007;

    /// @dev Highest assigned context property ID.
    uint16 internal constant CTX_MAX = CTX_GAS_PRICE;

    /*/////////////////////////////////////////////////////////////////////////
                                NORMATIVE LIMITS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Maximum path depth of a well-formed policy, counted across the enclosing loop (PWF-14).
    uint8 internal constant MAX_PATH_DEPTH = 32;

    /// @dev Maximum array length for quantifier iteration (PV-7).
    uint256 internal constant MAX_QUANTIFIED_ARRAY_LENGTH = 256;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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

    /// @dev Current policy format version (lower nibble of header byte).
    uint8 internal constant POLICY_VERSION = 0x01;

    /// @dev Mask to extract the version from the header byte.
    uint8 internal constant POLICY_VERSION_MASK = 0x0F;

    /// @dev Header flag: policy targets raw ABI calldata without a 4-byte selector.
    uint8 internal constant FLAG_NO_SELECTOR = 0x10;

    /// @dev Mask for reserved header bits (must be zero).
    uint8 internal constant POLICY_RESERVED_MASK = 0xE0;

    /// @dev Byte offset of `selector` within the policy header.
    uint256 internal constant POLICY_SELECTOR_OFFSET = POLICY_HEADER_OFFSET + POLICY_HEADER_SIZE;

    /// @dev Size of the `selector` field in bytes.
    uint256 internal constant POLICY_SELECTOR_SIZE = 4;

    /// @dev Byte offset of `descLength` within the policy header.
    uint256 internal constant POLICY_DESC_LENGTH_OFFSET = POLICY_SELECTOR_OFFSET + POLICY_SELECTOR_SIZE;

    /// @dev Size of the `descLength` field in bytes.
    uint256 internal constant POLICY_DESC_LENGTH_SIZE = 2;

    /// @dev Byte offset of the embedded descriptor within the policy header.
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

    /// @dev Context scope (msg.sender, msg.value, block.*, chain.id).
    uint8 internal constant SCOPE_CONTEXT = 0x00;

    /// @dev Calldata scope (argument path traversal).
    uint8 internal constant SCOPE_CALLDATA = 0x01;

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

    /// @dev Size of the `opCode` field in bytes.
    uint256 internal constant RULE_OPCODE_SIZE = 1;

    /// @dev Size of the `dataLength` field in bytes.
    uint256 internal constant RULE_DATALENGTH_SIZE = 2;

    /// @dev Fixed byte overhead of a rule header, excluding `pathLength` and `dataLength`.
    /// Breakdown: size(2) + scope(1) + depth(1) + opCode(1) + dataLength(2) = 7.
    // forgefmt: disable-next-item
    uint256 internal constant RULE_FIXED_OVERHEAD =
        RULE_SIZE_SIZE + RULE_SCOPE_SIZE + RULE_DEPTH_SIZE + RULE_OPCODE_SIZE + RULE_DATALENGTH_SIZE;

    /// @dev Minimum rule size: fixedOverhead(7) + path(2 min).
    uint256 internal constant RULE_MIN_SIZE = RULE_FIXED_OVERHEAD + PATH_STEP_SIZE;

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
}

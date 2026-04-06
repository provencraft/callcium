// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Be16 } from "./Be16.sol";
import { Descriptor } from "./Descriptor.sol";
import { OpCode } from "./OpCode.sol";
import { OpRule } from "./OpRule.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { LibBytes } from "solady/utils/LibBytes.sol";

/// @title Policy
/// @notice Format-aware views for policy blobs.
library Policy {
    /*/////////////////////////////////////////////////////////////////////////
                                     ERRORS
    ////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the policy blob is too short to contain a valid header.
    error MalformedHeader();

    /// @notice Thrown when the policy format version is not supported.
    /// @param version The unsupported version byte.
    error UnsupportedVersion(uint8 version);

    /// @notice Thrown when the policy declares zero groups.
    error EmptyPolicy();

    /// @notice Thrown when parsing reaches end of policy blob unexpectedly.
    error UnexpectedEnd();

    /// @notice Thrown when a group index exceeds the declared count.
    /// @param index The requested group index.
    /// @param count The declared group count.
    error GroupIndexOutOfBounds(uint256 index, uint256 count);

    /// @notice Thrown when a group extends beyond policy boundaries.
    /// @param groupOffset The offset of the malformed group.
    error GroupOverflow(uint256 groupOffset);

    /// @notice Thrown when a rule index exceeds the declared count in a group.
    /// @param groupOffset The offset of the group containing the rule.
    /// @param index The requested rule index.
    /// @param count The declared rule count for the group.
    error RuleIndexOutOfBounds(uint256 groupOffset, uint256 index, uint256 count);

    /// @notice Thrown when a rule extends beyond group boundaries.
    /// @param ruleOffset The offset of the malformed rule.
    error RuleOverflow(uint256 ruleOffset);

    /// @notice Thrown when a rule size is below the minimum.
    /// @param ruleOffset The offset of the malformed rule.
    /// @param size The declared size.
    error RuleTooSmall(uint256 ruleOffset, uint256 size);

    /// @notice Thrown when a path step index exceeds the declared depth.
    /// @param ruleOffset The offset of the rule.
    /// @param index The requested path step index.
    /// @param depth The declared path depth.
    error PathStepOutOfBounds(uint256 ruleOffset, uint256 index, uint256 depth);

    /// @notice Thrown when a rule field access exceeds the rule boundary.
    /// @param ruleOffset The offset of the rule.
    error RuleFieldOutOfBounds(uint256 ruleOffset);

    /// @notice Thrown when declared rule size does not match the field layout.
    /// @param ruleOffset The offset of the inconsistent rule.
    error RuleSizeMismatch(uint256 ruleOffset);

    /// @notice Thrown when a rule has an empty path.
    /// @param ruleOffset The offset of the rule with depth zero.
    error EmptyPath(uint256 ruleOffset);

    /// @notice Thrown when a rule has an unknown operator code or mismatched payload size.
    /// @param ruleOffset The offset of the rule with the invalid operator.
    error UnknownOperator(uint256 ruleOffset);

    /// @notice Thrown when a group declares zero rules.
    /// @param groupOffset The offset of the empty group.
    error EmptyGroup(uint256 groupOffset);

    /// @notice Thrown when the declared group size is too small for its rule count.
    /// @param groupOffset The offset of the undersized group.
    error GroupTooSmall(uint256 groupOffset);

    /// @notice Thrown when rules do not exactly fill the declared group size.
    /// @param groupOffset The offset of the group with trailing bytes.
    error GroupSizeMismatch(uint256 groupOffset);

    /// @notice Thrown when a rule scope byte is not a defined value.
    /// @param ruleOffset The offset of the rule with the invalid scope.
    error InvalidScope(uint256 ruleOffset);

    /// @notice Thrown when a context-scope rule does not have exactly one path step.
    /// @param ruleOffset The offset of the rule with the invalid path depth.
    error InvalidContextPath(uint256 ruleOffset);

    /// @notice Thrown when the selector is accessed on a selectorless policy.
    error OmittedSelector();

    /*/////////////////////////////////////////////////////////////////////////
                                    FUNCTIONS
    ////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the policy format version from the header.
    /// @param self The policy blob.
    /// @return The version nibble (bits 3-0 of the header byte).
    function version(bytes memory self) internal pure returns (uint8) {
        require(self.length >= PF.POLICY_HEADER_PREFIX, MalformedHeader());
        return uint8(self[PF.POLICY_HEADER_OFFSET]) & PF.POLICY_VERSION_MASK;
    }

    /// @notice Returns whether the policy targets selectorless calldata.
    /// @param self The policy blob.
    /// @return True if the policy has the selectorless flag set.
    function isSelectorless(bytes memory self) internal pure returns (bool) {
        require(self.length >= PF.POLICY_HEADER_PREFIX, MalformedHeader());
        return (uint8(self[PF.POLICY_HEADER_OFFSET]) & PF.FLAG_NO_SELECTOR) != 0;
    }

    /// @notice Returns the function selector bound by the policy.
    /// @param self The policy blob.
    /// @return The 4-byte function selector.
    function selector(bytes memory self) internal pure returns (bytes4) {
        require(!isSelectorless(self), OmittedSelector());
        return bytes4(LibBytes.load(self, PF.POLICY_SELECTOR_OFFSET));
    }

    /// @notice Returns the descriptor length from the header.
    /// @param self The policy blob.
    /// @return The descriptor length in bytes.
    function descriptorLength(bytes memory self) internal pure returns (uint16) {
        require(self.length >= PF.POLICY_HEADER_PREFIX, MalformedHeader());
        return Be16.readUnchecked(self, PF.POLICY_DESC_LENGTH_OFFSET);
    }

    /// @notice Returns the embedded descriptor from the policy.
    /// @param self The policy blob.
    /// @return The descriptor bytes.
    function descriptor(bytes memory self) internal pure returns (bytes memory) {
        uint16 length = descriptorLength(self);
        uint256 fullHeaderSize = PF.POLICY_HEADER_PREFIX + length + PF.POLICY_GROUP_COUNT_SIZE;
        require(self.length >= fullHeaderSize, MalformedHeader());
        return LibBytes.slice(self, PF.POLICY_DESC_OFFSET, PF.POLICY_DESC_OFFSET + length);
    }

    /// @notice Returns the number of OR-groups in the policy.
    /// @param self The policy blob.
    /// @return The number of groups.
    function groupCount(bytes memory self) internal pure returns (uint8) {
        uint16 length = descriptorLength(self);
        uint256 groupCountOffset = PF.POLICY_HEADER_PREFIX + length;
        require(self.length >= groupCountOffset + PF.POLICY_GROUP_COUNT_SIZE, MalformedHeader());
        return uint8(self[groupCountOffset]);
    }

    /// @notice Validates the policy blob structure and version.
    /// @param self The policy blob to validate.
    function validate(bytes memory self) internal pure {
        require(self.length >= PF.POLICY_HEADER_PREFIX, MalformedHeader());
        uint8 header = uint8(self[PF.POLICY_HEADER_OFFSET]);
        uint8 formatVersion = header & PF.POLICY_VERSION_MASK;
        require(formatVersion == PF.POLICY_VERSION, UnsupportedVersion(formatVersion));
        require((header & PF.POLICY_RESERVED_MASK) == 0, MalformedHeader());

        // Selectorless policies must have a zeroed selector slot.
        if ((header & PF.FLAG_NO_SELECTOR) != 0) {
            require(bytes4(LibBytes.load(self, PF.POLICY_SELECTOR_OFFSET)) == bytes4(0), MalformedHeader());
        }

        // Minimum descriptor is 2 bytes (version + paramCount).
        uint16 descLen = descriptorLength(self);
        require(descLen >= 2, MalformedHeader());

        // Check descriptor correctness.
        bytes memory desc = descriptor(self);
        Descriptor.validate(desc);

        uint8 totalGroups = groupCount(self);
        require(totalGroups > 0, EmptyPolicy());
        uint256 offset = PF.POLICY_HEADER_PREFIX + desc.length + PF.POLICY_GROUP_COUNT_SIZE;

        for (uint256 groupIndex; groupIndex < totalGroups; ++groupIndex) {
            require(offset + PF.GROUP_HEADER_SIZE <= self.length, UnexpectedEnd());

            uint32 rulesRegionSize = groupSize(self, offset);
            uint256 groupEnd = offset + PF.GROUP_HEADER_SIZE + rulesRegionSize;
            require(groupEnd <= self.length, GroupOverflow(offset));

            uint16 totalRules = ruleCount(self, offset);
            require(totalRules > 0, EmptyGroup(offset));
            require(rulesRegionSize >= uint32(totalRules) * PF.RULE_MIN_SIZE, GroupTooSmall(offset));
            uint256 ruleOffset = offset + PF.GROUP_HEADER_SIZE;

            for (uint256 ruleIndex; ruleIndex < totalRules; ++ruleIndex) {
                uint16 ruleTotalSize = ruleSize(self, ruleOffset);

                // Scope must be a defined value.
                uint8 ruleScope = uint8(self[ruleOffset + PF.RULE_SCOPE_OFFSET]);
                require(ruleScope == PF.SCOPE_CONTEXT || ruleScope == PF.SCOPE_CALLDATA, InvalidScope(ruleOffset));

                // Framing consistency: declared size must match field layout.
                uint256 depth = uint8(self[ruleOffset + PF.RULE_DEPTH_OFFSET]);
                // forgefmt: disable-next-item
                uint256 dataLengthOffset = (
                    ruleOffset + PF.RULE_PATH_OFFSET + depth * PF.PATH_STEP_SIZE + PF.RULE_OPCODE_SIZE
                );
                require(
                    dataLengthOffset + PF.RULE_DATALENGTH_SIZE <= ruleOffset + ruleTotalSize,
                    RuleSizeMismatch(ruleOffset)
                );
                uint16 dataLength = Be16.readUnchecked(self, dataLengthOffset);
                require(
                    ruleTotalSize == PF.RULE_FIXED_OVERHEAD + depth * PF.PATH_STEP_SIZE + dataLength,
                    RuleSizeMismatch(ruleOffset)
                );

                // Operator must be a defined opcode with valid payload size.
                uint8 opBase = uint8(self[dataLengthOffset - PF.RULE_OPCODE_SIZE]) & ~OpCode.NOT;
                require(opBase != 0 && OpRule.isValidPayloadSize(opBase, dataLength), UnknownOperator(ruleOffset));

                // Path must be non-empty. Context-scope rules must have exactly one path step.
                require(depth >= 1, EmptyPath(ruleOffset));
                if (ruleScope == PF.SCOPE_CONTEXT) require(depth == 1, InvalidContextPath(ruleOffset));

                ruleOffset += ruleTotalSize;
                require(ruleOffset <= groupEnd, RuleOverflow(ruleOffset - ruleTotalSize));
            }

            require(ruleOffset == groupEnd, GroupSizeMismatch(offset));

            offset = groupEnd;
        }

        require(offset == self.length, UnexpectedEnd());
    }

    /// @notice Returns the byte offset of the `index`-th group in `self`.
    /// @param self The policy blob.
    /// @param index Group index (0-based).
    /// @return groupOffset Byte offset of the group header.
    function groupAt(bytes memory self, uint256 index) internal pure returns (uint256 groupOffset) {
        uint256 count = groupCount(self);
        require(index < count, GroupIndexOutOfBounds(index, count));
        uint16 descLength = descriptorLength(self);
        groupOffset = PF.POLICY_HEADER_PREFIX + descLength + PF.POLICY_GROUP_COUNT_SIZE;
        for (uint256 i; i < index; ++i) {
            uint32 size = groupSize(self, groupOffset);
            groupOffset += PF.GROUP_HEADER_SIZE + size;
            require(groupOffset <= self.length, GroupOverflow(groupOffset - PF.GROUP_HEADER_SIZE - size));
        }
    }

    /// @notice Returns the declared number of rules in the group at `groupOffset`.
    /// @param self The policy blob.
    /// @param groupOffset Offset of a group header within `self`.
    /// @return The number of rules in the group.
    function ruleCount(bytes memory self, uint256 groupOffset) internal pure returns (uint16) {
        require(groupOffset + PF.GROUP_HEADER_SIZE <= self.length, UnexpectedEnd());
        return Be16.readUnchecked(self, groupOffset + PF.GROUP_RULECOUNT_OFFSET);
    }

    /// @notice Returns the payload size in bytes for the group at `groupOffset`.
    /// @dev Payload starts after the group header and spans rules region.
    /// @param self The policy blob.
    /// @param groupOffset Offset of a group header within `self`.
    /// @return size The payload size in bytes.
    function groupSize(bytes memory self, uint256 groupOffset) internal pure returns (uint32 size) {
        require(groupOffset + PF.GROUP_HEADER_SIZE <= self.length, UnexpectedEnd());
        uint256 offset = groupOffset + PF.GROUP_SIZE_OFFSET;
        uint256 shift = 256 - 8 * PF.GROUP_SIZE_SIZE;
        assembly {
            let p := add(add(self, 32), offset)
            size := shr(shift, mload(p))
        }
        require(groupOffset + PF.GROUP_HEADER_SIZE + size <= self.length, GroupOverflow(groupOffset));
    }

    /// @notice Returns the byte offset of the `index`-th rule within the group at `groupOffset`.
    /// @param self The policy blob.
    /// @param groupOffset Offset of a group header within `self`.
    /// @param index Rule index (0-based).
    /// @return ruleOffset Byte offset of the rule header.
    function ruleAt(bytes memory self, uint256 groupOffset, uint256 index) internal pure returns (uint256 ruleOffset) {
        uint32 rulesRegionSize = groupSize(self, groupOffset);
        uint256 start = groupOffset + PF.GROUP_HEADER_SIZE;
        uint256 end = start + rulesRegionSize;
        uint256 count = ruleCount(self, groupOffset);
        require(index < count, RuleIndexOutOfBounds(groupOffset, index, count));

        ruleOffset = start;
        for (uint256 i; i < index; ++i) {
            uint16 ruleTotalSize = ruleSize(self, ruleOffset);
            ruleOffset += ruleTotalSize;
            require(ruleOffset <= end, RuleOverflow(ruleOffset - ruleTotalSize));
        }
    }

    /// @notice Returns the size in bytes of the rule at `ruleOffset` (self-inclusive).
    /// @param self The policy blob.
    /// @param ruleOffset Offset of a rule header within `self`.
    /// @return size The rule size in bytes.
    function ruleSize(bytes memory self, uint256 ruleOffset) internal pure returns (uint16 size) {
        require(ruleOffset + PF.RULE_SIZE_SIZE <= self.length, UnexpectedEnd());
        size = Be16.readUnchecked(self, ruleOffset);
        require(size >= PF.RULE_MIN_SIZE, RuleTooSmall(ruleOffset, size));
        require(ruleOffset + size <= self.length, RuleOverflow(ruleOffset));
    }

    /// @notice Returns the rule scope (context or calldata) for the rule at `ruleOffset`.
    /// @param self The policy blob.
    /// @param ruleOffset Offset of a rule header within `self`.
    /// @return The scope byte.
    function scope(bytes memory self, uint256 ruleOffset) internal pure returns (uint8) {
        uint256 offset = ruleOffset + PF.RULE_SCOPE_OFFSET;
        require(offset + PF.RULE_SCOPE_SIZE <= self.length, RuleFieldOutOfBounds(ruleOffset));
        return uint8(self[offset]);
    }

    /// @notice Returns the path depth for the rule at `ruleOffset`.
    /// @param self The policy blob.
    /// @param ruleOffset Offset of a rule header within `self`.
    /// @return The path depth.
    function pathDepth(bytes memory self, uint256 ruleOffset) internal pure returns (uint8) {
        uint256 offset = ruleOffset + PF.RULE_DEPTH_OFFSET;
        require(offset + PF.RULE_DEPTH_SIZE <= self.length, RuleFieldOutOfBounds(ruleOffset));
        return uint8(self[offset]);
    }

    /// @notice Returns the path step (big-endian uint16) at `stepIndex` for the rule at `ruleOffset`.
    /// @param self The policy blob.
    /// @param ruleOffset Offset of a rule header within `self`.
    /// @param stepIndex Path step index (0-based).
    /// @return step The uint16 path step value.
    function pathStep(bytes memory self, uint256 ruleOffset, uint256 stepIndex) internal pure returns (uint16 step) {
        uint8 depth = pathDepth(self, ruleOffset);
        require(stepIndex < depth, PathStepOutOfBounds(ruleOffset, stepIndex, depth));
        uint256 start = ruleOffset + PF.RULE_PATH_OFFSET;
        uint256 offset = start + (stepIndex * PF.PATH_STEP_SIZE);

        uint16 size = Be16.readUnchecked(self, ruleOffset);
        require(offset + PF.PATH_STEP_SIZE <= ruleOffset + size, RuleFieldOutOfBounds(ruleOffset));
        step = Be16.readUnchecked(self, offset);
    }

    /// @notice Returns the operator code for the rule at `ruleOffset`.
    /// @param self The policy blob.
    /// @param ruleOffset Offset of a rule header within `self`.
    /// @return The operator code byte.
    function opCode(bytes memory self, uint256 ruleOffset) internal pure returns (uint8) {
        uint8 depth = pathDepth(self, ruleOffset);
        uint256 offset = ruleOffset + PF.RULE_PATH_OFFSET + (uint256(depth) * PF.PATH_STEP_SIZE);

        uint16 size = Be16.readUnchecked(self, ruleOffset);
        require(offset + PF.RULE_OPCODE_SIZE <= ruleOffset + size, RuleFieldOutOfBounds(ruleOffset));
        return uint8(self[offset]);
    }

    /// @notice Returns the data view (offset and length) for the rule at `ruleOffset`.
    /// @param self The policy blob.
    /// @param ruleOffset Offset of a rule header within `self`.
    /// @return dataOffset Offset of the operator data payload within `self`.
    /// @return dataLength Length of the operator data payload.
    function dataView(
        bytes memory self,
        uint256 ruleOffset
    )
        internal
        pure
        returns (uint256 dataOffset, uint16 dataLength)
    {
        uint8 depth = pathDepth(self, ruleOffset);
        uint256 offset = ruleOffset + PF.RULE_PATH_OFFSET + (uint256(depth) * PF.PATH_STEP_SIZE) + PF.RULE_OPCODE_SIZE;
        uint16 size = Be16.readUnchecked(self, ruleOffset);
        require(offset + PF.RULE_DATALENGTH_SIZE <= ruleOffset + size, RuleFieldOutOfBounds(ruleOffset));

        dataLength = Be16.readUnchecked(self, offset);
        dataOffset = offset + PF.RULE_DATALENGTH_SIZE;
        require(dataOffset + dataLength <= ruleOffset + size, RuleFieldOutOfBounds(ruleOffset));
    }
}

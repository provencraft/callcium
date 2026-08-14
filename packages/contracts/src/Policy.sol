// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Be16 } from "./Be16.sol";
import { Descriptor } from "./Descriptor.sol";
import { DescriptorFormat as DF } from "./DescriptorFormat.sol";
import { OpCode } from "./OpCode.sol";
import { OpRule } from "./OpRule.sol";
import { Path } from "./Path.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";
import { LibBytes } from "solady/utils/LibBytes.sol";

/// @title Policy
/// @notice Format-aware views for policy blobs.
library Policy {
    /// @dev State threaded through the compilation of a path into a hint block.
    struct HintWalk {
        /// Hops of the chain currently being compiled.
        bytes chain;
        /// Hops of the main chain, captured when a quantifier closes it.
        bytes mainHops;
        /// Byte offset of the next node relative to the chain's current base.
        uint256 delta;
        /// Frame prefix packed as it appears on the wire: arrayDelta(32) | count(16) | meta(16).
        uint256 frame;
        /// Header kind the path resolves to.
        uint8 kind;
        /// Set while the chain already ends inside the current node, which then takes no entry hop.
        bool entered;
    }

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

    /// @notice Thrown when bytes remain after the last group.
    error TrailingBytes();

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

    /// @notice Thrown when a hint block carries a reserved or unused state.
    /// @param ruleOffset The offset of the rule with the malformed hint.
    error MalformedHint(uint256 ruleOffset);

    /// @notice Thrown when a rule's operator family does not match the type its target declares.
    /// @param ruleOffset The byte offset of the rule within the policy.
    error OperatorTargetMismatch(uint256 ruleOffset);

    /// @notice Thrown when a path does not address a target reachable by a hop chain.
    /// @param stepIndex The index of the path step that does not resolve.
    error UncompilablePath(uint256 stepIndex);

    /// @notice Thrown when a rule has an empty path.
    /// @param ruleOffset The offset of the rule with depth zero.
    error EmptyPath(uint256 ruleOffset);

    /// @notice Thrown when a rule has an unknown operator code or mismatched payload size.
    /// @param ruleOffset The offset of the rule with the invalid operator.
    error UnknownOperator(uint256 ruleOffset);

    /// @notice Thrown when an IN operator's operands are not strictly ascending (unsigned).
    /// @param ruleOffset The offset of the rule with the unsorted set.
    error UnsortedInSet(uint256 ruleOffset);

    /// @notice Thrown when a rule path exceeds the maximum depth.
    /// @param ruleOffset The offset of the rule.
    /// @param depth The declared path depth.
    error PathTooDeep(uint256 ruleOffset, uint256 depth);

    /// @notice Thrown when a context rule references an undefined context property.
    /// @param ruleOffset The offset of the rule.
    error UnknownContextProperty(uint256 ruleOffset);

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
                ruleOffset = _validateRule(self, ruleOffset, groupEnd);
            }

            require(ruleOffset == groupEnd, GroupSizeMismatch(offset));

            offset = groupEnd;
        }

        require(offset == self.length, TrailingBytes());
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
        assembly ("memory-safe") {
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

    /// @notice Returns the offset and size of the compiled hint block for the rule at `ruleOffset`.
    /// @dev Context rules carry no hint block and resolve to a zero size.
    /// @param self The policy blob.
    /// @param ruleOffset Offset of a rule header within `self`.
    /// @return hintOffset Byte offset of the hint block within `self`.
    /// @return hintSize Size of the hint block in bytes.
    function hintView(
        bytes memory self,
        uint256 ruleOffset
    )
        internal
        pure
        returns (uint256 hintOffset, uint256 hintSize)
    {
        uint256 depth = pathDepth(self, ruleOffset);
        hintOffset = ruleOffset + PF.RULE_PATH_OFFSET + depth * PF.PATH_STEP_SIZE;
        if (scope(self, ruleOffset) == PF.SCOPE_CONTEXT) return (hintOffset, 0);

        uint256 ruleEnd = ruleOffset + Be16.readUnchecked(self, ruleOffset);
        require(hintOffset + PF.HINT_HEADER_SIZE <= ruleEnd, RuleFieldOutOfBounds(ruleOffset));

        uint8 header = uint8(self[hintOffset]);
        uint256 hopsEnd = hintOffset + PF.HINT_HEADER_SIZE + uint256(header & PF.HINT_HOP_COUNT_MASK) * PF.HINT_HOP_SIZE;
        hintSize = hopsEnd - hintOffset + PF.HINT_TARGET_SIZE;

        // A quantifier frame sits between the main chain and the target, sized by its own header byte.
        if (header >> PF.HINT_KIND_SHIFT != PF.HINT_KIND_NONE) {
            uint256 suffixHeaderOffset = hopsEnd + PF.HINT_FRAME_PREFIX_SIZE;
            require(suffixHeaderOffset < ruleEnd, RuleFieldOutOfBounds(ruleOffset));
            uint8 suffixHeader = uint8(self[suffixHeaderOffset]);
            hintSize += PF.HINT_FRAME_PREFIX_SIZE + PF.HINT_HEADER_SIZE + uint256(suffixHeader & PF.HINT_HOP_COUNT_MASK)
            * PF.HINT_HOP_SIZE;
        }
        require(hintOffset + hintSize <= ruleEnd, RuleFieldOutOfBounds(ruleOffset));
    }

    /// @notice Compiles a calldata rule path into its wire hint block.
    /// @dev Reverts when a step leaves the structure the descriptor declares, quantifies over a
    /// non-array node, or repeats a quantifier.
    /// @param desc The descriptor bytes.
    /// @param path Path encoded as big-endian uint16 steps.
    /// @return The hint block bytes.
    function compileHint(bytes memory desc, bytes memory path) internal pure returns (bytes memory) {
        uint256 depth = Path.validate(path);
        uint256 argIndex = Path.atUnchecked(path, 0);
        require(argIndex < Descriptor.paramCount(desc), UncompilablePath(0));

        // The argument's head slot sits past the slots of every preceding parameter.
        (uint256 argSpan, uint256 descOffset) = _headSpan(desc, DF.HEADER_SIZE, argIndex);
        HintWalk memory walk;
        walk.delta = argSpan;

        for (uint256 stepIndex = 1; stepIndex < depth; ++stepIndex) {
            descOffset = _walkStep(desc, walk, descOffset, Path.atUnchecked(path, stepIndex), stepIndex);
        }

        (uint8 targetCode, bool targetIsDynamic,,) = Descriptor.inspect(desc, descOffset);
        _enter(walk, targetIsDynamic && !walk.entered);

        uint16 targetMeta;
        if (targetCode == TypeCode.DYNAMIC_ARRAY) (targetMeta,) = _arrayMeta(desc, descOffset, targetCode);

        // Packed as the target block it becomes on the wire: targetDelta(32) | targetMeta(16) | typeCode(8).
        return _encodeHint(walk, (walk.delta << 24) | (uint256(targetMeta) << 8) | targetCode, depth);
    }

    /// @notice Returns the operator code for the rule at `ruleOffset`.
    /// @param self The policy blob.
    /// @param ruleOffset Offset of a rule header within `self`.
    /// @return The operator code byte.
    function opCode(bytes memory self, uint256 ruleOffset) internal pure returns (uint8) {
        (uint256 hintOffset, uint256 hintSize) = hintView(self, ruleOffset);
        uint256 offset = hintOffset + hintSize;

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
        (uint256 hintOffset, uint256 hintSize) = hintView(self, ruleOffset);
        uint256 offset = hintOffset + hintSize + PF.RULE_OPCODE_SIZE;
        uint16 size = Be16.readUnchecked(self, ruleOffset);
        require(offset + PF.RULE_DATALENGTH_SIZE <= ruleOffset + size, RuleFieldOutOfBounds(ruleOffset));

        dataLength = Be16.readUnchecked(self, offset);
        dataOffset = offset + PF.RULE_DATALENGTH_SIZE;
        require(dataOffset + dataLength <= ruleOffset + size, RuleFieldOutOfBounds(ruleOffset));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    ////////////////////////////////////////////////////////////////////////*/

    /// @dev Validates a single rule and returns the offset of the next rule.
    function _validateRule(bytes memory self, uint256 ruleOffset, uint256 groupEnd) private pure returns (uint256) {
        uint16 ruleTotalSize = ruleSize(self, ruleOffset);

        // Scope must be a defined value.
        uint8 ruleScope = uint8(self[ruleOffset + PF.RULE_SCOPE_OFFSET]);
        require(ruleScope == PF.SCOPE_CONTEXT || ruleScope == PF.SCOPE_CALLDATA, InvalidScope(ruleOffset));

        uint256 depth = uint8(self[ruleOffset + PF.RULE_DEPTH_OFFSET]);
        (uint256 hintOffset, uint256 hintSize) = hintView(self, ruleOffset);
        if (hintSize != 0) _validateHint(self, ruleOffset, hintOffset, hintSize);

        // Framing consistency: declared size must match field layout.
        uint256 dataLengthOffset = hintOffset + hintSize + PF.RULE_OPCODE_SIZE;
        require(dataLengthOffset + PF.RULE_DATALENGTH_SIZE <= ruleOffset + ruleTotalSize, RuleSizeMismatch(ruleOffset));
        uint16 dataLength = Be16.readUnchecked(self, dataLengthOffset);
        require(
            ruleTotalSize == PF.RULE_FIXED_OVERHEAD + depth * PF.PATH_STEP_SIZE + hintSize + dataLength,
            RuleSizeMismatch(ruleOffset)
        );

        // Operator must be a defined opcode with valid payload size.
        uint8 opBase = uint8(self[dataLengthOffset - PF.RULE_OPCODE_SIZE]) & ~OpCode.NOT;
        require(opBase != 0 && OpRule.isValidPayloadSize(opBase, dataLength), UnknownOperator(ruleOffset));

        if (hintSize != 0) _validateOperatorTarget(self, ruleOffset, hintOffset, hintSize, opBase);

        // IN operands must be strictly ascending (unsigned); strictness also rejects duplicates.
        if (opBase == OpCode.IN) {
            _validateInAscending(self, dataLengthOffset + PF.RULE_DATALENGTH_SIZE, dataLength, ruleOffset);
        }

        // Path must be non-empty and within the depth cap.
        require(depth >= 1, EmptyPath(ruleOffset));
        require(depth <= PF.MAX_PATH_DEPTH, PathTooDeep(ruleOffset, depth));

        // Context-scope rules must have exactly one path step naming a defined property.
        if (ruleScope == PF.SCOPE_CONTEXT) {
            require(depth == 1, InvalidContextPath(ruleOffset));
            uint16 contextPropertyId = Be16.readUnchecked(self, ruleOffset + PF.RULE_PATH_OFFSET);
            require(contextPropertyId <= PF.CTX_MAX, UnknownContextProperty(ruleOffset));
        }

        ruleOffset += ruleTotalSize;
        require(ruleOffset <= groupEnd, RuleOverflow(ruleOffset - ruleTotalSize));
        return ruleOffset;
    }

    /// @dev Returns the combined head slot span of the `count` nodes at `offset`, and the offset of the node past them.
    function _headSpan(
        bytes memory desc,
        uint256 offset,
        uint256 count
    )
        private
        pure
        returns (uint256 span, uint256 nodeOffset)
    {
        nodeOffset = offset;
        for (uint256 i; i < count; ++i) {
            (, bool isDynamic, uint32 staticSize, uint256 next) = Descriptor.inspect(desc, nodeOffset);
            // An indirected node occupies a single offset word.
            span += isDynamic ? 32 : staticSize;
            nodeOffset = next;
        }
    }

    /// @dev Applies one path step to `walk` and returns the descriptor offset the step reaches.
    function _walkStep(
        bytes memory desc,
        HintWalk memory walk,
        uint256 descOffset,
        uint16 step,
        uint256 stepIndex
    )
        private
        pure
        returns (uint256)
    {
        (uint8 code, bool isDynamic,,) = Descriptor.inspect(desc, descOffset);

        // A quantifier reaches an array alone, every other code reading its value as an index.
        if (code == TypeCode.TUPLE) {
            require(step < Descriptor.tupleFieldCount(desc, descOffset), UncompilablePath(stepIndex));
            _enter(walk, isDynamic && !walk.entered);

            (uint256 fieldSpan, uint256 fieldOffset) = _headSpan(desc, descOffset + DF.TUPLE_HEADER_SIZE, step);
            walk.delta += fieldSpan;
            walk.entered = false;
            return fieldOffset;
        }

        require(code == TypeCode.STATIC_ARRAY || code == TypeCode.DYNAMIC_ARRAY, UncompilablePath(stepIndex));
        if (code == TypeCode.STATIC_ARRAY && step < Path.ANY) {
            require(step < Descriptor.staticArrayLength(desc, descOffset), UncompilablePath(stepIndex));
        }
        (uint16 meta, bool elemIsDynamic) = _arrayMeta(desc, descOffset, code);

        if (step >= Path.ANY) {
            require(walk.kind == PF.HINT_KIND_NONE, UncompilablePath(stepIndex));
            _enter(walk, isDynamic && !walk.entered);

            uint256 count = code == TypeCode.DYNAMIC_ARRAY ? 0 : Descriptor.staticArrayLength(desc, descOffset);
            walk.frame = (walk.delta << 32) | (count << 16) | meta;
            walk.kind = step == Path.ALL ? PF.HINT_KIND_ALL : PF.HINT_KIND_ANY;

            walk.mainHops = walk.chain;
            walk.chain = "";
            walk.delta = 0;
        } else if (isDynamic) {
            // An indirected array holds its elements behind an offset word.
            _enter(walk, !walk.entered);
            walk.chain = abi.encodePacked(walk.chain, uint32(0), step, meta);
            walk.delta = 0;
        } else {
            // A static array of static elements is inline, so the index folds into the accumulator.
            walk.delta += uint256(step) * uint256(meta & PF.HINT_META_STRIDE_MASK) * 32;
        }

        walk.entered = elemIsDynamic;
        return descOffset + DF.ARRAY_HEADER_SIZE;
    }

    /// @dev Appends the hop entering an indirected node's payload and rebases the offset accumulator.
    function _enter(HintWalk memory walk, bool needed) private pure {
        if (!needed) return;
        // forge-lint: disable-next-line(unsafe-typecast) descriptor limits bound head offsets below 2**32.
        walk.chain = abi.encodePacked(walk.chain, uint32(walk.delta), PF.HINT_NO_INDEX, uint16(0));
        walk.delta = 0;
    }

    /// @dev Serializes a completed walk and its packed target block into the wire hint block.
    function _encodeHint(HintWalk memory walk, uint256 target, uint256 depth) private pure returns (bytes memory) {
        bytes memory suffixHops;
        if (walk.kind == PF.HINT_KIND_NONE) walk.mainHops = walk.chain;
        else suffixHops = walk.chain;

        uint256 mainHopCount = walk.mainHops.length / PF.HINT_HOP_SIZE;
        uint256 suffixHopCount = suffixHops.length / PF.HINT_HOP_SIZE;
        require(
            mainHopCount <= PF.HINT_HOP_COUNT_MASK && suffixHopCount <= PF.HINT_HOP_COUNT_MASK, UncompilablePath(depth)
        );

        // forge-lint: disable-next-line(unsafe-typecast) bounded above by the hop count check.
        bytes memory out = abi.encodePacked((walk.kind << PF.HINT_KIND_SHIFT) | uint8(mainHopCount), walk.mainHops);

        if (walk.kind != PF.HINT_KIND_NONE) {
            // forge-lint: disable-next-line(unsafe-typecast) the frame is packed to its wire width.
            out = abi.encodePacked(out, uint64(walk.frame), uint8(suffixHopCount), suffixHops);
        }

        // forge-lint: disable-next-line(unsafe-typecast) the target is packed to its wire width.
        return abi.encodePacked(out, uint56(target));
    }

    /// @dev Returns the meta word describing the array node at `arrayOffset`, and whether its elements are dynamic.
    function _arrayMeta(
        bytes memory desc,
        uint256 arrayOffset,
        uint8 code
    )
        private
        pure
        returns (uint16 meta, bool elemIsDynamic)
    {
        uint32 elemStaticSize;
        (, elemIsDynamic, elemStaticSize,) = Descriptor.inspect(desc, arrayOffset + DF.ARRAY_HEADER_SIZE);
        // A dynamic element occupies one offset word within the element region.
        // forge-lint: disable-next-line(unsafe-typecast) descriptor static words fit the stride field.
        meta = elemIsDynamic ? 1 : uint16(elemStaticSize >> 5);
        if (elemIsDynamic) meta |= PF.HINT_META_ELEM_DYNAMIC;
        if (code == TypeCode.DYNAMIC_ARRAY) meta |= PF.HINT_META_DYNAMIC_ARRAY;
    }

    /// @dev Requires the hint block at `hintOffset` to carry no reserved or unused state.
    function _validateHint(bytes memory self, uint256 ruleOffset, uint256 hintOffset, uint256 hintSize) private pure {
        uint8 header = uint8(self[hintOffset]);
        uint8 kind = header >> PF.HINT_KIND_SHIFT;
        require(kind <= PF.HINT_KIND_MAX, MalformedHint(ruleOffset));

        uint256 hopsStart = hintOffset + PF.HINT_HEADER_SIZE;
        uint256 hopsEnd = hopsStart + uint256(header & PF.HINT_HOP_COUNT_MASK) * PF.HINT_HOP_SIZE;
        _validateHops(self, ruleOffset, hopsStart, hopsEnd);

        uint256 targetOffset = hintOffset + hintSize - PF.HINT_TARGET_SIZE;
        if (kind != PF.HINT_KIND_NONE) {
            uint16 frameMeta = Be16.readUnchecked(self, hopsEnd + PF.HINT_FRAME_META_OFFSET);
            require(frameMeta & PF.HINT_META_RESERVED_MASK == 0, MalformedHint(ruleOffset));
            uint8 suffixHeader = uint8(self[hopsEnd + PF.HINT_FRAME_PREFIX_SIZE]);
            require(suffixHeader & PF.HINT_SUFFIX_RESERVED_MASK == 0, MalformedHint(ruleOffset));
            _validateHops(self, ruleOffset, hopsEnd + PF.HINT_FRAME_PREFIX_SIZE + PF.HINT_HEADER_SIZE, targetOffset);
        }

        uint16 targetMeta = Be16.readUnchecked(self, targetOffset + PF.HINT_TARGET_META_OFFSET);
        uint8 typeCode = uint8(self[targetOffset + PF.HINT_TARGET_TYPECODE_OFFSET]);
        // A target meta word describes a dynamic array and is absent for every other type.
        // forgefmt: disable-next-item
        require(
            typeCode == TypeCode.DYNAMIC_ARRAY
                ? targetMeta & PF.HINT_META_RESERVED_MASK == 0
                : targetMeta == 0,
            MalformedHint(ruleOffset)
        );

        // An operator reads either a scalar word or a declared length, so a target carrying
        // neither — a tuple, a static array, or an undefined code — addresses nothing.
        // forgefmt: disable-next-item
        require(
            TypeRule.isElementary(typeCode) || TypeRule.hasCalldataLength(typeCode),
            MalformedHint(ruleOffset)
        );
    }

    /// @dev Requires the operator family to match the type the rule's hint target declares.
    function _validateOperatorTarget(
        bytes memory self,
        uint256 ruleOffset,
        uint256 hintOffset,
        uint256 hintSize,
        uint8 opBase
    )
        private
        pure
    {
        uint256 typeCodeOffset = hintOffset + hintSize - PF.HINT_TARGET_SIZE + PF.HINT_TARGET_TYPECODE_OFFSET;
        // A length operator reads the declared length a dynamic target resolves to, and a value
        // operator reads a scalar word, so the target type fixes which family the rule may carry.
        // forgefmt: disable-next-item
        require(
            TypeRule.hasCalldataLength(uint8(self[typeCodeOffset])) == OpRule.isLengthOp(opBase),
            OperatorTargetMismatch(ruleOffset)
        );
    }

    /// @dev Requires every hop entry in `[start, end)` to carry no reserved or unused state.
    function _validateHops(bytes memory self, uint256 ruleOffset, uint256 start, uint256 end) private pure {
        for (uint256 offset = start; offset < end; offset += PF.HINT_HOP_SIZE) {
            uint16 index = Be16.readUnchecked(self, offset + PF.HINT_HOP_INDEX_OFFSET);
            uint16 meta = Be16.readUnchecked(self, offset + PF.HINT_HOP_META_OFFSET);
            require(index != PF.HINT_INDEX_RESERVED, MalformedHint(ruleOffset));

            // A plain hop carries no element meta; an element hop addresses no offset of its own.
            if (index == PF.HINT_NO_INDEX) {
                require(meta == 0, MalformedHint(ruleOffset));
            } else {
                require(uint32(bytes4(LibBytes.load(self, offset))) == 0, MalformedHint(ruleOffset));
                require(meta & PF.HINT_META_RESERVED_MASK == 0, MalformedHint(ruleOffset));
            }
        }
    }

    /// @dev Requires the IN operand words to be strictly ascending by unsigned value.
    function _validateInAscending(
        bytes memory self,
        uint256 payloadStart,
        uint16 dataLength,
        uint256 ruleOffset
    )
        private
        pure
    {
        uint256 count = dataLength / 32;
        uint256 prev = uint256(LibBytes.load(self, payloadStart));
        for (uint256 i = 1; i < count; ++i) {
            uint256 cur = uint256(LibBytes.load(self, payloadStart + i * 32));
            require(cur > prev, UnsortedInSet(ruleOffset));
            prev = cur;
        }
    }
}

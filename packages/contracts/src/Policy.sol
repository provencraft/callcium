// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Be16 } from "./Be16.sol";
import { Descriptor } from "./Descriptor.sol";
import { OpCode } from "./OpCode.sol";
import { OpRule } from "./OpRule.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";
import { LibBytes } from "./vendor/solady/utils/LibBytes.sol";

/// @title Policy
/// @notice Format-aware views for policy blobs.
library Policy {
    /*/////////////////////////////////////////////////////////////////////////
                                     ERRORS
    ////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the policy header is truncated or has an invalid field.
    error MalformedHeader();

    /// @notice Thrown when the policy format major version is not supported.
    /// @param major The unsupported major version.
    error UnsupportedVersion(uint8 major);

    /// @notice Thrown when the minor version is not the lowest covering the policy's features.
    /// @param minor The declared minor version.
    error MinorMismatch(uint8 minor);

    /// @notice Thrown when the policy declares zero groups.
    error EmptyPolicy();

    /// @notice Thrown when parsing reaches end of policy blob unexpectedly.
    error UnexpectedEnd();

    /// @notice Thrown when bytes remain after the last group.
    error TrailingBytes();

    /// @notice Thrown when a group extends beyond policy boundaries.
    /// @param groupOffset The offset of the malformed group.
    error GroupOverflow(uint256 groupOffset);

    /// @notice Thrown when a rule extends beyond group boundaries.
    /// @param ruleOffset The offset of the malformed rule.
    error RuleOverflow(uint256 ruleOffset);

    /// @notice Thrown when a rule size is below the minimum.
    /// @param ruleOffset The offset of the malformed rule.
    /// @param size The declared size.
    error RuleTooSmall(uint256 ruleOffset, uint256 size);

    /// @notice Thrown when declared rule size does not match the field layout.
    /// @param ruleOffset The offset of the inconsistent rule.
    error RuleSizeMismatch(uint256 ruleOffset);

    /// @notice Thrown when a hint block carries a reserved or unused state.
    /// @param ruleOffset The offset of the rule with the malformed hint.
    error MalformedHint(uint256 ruleOffset);

    /// @notice Thrown when a rule's operator family does not match the type its target declares.
    /// @param ruleOffset The byte offset of the rule within the policy.
    error OperatorTargetMismatch(uint256 ruleOffset);

    /// @notice Thrown when a rule has an empty path.
    /// @param ruleOffset The offset of the rule with depth zero.
    error EmptyPath(uint256 ruleOffset);

    /// @notice Thrown when a path step lies in the reserved marker range.
    /// @param ruleOffset The offset of the rule with the reserved step.
    error UnknownPathStep(uint256 ruleOffset);

    /// @notice Thrown when a rule has an unknown operator code.
    /// @param ruleOffset The offset of the rule with the invalid operator.
    error UnknownOperator(uint256 ruleOffset);

    /// @notice Thrown when an operator's payload size does not match its operand width.
    /// @param ruleOffset The offset of the rule with the invalid operator.
    error DataLengthMismatch(uint256 ruleOffset);

    /// @notice Thrown when a context operand is used with an operator other than EQ, GT, LT, GTE or LTE.
    /// @param ruleOffset The offset of the rule with the invalid operator.
    error InvalidContextOperand(uint256 ruleOffset);

    /// @notice Thrown when an IN operator's operands are not strictly ascending (unsigned).
    /// @param ruleOffset The offset of the rule with the unsorted set.
    error UnsortedInSet(uint256 ruleOffset);

    /// @notice Thrown when a rule path exceeds the maximum depth.
    /// @param ruleOffset The offset of the rule.
    /// @param depth The path depth counted across the enclosing loop.
    error PathTooDeep(uint256 ruleOffset, uint256 depth);

    /// @notice Thrown when a context rule references an undefined context property.
    /// @param ruleOffset The offset of the rule.
    error UnknownContextProperty(uint256 ruleOffset);

    /// @notice Thrown when a group or a loop body declares zero rules.
    /// @param groupOffset The offset of the empty group, or of the loop rule that contains the empty body.
    error EmptyGroup(uint256 groupOffset);

    /// @notice Thrown when rules do not exactly fill the declared group size.
    /// @param groupOffset The offset of the group with trailing bytes.
    error GroupSizeMismatch(uint256 groupOffset);

    /// @notice Thrown when a rule scope byte is not a defined value.
    /// @param ruleOffset The offset of the rule with the invalid scope.
    error UnknownScope(uint256 ruleOffset);

    /// @notice Thrown when a loop body contains a loop rule.
    /// @param ruleOffset The offset of the inner loop rule.
    error InvalidNestedLoop(uint256 ruleOffset);

    /// @notice Thrown when a loop quantifier byte is not a defined value.
    /// @param ruleOffset The offset of the loop rule with the invalid quantifier.
    error UnknownQuantifier(uint256 ruleOffset);

    /// @notice Thrown when a context-scope rule does not have exactly one path step.
    /// @param ruleOffset The offset of the rule with the invalid path depth.
    error InvalidContextPath(uint256 ruleOffset);

    /// @notice Thrown when the selector is accessed on a selectorless policy.
    error OmittedSelector();

    /*/////////////////////////////////////////////////////////////////////////
                                    FUNCTIONS
    ////////////////////////////////////////////////////////////////////////*/

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
        // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: `selector`.
        return bytes4(LibBytes.load(self, PF.POLICY_SELECTOR_OFFSET));
    }

    /// @notice Validates the policy blob structure and version.
    /// @param self The policy blob to validate.
    function validate(bytes memory self) internal pure {
        require(self.length >= PF.POLICY_HEADER_PREFIX, MalformedHeader());
        uint8 header = uint8(self[PF.POLICY_HEADER_OFFSET]);
        uint8 major = header >> PF.MAJOR_SHIFT;
        require(major == PF.MAJOR, UnsupportedVersion(major));
        // A blob that uses no extension declares MINOR, the lowest minor covering its features.
        uint8 minor = (header >> PF.MINOR_SHIFT) & PF.MINOR_MASK;
        require(minor == PF.MINOR, MinorMismatch(minor));

        // Selectorless policies must have a zeroed selector slot.
        if ((header & PF.FLAG_NO_SELECTOR) != 0) {
            // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: `selector`.
            require(bytes4(LibBytes.load(self, PF.POLICY_SELECTOR_OFFSET)) == bytes4(0), MalformedHeader());
        }

        uint256 groupCountOffset = PF.POLICY_DESC_OFFSET + Be16.readUnchecked(self, PF.POLICY_DESC_LENGTH_OFFSET);
        require(self.length >= groupCountOffset + PF.POLICY_GROUP_COUNT_SIZE, MalformedHeader());
        Descriptor.validate(LibBytes.slice(self, PF.POLICY_DESC_OFFSET, groupCountOffset));

        uint8 totalGroups = uint8(self[groupCountOffset]);
        require(totalGroups > 0, EmptyPolicy());
        uint256 offset = groupCountOffset + PF.POLICY_GROUP_COUNT_SIZE;

        for (uint256 groupIndex = 0; groupIndex < totalGroups; ++groupIndex) {
            require(offset + PF.GROUP_HEADER_SIZE <= self.length, UnexpectedEnd());

            // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: `groupSize`.
            uint32 rulesRegionSize = uint32(bytes4(LibBytes.load(self, offset + PF.GROUP_SIZE_OFFSET)));
            uint256 groupEnd = offset + PF.GROUP_HEADER_SIZE + rulesRegionSize;
            require(groupEnd <= self.length, GroupOverflow(offset));

            uint16 totalRules = Be16.readUnchecked(self, offset + PF.GROUP_RULECOUNT_OFFSET);
            require(totalRules > 0, EmptyGroup(offset));
            uint256 ruleOffset = offset + PF.GROUP_HEADER_SIZE;

            for (uint256 ruleIndex = 0; ruleIndex < totalRules; ++ruleIndex) {
                require(ruleOffset + PF.RULE_SIZE_SIZE <= groupEnd, GroupSizeMismatch(offset));
                ruleOffset = _validateRule(self, ruleOffset, groupEnd);
            }

            require(ruleOffset == groupEnd, GroupSizeMismatch(offset));

            offset = groupEnd;
        }

        require(offset == self.length, TrailingBytes());
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    ////////////////////////////////////////////////////////////////////////*/

    /// @dev Validates a single rule and returns the offset of the next rule.
    function _validateRule(bytes memory self, uint256 ruleOffset, uint256 groupEnd) private pure returns (uint256) {
        uint256 ruleEnd = ruleOffset + _ruleSize(self, ruleOffset, groupEnd);
        uint8 ruleScope = _scope(self, ruleOffset, ruleEnd);
        if (ruleScope == PF.SCOPE_LOOP) _validateLoop(self, ruleOffset, ruleEnd);
        else _validateTest(self, ruleOffset, ruleEnd, ruleScope, 0);
        return ruleEnd;
    }

    /// @dev Returns the size of the rule at `ruleOffset`, which must lie within `end`.
    function _ruleSize(bytes memory self, uint256 ruleOffset, uint256 end) private pure returns (uint16 size) {
        size = Be16.readUnchecked(self, ruleOffset);
        require(size >= PF.RULE_SIZE_SIZE, RuleTooSmall(ruleOffset, size));
        require(ruleOffset + size <= end, RuleOverflow(ruleOffset));
    }

    /// @dev Returns the scope of the rule at `ruleOffset`, which must be a defined value.
    function _scope(bytes memory self, uint256 ruleOffset, uint256 ruleEnd) private pure returns (uint8 ruleScope) {
        require(ruleOffset + PF.RULE_SCOPE_OFFSET + PF.RULE_SCOPE_SIZE <= ruleEnd, RuleSizeMismatch(ruleOffset));
        ruleScope = uint8(self[ruleOffset + PF.RULE_SCOPE_OFFSET]);
        // forgefmt: disable-next-item
        require(
            ruleScope == PF.SCOPE_CONTEXT || ruleScope == PF.SCOPE_CALLDATA || ruleScope == PF.SCOPE_LOOP,
            UnknownScope(ruleOffset)
        );
    }

    /// @dev Validates the loop rule at `ruleOffset` and the tests of its body.
    function _validateLoop(bytes memory self, uint256 ruleOffset, uint256 ruleEnd) private pure {
        // forgefmt: disable-next-item
        require(
            ruleOffset + PF.RULE_QUANTIFIER_OFFSET + PF.RULE_QUANTIFIER_SIZE <= ruleEnd,
            RuleSizeMismatch(ruleOffset)
        );
        uint8 quantifier = uint8(self[ruleOffset + PF.RULE_QUANTIFIER_OFFSET]);
        // forgefmt: disable-next-item
        require(
            quantifier == PF.QUANTIFIER_ALL || quantifier == PF.QUANTIFIER_ANY,
            UnknownQuantifier(ruleOffset)
        );

        (uint256 hintOffset, uint256 depth) =
            _validatePath(self, ruleOffset, ruleOffset + PF.LOOP_DEPTH_OFFSET, ruleEnd);
        require(depth >= 1, EmptyPath(ruleOffset));
        require(depth <= PF.MAX_PATH_DEPTH, PathTooDeep(ruleOffset, depth));

        uint256 frameOffset = _validateHint(self, ruleOffset, hintOffset, ruleEnd);
        // forgefmt: disable-next-item
        require(
            frameOffset + PF.HINT_FRAME_PREFIX_SIZE + PF.GROUP_RULECOUNT_SIZE <= ruleEnd,
            RuleSizeMismatch(ruleOffset)
        );
        uint16 frameMeta = Be16.readUnchecked(self, frameOffset + PF.HINT_FRAME_META_OFFSET);
        require(frameMeta & PF.HINT_META_RESERVED_MASK == 0, MalformedHint(ruleOffset));

        uint256 bodyOffset = frameOffset + PF.HINT_FRAME_PREFIX_SIZE;
        uint16 totalRules = Be16.readUnchecked(self, bodyOffset);
        require(totalRules > 0, EmptyGroup(ruleOffset));
        uint256 testOffset = bodyOffset + PF.GROUP_RULECOUNT_SIZE;

        for (uint256 ruleIndex = 0; ruleIndex < totalRules; ++ruleIndex) {
            require(testOffset + PF.RULE_SIZE_SIZE <= ruleEnd, RuleSizeMismatch(ruleOffset));
            uint256 testEnd = testOffset + _ruleSize(self, testOffset, ruleEnd);
            uint8 testScope = _scope(self, testOffset, testEnd);
            require(testScope != PF.SCOPE_LOOP, InvalidNestedLoop(testOffset));
            _validateTest(self, testOffset, testEnd, testScope, depth);
            testOffset = testEnd;
        }

        require(testOffset == ruleEnd, RuleSizeMismatch(ruleOffset));
    }

    /// @dev Validates the context or calldata test at `ruleOffset`, `outerDepth` path steps below the arguments.
    function _validateTest(
        bytes memory self,
        uint256 ruleOffset,
        uint256 ruleEnd,
        uint8 ruleScope,
        uint256 outerDepth
    )
        private
        pure
    {
        uint256 operatorOffset;
        uint8 typeCode;
        if (ruleScope == PF.SCOPE_CONTEXT) {
            // Context-scope rules must have exactly one path step naming a defined property.
            require(ruleOffset + PF.RULE_PATH_OFFSET <= ruleEnd, RuleSizeMismatch(ruleOffset));
            require(uint8(self[ruleOffset + PF.RULE_DEPTH_OFFSET]) == 1, InvalidContextPath(ruleOffset));
            operatorOffset = ruleOffset + PF.RULE_PATH_OFFSET + PF.PROPERTY_ID_SIZE;
            require(operatorOffset <= ruleEnd, RuleSizeMismatch(ruleOffset));
            uint16 contextPropertyId = Be16.readUnchecked(self, ruleOffset + PF.RULE_PATH_OFFSET);
            require(contextPropertyId <= PF.CTX_MAX, UnknownContextProperty(ruleOffset));
            typeCode = TypeRule.contextPropertyType(contextPropertyId);
        } else {
            (uint256 hintOffset, uint256 depth) =
                _validatePath(self, ruleOffset, ruleOffset + PF.RULE_DEPTH_OFFSET, ruleEnd);
            // A root test lies outside every loop, and only a root path must be non-empty.
            if (outerDepth == 0) require(depth >= 1, EmptyPath(ruleOffset));
            require(outerDepth + depth <= PF.MAX_PATH_DEPTH, PathTooDeep(ruleOffset, outerDepth + depth));

            uint256 targetOffset = _validateHint(self, ruleOffset, hintOffset, ruleEnd);
            operatorOffset = targetOffset + PF.HINT_TARGET_SIZE;
            require(operatorOffset <= ruleEnd, RuleSizeMismatch(ruleOffset));
            uint16 targetMeta = Be16.readUnchecked(self, targetOffset + PF.HINT_TARGET_META_OFFSET);
            typeCode = uint8(self[targetOffset + PF.HINT_TARGET_TYPECODE_OFFSET]);
            // A target meta word describes a dynamic array and is absent for every other type.
            // forgefmt: disable-next-item
            require(
                typeCode == TypeCode.DYNAMIC_ARRAY
                    ? targetMeta & PF.HINT_META_RESERVED_MASK == 0
                    : targetMeta == 0,
                MalformedHint(ruleOffset)
            );

            // An operator reads either a scalar word or a declared length, so a target carrying neither — a tuple, a
            // static array, or an undefined code — addresses nothing.
            // forgefmt: disable-next-item
            require(
                TypeRule.operandWidth(typeCode) != 0 || TypeRule.hasCalldataLength(typeCode),
                MalformedHint(ruleOffset)
            );
        }

        uint256 operatorEnd = _validateOperator(self, ruleOffset, operatorOffset, ruleEnd, typeCode);
        require(operatorEnd == ruleEnd, RuleSizeMismatch(ruleOffset));
    }

    /// @dev Requires the path whose depth field sits at `depthOffset` to step below the reserved marker range, and
    /// returns the offset past the path and its depth.
    function _validatePath(
        bytes memory self,
        uint256 ruleOffset,
        uint256 depthOffset,
        uint256 ruleEnd
    )
        private
        pure
        returns (uint256 pathEnd, uint256 depth)
    {
        require(depthOffset + PF.RULE_DEPTH_SIZE <= ruleEnd, RuleSizeMismatch(ruleOffset));
        depth = uint8(self[depthOffset]);
        uint256 pathStart = depthOffset + PF.RULE_DEPTH_SIZE;
        pathEnd = pathStart + depth * PF.PATH_STEP_SIZE;
        require(pathEnd <= ruleEnd, RuleSizeMismatch(ruleOffset));

        for (uint256 offset = pathStart; offset < pathEnd; offset += PF.PATH_STEP_SIZE) {
            require(Be16.readUnchecked(self, offset) < PF.PATH_MARKER_BASE, UnknownPathStep(ruleOffset));
        }
    }

    /// @dev Requires the hint header and hops at `hintOffset` to carry no reserved or unused state, and returns the
    /// offset past the hops.
    function _validateHint(
        bytes memory self,
        uint256 ruleOffset,
        uint256 hintOffset,
        uint256 ruleEnd
    )
        private
        pure
        returns (uint256 hopsEnd)
    {
        require(hintOffset + PF.HINT_HEADER_SIZE <= ruleEnd, RuleSizeMismatch(ruleOffset));
        uint8 header = uint8(self[hintOffset]);
        require(header & PF.HINT_HEADER_RESERVED_MASK == 0, MalformedHint(ruleOffset));

        uint256 hopsStart = hintOffset + PF.HINT_HEADER_SIZE;
        hopsEnd = hopsStart + uint256(header & PF.HINT_HOP_COUNT_MASK) * PF.HINT_HOP_SIZE;
        require(hopsEnd <= ruleEnd, RuleSizeMismatch(ruleOffset));
        _validateHops(self, ruleOffset, hopsStart, hopsEnd);
    }

    /// @dev Requires every hop entry in `[start, end)` to carry no reserved or unused state.
    function _validateHops(bytes memory self, uint256 ruleOffset, uint256 start, uint256 end) private pure {
        for (uint256 offset = start; offset < end; offset += PF.HINT_HOP_SIZE) {
            uint16 index = Be16.readUnchecked(self, offset + PF.HINT_HOP_INDEX_OFFSET);
            require(index == PF.HINT_NO_INDEX || index < PF.PATH_MARKER_BASE, MalformedHint(ruleOffset));

            uint16 meta = Be16.readUnchecked(self, offset + PF.HINT_HOP_META_OFFSET);
            // A plain hop carries no element meta; an element hop addresses no offset of its own.
            if (index == PF.HINT_NO_INDEX) {
                require(meta == 0, MalformedHint(ruleOffset));
            } else {
                // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the hop's delta.
                require(uint32(bytes4(LibBytes.load(self, offset))) == 0, MalformedHint(ruleOffset));
                require(meta & PF.HINT_META_RESERVED_MASK == 0, MalformedHint(ruleOffset));
            }
        }
    }

    /// @dev Validates the operator at `offset` against a target of `typeCode` and returns the offset past it.
    function _validateOperator(
        bytes memory self,
        uint256 ruleOffset,
        uint256 offset,
        uint256 ruleEnd,
        uint8 typeCode
    )
        private
        pure
        returns (uint256 operatorEnd)
    {
        require(offset + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE <= ruleEnd, RuleSizeMismatch(ruleOffset));
        uint8 opCode = uint8(self[offset]);
        uint8 opBase = opCode & OpCode.COMPARISON_MASK;
        uint8 source = (opCode & ~OpCode.NOT) >> OpCode.SOURCE_SHIFT;
        // forgefmt: disable-next-item
        require(
            OpRule.isComparison(opBase) && (source == OpCode.SOURCE_CONSTANT || source == OpCode.SOURCE_CONTEXT),
            UnknownOperator(ruleOffset)
        );

        // A length operator reads the declared length a dynamic target resolves to, and a value operator reads a scalar
        // word, so the target type fixes which family the rule may carry.
        bool isLength = OpRule.isLengthOp(opBase);
        require(TypeRule.hasCalldataLength(typeCode) == isLength, OperatorTargetMismatch(ruleOffset));

        uint16 dataLength = Be16.readUnchecked(self, offset + PF.RULE_OPCODE_SIZE);
        uint256 dataOffset = offset + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;
        operatorEnd = dataOffset + dataLength;

        if (source == OpCode.SOURCE_CONTEXT) {
            require(OpRule.acceptsContextSource(opBase), InvalidContextOperand(ruleOffset));
            require(dataLength == PF.PROPERTY_ID_SIZE, DataLengthMismatch(ruleOffset));
            require(operatorEnd <= ruleEnd, RuleSizeMismatch(ruleOffset));
            // A context operand must name a defined context property.
            require(Be16.readUnchecked(self, dataOffset) <= PF.CTX_MAX, UnknownContextProperty(ruleOffset));
        } else {
            uint256 width = TypeRule.operandWidth(isLength ? TypeRule.LENGTH_TYPE : typeCode);
            require(OpRule.isValidPayloadSize(opBase, dataLength, width), DataLengthMismatch(ruleOffset));
            require(operatorEnd <= ruleEnd, RuleSizeMismatch(ruleOffset));
            // IN operands must be strictly ascending (unsigned); strictness also rejects duplicates.
            if (opBase == OpCode.IN) _validateInAscending(self, dataOffset, dataLength, width, ruleOffset);
        }
    }

    /// @dev Requires the IN operand members to be strictly ascending by unsigned value. Sign extension and left
    /// alignment keep the unsigned order of a member's bytes, so the bytes order the members as their loaded words.
    function _validateInAscending(
        bytes memory self,
        uint256 payloadStart,
        uint16 dataLength,
        uint256 width,
        uint256 ruleOffset
    )
        private
        pure
    {
        uint256 count = dataLength / width;
        uint256 shift = 256 - 8 * width;
        uint256 prev = uint256(LibBytes.load(self, payloadStart)) >> shift;
        for (uint256 i = 1; i < count; ++i) {
            uint256 cur = uint256(LibBytes.load(self, payloadStart + i * width)) >> shift;
            require(cur > prev, UnsortedInSet(ruleOffset));
            prev = cur;
        }
    }
}

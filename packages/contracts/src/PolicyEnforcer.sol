// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Be16 } from "./Be16.sol";
import { CalldataReader } from "./CalldataReader.sol";
import { OpCode } from "./OpCode.sol";
import { Policy } from "./Policy.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";
import { LibBytes } from "./vendor/solady/utils/LibBytes.sol";

/// @title PolicyEnforcer
/// @notice Evaluation of ABI-encoded data against policy blobs.
library PolicyEnforcer {
    /// @dev Position a hop chain returns when an element hop's index is at or past a dynamic array's length. Every
    /// position a chain reaches is bounded by the calldata length plus wire-width fields, far below it.
    uint256 private constant INDEX_OUT_OF_BOUNDS = type(uint256).max;

    /*/////////////////////////////////////////////////////////////////////////
                                        ERRORS
    ////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when calldata violates the policy.
    error PolicyViolation(uint32 groupIndex, uint32 ruleIndex);

    /// @notice Thrown when the function selector does not match the policy header.
    error SelectorMismatch(bytes4 expected, bytes4 actual);

    /// @notice Thrown when calldata is too short to contain a selector.
    error MissingSelector();

    /// @notice Thrown when the policy's minor version is above the highest one this release implements.
    /// @param minor The declared minor version.
    error UnsupportedMinor(uint8 minor);

    /// @notice Thrown when array exceeds max length for quantified iteration.
    error QuantifierLimitExceeded(uint256 length, uint256 maxLength);

    /// @notice Thrown when a resolved word is not the canonical encoding of its declared type.
    /// @param typeCode The declared type of the target.
    /// @param value The raw 32-byte word.
    error NonCanonicalValue(uint8 typeCode, bytes32 value);

    /*/////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    ////////////////////////////////////////////////////////////////////////*/

    /// @notice Reverts when `callData` violates `policy`.
    /// @dev Requires a structurally validated policy blob. Behavior on an unvalidated blob is undefined.
    /// @param policy The policy blob with embedded descriptor.
    /// @param callData The calldata to validate.
    function enforce(bytes memory policy, bytes calldata callData) internal view {
        (bool ok, uint32 failedGroup, uint32 failedRule) = _evalPolicy(policy, callData);
        if (!ok) revert PolicyViolation(failedGroup, failedRule);
    }

    /// @notice Returns true if `callData` complies with `policy`.
    /// @dev Requires a structurally validated policy blob. Behavior on an unvalidated blob is undefined. Reverts on
    /// abort violations and integrity errors. Returns false for group-local violations.
    /// @param policy The policy blob with embedded descriptor.
    /// @param callData The calldata to validate.
    /// @return ok True if calldata complies with the policy.
    function check(bytes memory policy, bytes calldata callData) internal view returns (bool ok) {
        (ok,,) = _evalPolicy(policy, callData);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    ////////////////////////////////////////////////////////////////////////*/

    /// @dev Evaluates the full policy against calldata. Returns pass/fail with the failing group/rule indices.
    /// @dev Offsets are wire-bounded: a blob offset never exceeds the buffer length. Every field added to a blob offset
    /// is bounded by its own wire width, so no sum in this body can wrap.
    function _evalPolicy(
        bytes memory policy,
        bytes calldata callData
    )
        private
        view
        returns (bool ok, uint32 failingGroup, uint32 failingRule)
    {
        unchecked {
            // Every field read below indexes the buffer unchecked, so the header must be present.
            require(policy.length >= PF.POLICY_HEADER_PREFIX, Policy.MalformedHeader());

            // Parse the policy header once; every later field read reuses these offsets.
            uint8 policyHeader = _byteAt(policy, PF.POLICY_HEADER_OFFSET);
            uint8 major = policyHeader >> PF.MAJOR_SHIFT;
            require(major == PF.MAJOR, Policy.UnsupportedVersion(major));
            uint8 minor = (policyHeader >> PF.MINOR_SHIFT) & PF.MINOR_MASK;
            require(minor <= PF.SUPPORTED_MINOR, UnsupportedMinor(minor));

            // Determine base offset and validate selector if present.
            uint256 baseOffset = 0;
            if (policyHeader & PF.FLAG_NO_SELECTOR == 0) {
                // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: `selector`.
                bytes4 expectedSelector = bytes4(LibBytes.load(policy, PF.POLICY_SELECTOR_OFFSET));
                require(callData.length >= PF.POLICY_SELECTOR_SIZE, MissingSelector());
                // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the calldata's selector.
                bytes4 actualSelector = bytes4(LibBytes.loadCalldata(callData, 0));
                require(expectedSelector == actualSelector, SelectorMismatch(expectedSelector, actualSelector));
                baseOffset = PF.POLICY_SELECTOR_SIZE;
            }

            // Groups sit past the embedded descriptor, whose bytes evaluation never reads.
            uint256 descLength = Be16.readUnchecked(policy, PF.POLICY_DESC_LENGTH_OFFSET);
            uint256 groupCountOffset = PF.POLICY_HEADER_PREFIX + descLength;
            uint8 groups = _byteAt(policy, groupCountOffset);

            // Evaluate groups with OR semantics: first passing group succeeds.
            uint256 groupOffset = groupCountOffset + PF.POLICY_GROUP_COUNT_SIZE;
            for (uint32 groupIndex = 0; groupIndex < groups; ++groupIndex) {
                // forgefmt: disable-next-item
                (bool groupOk, uint32 failingRuleIndex, uint256 groupEnd) = _evalGroup(
                    policy, baseOffset, callData, groupOffset
                );
                if (groupOk) return (true, 0, 0);
                failingGroup = groupIndex;
                failingRule = failingRuleIndex;
                groupOffset = groupEnd;
            }

            return (false, failingGroup, failingRule);
        }
    }

    /// @dev Evaluates the root group at `groupOffset`. Returns the verdict, the failing rule index (zero when the group
    /// passes), and the offset one past the group's last rule.
    /// @dev Offsets are wire-bounded as in `_evalPolicy`, so no sum in this body can wrap.
    function _evalGroup(
        bytes memory policy,
        uint256 baseOffset,
        bytes calldata callData,
        uint256 groupOffset
    )
        private
        view
        returns (bool groupOk, uint32 failingRule, uint256 groupEnd)
    {
        unchecked {
            uint16 ruleCount = Be16.readUnchecked(policy, groupOffset + PF.GROUP_RULECOUNT_OFFSET);
            // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: `groupSize`.
            uint32 groupSize = uint32(bytes4(LibBytes.load(policy, groupOffset + PF.GROUP_SIZE_OFFSET)));
            groupEnd = groupOffset + PF.GROUP_HEADER_SIZE + groupSize;

            uint256 ruleOffset = groupOffset + PF.GROUP_HEADER_SIZE;
            for (uint32 ruleIndex = 0; ruleIndex < ruleCount; ++ruleIndex) {
                uint16 ruleSize = Be16.readUnchecked(policy, ruleOffset);
                if (!_evalRule(policy, baseOffset, callData, ruleOffset)) return (false, ruleIndex, groupEnd);

                ruleOffset += ruleSize;
            }

            return (true, 0, groupEnd);
        }
    }

    /// @dev Evaluates a root rule. Returns true if rule passes.
    /// @dev Offsets are wire-bounded as in `_evalPolicy`, so no sum in this body can wrap.
    function _evalRule(
        bytes memory policy,
        uint256 baseOffset,
        bytes calldata callData,
        uint256 ruleOffset
    )
        private
        view
        returns (bool)
    {
        unchecked {
            uint8 scope = _byteAt(policy, ruleOffset + PF.RULE_SCOPE_OFFSET);
            if (scope == PF.SCOPE_CALLDATA) return _evalTest(policy, baseOffset, callData, ruleOffset);
            if (scope == PF.SCOPE_CONTEXT) return _evalContextTest(policy, ruleOffset);
            return _evalLoop(policy, baseOffset, callData, ruleOffset);
        }
    }

    /// @dev Evaluates the loop rule at `ruleOffset`, its body against each element of the array its frame resolves.
    /// @dev Offsets are wire-bounded as in `_evalPolicy`, and the element count the frame gives is capped, so no sum
    /// in this body can wrap.
    function _evalLoop(
        bytes memory policy,
        uint256 baseOffset,
        bytes calldata callData,
        uint256 ruleOffset
    )
        private
        view
        returns (bool)
    {
        unchecked {
            bool isUniversal = _byteAt(policy, ruleOffset + PF.RULE_QUANTIFIER_OFFSET) == PF.QUANTIFIER_ALL;
            uint256 depth = _byteAt(policy, ruleOffset + PF.LOOP_DEPTH_OFFSET);
            uint256 hintOffset = ruleOffset + PF.LOOP_DEPTH_OFFSET + PF.RULE_DEPTH_SIZE + depth * PF.PATH_STEP_SIZE;
            uint256 hopCount = _byteAt(policy, hintOffset);
            uint256 hopsOffset = hintOffset + PF.HINT_HEADER_SIZE;
            uint256 frameOffset = hopsOffset + hopCount * PF.HINT_HOP_SIZE;

            uint256 array = baseOffset;
            if (hopCount != 0) {
                array = _chain(policy, callData, baseOffset, hopsOffset, hopCount);
                if (array == INDEX_OUT_OF_BOUNDS) return false;
            }

            // The frame right-aligns to arrayDelta(32) | count(16) | meta(16).
            uint256 frame = uint256(LibBytes.load(policy, frameOffset)) >> (256 - 8 * PF.HINT_FRAME_PREFIX_SIZE);
            uint256 elems = array + (frame >> 32);
            uint256 count = (frame >> 16) & type(uint16).max;

            // A frame declaring no count spans a dynamic array, whose length word precedes its elements.
            if (count == 0) {
                count = uint256(CalldataReader.loadWord(callData, elems));
                elems += 32;
            }
            require(
                count <= PF.MAX_QUANTIFIED_ARRAY_LENGTH, QuantifierLimitExceeded(count, PF.MAX_QUANTIFIED_ARRAY_LENGTH)
            );

            if (count == 0) return isUniversal;

            uint256 bodyOffset = frameOffset + PF.HINT_FRAME_PREFIX_SIZE;
            uint256 elemStride = (frame & PF.HINT_META_STRIDE_MASK) * 32;
            bool elemIsDynamic = frame & PF.HINT_META_ELEM_DYNAMIC != 0;

            // A body rule is a context test or a calldata test, so a lone rule outside the context scope reads calldata.
            uint256 firstRuleOffset = bodyOffset + PF.GROUP_RULECOUNT_SIZE;
            if (
                Be16.readUnchecked(policy, bodyOffset) == 1
                    && _byteAt(policy, firstRuleOffset + PF.RULE_SCOPE_OFFSET) != PF.SCOPE_CONTEXT
            ) {
                // forgefmt: disable-next-item
                return _evalQuantified(
                    policy, callData, firstRuleOffset, elems, count, elemStride, elemIsDynamic, isUniversal
                );
            }

            uint256 ruleCount = Be16.readUnchecked(policy, bodyOffset);
            for (uint256 index = 0; index < count; ++index) {
                uint256 slot = elems + index * elemStride;
                uint256 elem = elemIsDynamic ? _follow(callData, elems, slot) : slot;

                // Universal quantification short-circuits on failure, existential on success.
                bool bodyOk = _evalBody(policy, callData, firstRuleOffset, ruleCount, elem);
                if (bodyOk != isUniversal) return bodyOk;
            }

            return isUniversal; // Universal: all passed, Existential: none passed.
        }
    }

    /// @dev Evaluates the loop body whose one rule is the calldata test at `ruleOffset` against `count` elements from
    /// `elems`.
    /// @dev Offsets are wire-bounded as in `_evalPolicy`, and `count` is capped, so no sum in this body can wrap.
    function _evalQuantified(
        bytes memory policy,
        bytes calldata callData,
        uint256 ruleOffset,
        uint256 elems,
        uint256 count,
        uint256 elemStride,
        bool elemIsDynamic,
        bool isUniversal
    )
        private
        view
        returns (bool)
    {
        unchecked {
            uint256 depth = _byteAt(policy, ruleOffset + PF.RULE_DEPTH_OFFSET);
            uint256 hintOffset = ruleOffset + PF.RULE_PATH_OFFSET + depth * PF.PATH_STEP_SIZE;
            uint256 hopCount = _byteAt(policy, hintOffset);
            uint256 hopsOffset = hintOffset + PF.HINT_HEADER_SIZE;
            uint256 targetOffset = hopsOffset + hopCount * PF.HINT_HOP_SIZE;

            // Every element shares one target type and one operator, so both resolve before iterating. The block and
            // the operator fields behind it right-align to targetDelta(32) | targetMeta(16) | typeCode(8) | opCode(8) |
            // dataLength(16).
            uint256 tail = uint256(LibBytes.load(policy, targetOffset)) >> (256 - 8 * PF.HINT_TARGET_OPERATOR_SIZE);
            uint256 targetBlock = tail >> (8 * (PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE));
            // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the type code.
            uint8 typeCode = uint8(targetBlock);
            uint256 targetDelta = targetBlock >> 24;
            // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the operator code.
            uint8 opCode = uint8(tail >> (8 * PF.RULE_DATALENGTH_SIZE));
            // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: `dataLength`.
            uint16 dataLength = uint16(tail);
            uint256 dataOffset = targetOffset + PF.HINT_TARGET_OPERATOR_SIZE;

            bool hasLength = TypeRule.hasCalldataLength(typeCode);
            uint256 payloadStride = 0;
            uint8 mode = 0;
            uint256 bits = 0;
            uint256 width = 0;
            if (hasLength) payloadStride = _payloadStride(typeCode, targetBlock);
            else (mode, bits, width) = TypeRule.canonicalSpec(typeCode);

            for (uint256 index = 0; index < count; ++index) {
                uint256 slot = elems + index * elemStride;
                uint256 target = elemIsDynamic ? _follow(callData, elems, slot) : slot;
                if (hopCount != 0) target = _chain(policy, callData, target, hopsOffset, hopCount);

                bool elemOk = false;
                if (target != INDEX_OUT_OF_BOUNDS) {
                    target += targetDelta;
                    bytes32 word = CalldataReader.loadWord(callData, target);
                    if (hasLength) {
                        // A dynamic target's chain ends at its payload, so the word there is the declared length.
                        uint256 length = uint256(word);
                        _requireExtent(callData, target, length, payloadStride);
                        // forgefmt: disable-next-item
                        elemOk = _applyOperator(
                            opCode, bytes32(0), length, TypeRule.CANON_RIGHT, TypeRule.LENGTH_WIDTH,
                            policy, dataOffset, dataLength
                        );
                    } else {
                        require(TypeRule.checkCanonical(mode, bits, word), NonCanonicalValue(typeCode, word));
                        elemOk = _applyOperator(opCode, word, 32, mode, width, policy, dataOffset, dataLength);
                    }
                }

                // Universal quantification short-circuits on failure, existential on success.
                if (elemOk != isUniversal) return elemOk;
            }

            return isUniversal; // Universal: all passed, Existential: none passed.
        }
    }

    /// @dev Evaluates the `ruleCount` body rules from `ruleOffset` against the element whose encoding starts at `elem`.
    /// Returns true if every rule passes.
    /// @dev Offsets are wire-bounded as in `_evalPolicy`, so no sum in this body can wrap.
    function _evalBody(
        bytes memory policy,
        bytes calldata callData,
        uint256 ruleOffset,
        uint256 ruleCount,
        uint256 elem
    )
        private
        view
        returns (bool)
    {
        unchecked {
            for (uint256 ruleIndex = 0; ruleIndex < ruleCount; ++ruleIndex) {
                bool ruleOk = _byteAt(policy, ruleOffset + PF.RULE_SCOPE_OFFSET) == PF.SCOPE_CONTEXT
                    ? _evalContextTest(policy, ruleOffset)
                    : _evalTest(policy, elem, callData, ruleOffset);
                if (!ruleOk) return false;
                ruleOffset += Be16.readUnchecked(policy, ruleOffset);
            }
            return true;
        }
    }

    /// @dev Evaluates the calldata test at `ruleOffset` from the starting point whose encoding starts at `base`.
    /// @dev Offsets are wire-bounded as in `_evalPolicy`, so no sum in this body can wrap.
    function _evalTest(
        bytes memory policy,
        uint256 base,
        bytes calldata callData,
        uint256 ruleOffset
    )
        private
        view
        returns (bool)
    {
        unchecked {
            // The hint addresses the target on its own; path bytes are skipped by depth arithmetic.
            uint256 depth = _byteAt(policy, ruleOffset + PF.RULE_DEPTH_OFFSET);
            uint256 hintOffset = ruleOffset + PF.RULE_PATH_OFFSET + depth * PF.PATH_STEP_SIZE;
            uint256 hopCount = _byteAt(policy, hintOffset);
            uint256 hopsOffset = hintOffset + PF.HINT_HEADER_SIZE;
            uint256 targetOffset = hopsOffset + hopCount * PF.HINT_HOP_SIZE;

            uint256 target = base;
            if (hopCount != 0) {
                target = _chain(policy, callData, base, hopsOffset, hopCount);
                if (target == INDEX_OUT_OF_BOUNDS) return false;
            }

            // The block and the operator fields behind it are contiguous, so one load right-aligns:
            // targetDelta(32) | targetMeta(16) | typeCode(8) | opCode(8) | dataLength(16).
            uint256 tail = uint256(LibBytes.load(policy, targetOffset)) >> (256 - 8 * PF.HINT_TARGET_OPERATOR_SIZE);
            uint256 targetBlock = tail >> (8 * (PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE));
            // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the type code.
            uint8 typeCode = uint8(targetBlock);
            target += targetBlock >> 24;

            // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the operator code.
            uint8 opCode = uint8(tail >> (8 * PF.RULE_DATALENGTH_SIZE));
            // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: `dataLength`.
            uint16 dataLength = uint16(tail);
            uint256 dataOffset = targetOffset + PF.HINT_TARGET_OPERATOR_SIZE;
            bytes32 word = CalldataReader.loadWord(callData, target);

            // A dynamic target's chain ends at its payload, so the word there is the declared length.
            if (TypeRule.hasCalldataLength(typeCode)) {
                uint256 length = uint256(word);
                _requireExtent(callData, target, length, _payloadStride(typeCode, targetBlock));
                // forgefmt: disable-next-item
                return _applyOperator(
                    opCode, bytes32(0), length, TypeRule.CANON_RIGHT, TypeRule.LENGTH_WIDTH,
                    policy, dataOffset, dataLength
                );
            }

            // One spec states the target's canonical encoding and how its operands load.
            (uint8 mode, uint256 bits, uint256 width) = TypeRule.canonicalSpec(typeCode);
            require(TypeRule.checkCanonical(mode, bits, word), NonCanonicalValue(typeCode, word));
            return _applyOperator(opCode, word, 32, mode, width, policy, dataOffset, dataLength);
        }
    }

    /// @dev Evaluates the context test at `ruleOffset`.
    /// @dev Offsets are wire-bounded as in `_evalPolicy`, so no sum in this body can wrap.
    function _evalContextTest(bytes memory policy, uint256 ruleOffset) private view returns (bool) {
        unchecked {
            uint16 contextPropertyId = Be16.readUnchecked(policy, ruleOffset + PF.RULE_PATH_OFFSET);
            uint256 opCursor = ruleOffset + PF.RULE_PATH_OFFSET + PF.PROPERTY_ID_SIZE;
            uint8 opCode = _byteAt(policy, opCursor);
            uint256 dataLengthOffset = opCursor + PF.RULE_OPCODE_SIZE;
            uint16 dataLength = Be16.readUnchecked(policy, dataLengthOffset);
            (,, uint256 width) = TypeRule.canonicalSpec(TypeRule.contextPropertyType(contextPropertyId));
            return _applyOperator(
                opCode,
                _readContext(contextPropertyId),
                32,
                TypeRule.CANON_RIGHT,
                width,
                policy,
                dataLengthOffset + PF.RULE_DATALENGTH_SIZE,
                dataLength
            );
        }
    }

    /// @dev Follows `hopCount` hop entries from `base`. Returns the calldata offset that the entries reach, or
    /// `INDEX_OUT_OF_BOUNDS` when an element hop's index is at or past a dynamic array's length.
    /// @dev Offsets stay clear of wrapping throughout: every field added to a base is bounded by its wire width.
    /// Therefore only the sums that add a calldata-supplied word can reach the top of the range, and each of those
    /// sums is guarded first. A returned base can lie past the calldata length. The load that reads at or past the
    /// calldata length rejects that base.
    function _chain(
        bytes memory policy,
        bytes calldata callData,
        uint256 base,
        uint256 hopsOffset,
        uint256 hopCount
    )
        private
        pure
        returns (uint256)
    {
        unchecked {
            for (uint256 i = 0; i < hopCount; ++i) {
                // A hop right-aligns to delta(32) | index(16) | meta(16), so the meta masks apply directly.
                uint256 hop =
                    uint256(LibBytes.load(policy, hopsOffset + i * PF.HINT_HOP_SIZE)) >> (256 - 8 * PF.HINT_HOP_SIZE);
                uint256 index = (hop >> 16) & type(uint16).max;

                if (index == PF.HINT_NO_INDEX) {
                    base = _follow(callData, base, base + (hop >> 32));
                    continue;
                }

                uint256 elems = base;
                if (hop & PF.HINT_META_DYNAMIC_ARRAY != 0) {
                    if (index >= uint256(CalldataReader.loadWord(callData, elems))) return INDEX_OUT_OF_BOUNDS;
                    elems += 32;
                }

                uint256 slot = elems + index * (hop & PF.HINT_META_STRIDE_MASK) * 32;
                base = hop & PF.HINT_META_ELEM_DYNAMIC != 0 ? _follow(callData, elems, slot) : slot;
            }

            return base;
        }
    }

    /// @dev Returns `from` advanced by the offset word at `at`.
    /// @dev Requires `from <= at`, which makes the load's own bounds check cover `from` as well and leaves the
    /// comparison below sufficient to rule out a wrapping sum.
    function _follow(bytes calldata callData, uint256 from, uint256 at) private pure returns (uint256) {
        uint256 offset = uint256(CalldataReader.loadWord(callData, at));
        require(offset <= callData.length - from, CalldataReader.CalldataOutOfBounds());
        unchecked {
            return from + offset;
        }
    }

    /// @dev Returns the byte stride between the payload items a declared length counts.
    function _payloadStride(uint8 typeCode, uint256 targetBlock) private pure returns (uint256) {
        if (typeCode != TypeCode.DYNAMIC_ARRAY) return 1;
        return ((targetBlock >> 8) & PF.HINT_META_STRIDE_MASK) * 32;
    }

    /// @dev Requires the payload of `length` items of `stride` bytes each to lie within calldata.
    /// @dev Requires `target + 32 <= callData.length`, which the load of the length word establishes.
    function _requireExtent(bytes calldata callData, uint256 target, uint256 length, uint256 stride) private pure {
        // Dividing the room that remains keeps the extent clear of a product that could wrap.
        uint256 room = callData.length - (target + 32);
        require(stride == 0 || length <= room / stride, CalldataReader.CalldataOutOfBounds());
    }

    /// @dev Reads the byte at `offset`. The caller frames `offset` within the buffer.
    function _byteAt(bytes memory data, uint256 offset) private pure returns (uint8) {
        // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: one byte.
        return uint8(bytes1(LibBytes.load(data, offset)));
    }

    /// @dev Applies the operator to `value`, a word whose type has alignment `mode` and values of `width` bytes, or to
    /// `valueLength` for a length comparison. The operator data lies in `policy[dataOffset : dataOffset+dataLength)`.
    /// @dev Assumes dataLength matches the operator's expected payload size.
    function _applyOperator(
        uint8 opCode,
        bytes32 value,
        uint256 valueLength,
        uint8 mode,
        uint256 width,
        bytes memory policy,
        uint256 dataOffset,
        uint16 dataLength
    )
        private
        view
        returns (bool)
    {
        uint8 base = opCode & OpCode.COMPARISON_MASK;
        bool isSigned = mode == TypeRule.CANON_SIGNED;
        // Every comparison but IN reads its first operand here, a context property's value or a constant; a range
        // reads its upper bound one width on.
        bytes32 operand;
        if (opCode & (OpCode.SOURCE_CONTEXT << OpCode.SOURCE_SHIFT) == 0) {
            operand = TypeRule.loadOperand(LibBytes.load(policy, dataOffset), mode, width);
        } else {
            operand = _readContext(Be16.readUnchecked(policy, dataOffset));
        }
        bool result;

        // forgefmt: disable-next-item
        if (base == OpCode.EQ) {
            result = value == operand;

        } else if (base == OpCode.GT) {
            result = isSigned
                ? int256(uint256(value)) > int256(uint256(operand))
                : uint256(value) > uint256(operand);

        } else if (base == OpCode.LT) {
            result = isSigned
                ? int256(uint256(value)) < int256(uint256(operand))
                : uint256(value) < uint256(operand);

        } else if (base == OpCode.GTE) {
            result = isSigned
                ? int256(uint256(value)) >= int256(uint256(operand))
                : uint256(value) >= uint256(operand);

        } else if (base == OpCode.LTE) {
            result = isSigned
                ? int256(uint256(value)) <= int256(uint256(operand))
                : uint256(value) <= uint256(operand);

        } else if (base == OpCode.BETWEEN) {
            bytes32 upper = TypeRule.loadOperand(LibBytes.load(policy, dataOffset + width), mode, width);
            result = isSigned
                ? int256(uint256(value)) >= int256(uint256(operand))
                    && int256(uint256(value)) <= int256(uint256(upper))
                : uint256(value) >= uint256(operand) && uint256(value) <= uint256(upper);

        } else if (base == OpCode.IN) {
            result = _checkIn(value, mode, width, policy, dataOffset, dataLength);

        } else if (base == OpCode.BITMASK_ALL) {
            result = (value & operand) == operand;

        } else if (base == OpCode.BITMASK_ANY) {
            result = (value & operand) != bytes32(0);

        } else if (base == OpCode.BITMASK_NONE) {
            result = (value & operand) == bytes32(0);

        } else if (base == OpCode.LENGTH_EQ) {
            result = valueLength == uint256(operand);

        } else if (base == OpCode.LENGTH_GT) {
            result = valueLength > uint256(operand);

        } else if (base == OpCode.LENGTH_LT) {
            result = valueLength < uint256(operand);

        } else if (base == OpCode.LENGTH_GTE) {
            result = valueLength >= uint256(operand);

        } else if (base == OpCode.LENGTH_LTE) {
            result = valueLength <= uint256(operand);

        } else {
            // The comparison is defined, so the last one left is LENGTH_BETWEEN.
            uint256 upper = uint256(TypeRule.loadOperand(LibBytes.load(policy, dataOffset + width), mode, width));
            result = valueLength >= uint256(operand) && valueLength <= upper;
        }

        return (opCode & OpCode.NOT) != 0 ? !result : result;
    }

    /// @dev Checks if `value` is in the set of operands. Members are packed as consecutive operands of `width` bytes,
    /// strictly ascending as their bytes compared unsigned, which orders them as their loaded words. The search
    /// compares the bytes `value` loads from, so each probe is one read and one shift. Binary search adapted from
    /// Solady LibSort._searchSorted: 1-indexed search over the packed operands, where adjBase mimics the array length
    /// slot.
    /// Unsigned-only, membership-only — the signed bias and index-return of the original are dropped. Assumes
    /// dataLength > 0 and dataLength % width == 0.
    function _checkIn(
        bytes32 value,
        uint8 mode,
        uint256 width,
        bytes memory policy,
        uint256 dataOffset,
        uint16 dataLength
    )
        private
        pure
        returns (bool found)
    {
        uint256 shift;
        uint256 key;
        unchecked {
            shift = 256 - 8 * width;
            // A canonical word holds its member's bytes high for a left-aligned type and low for every other type,
            // above a sign extension for a signed one.
            key = mode == TypeRule.CANON_LEFT ? uint256(value) >> shift : uint256(value) & (type(uint256).max >> shift);
        }
        assembly ("memory-safe") {
            // Binary search over 1-indexed positions, so the base is biased down one member.
            let adjBase := sub(add(add(policy, 32), dataOffset), width)
            let l := 1
            let h := div(dataLength, width)
            let t := 0
            let mid := 0
            for { } 1 { } {
                mid := shr(1, add(l, h))
                t := shr(shift, mload(add(adjBase, mul(width, mid))))
                if or(gt(l, h), eq(t, key)) { break }
                if iszero(gt(key, t)) {
                    h := add(mid, not(0))
                    continue
                }
                l := add(mid, 1)
            }
            found := and(eq(t, key), iszero(iszero(mid)))
        }
    }

    /// @dev Reads context property `contextPropertyId`. An ID past `CTX_MAX` reads zero.
    function _readContext(uint256 contextPropertyId) private view returns (bytes32 word) {
        assembly ("memory-safe") {
            switch contextPropertyId
            // CTX_MSG_SENDER
            case 0x0000 { word := caller() }
            // CTX_MSG_VALUE
            case 0x0001 { word := callvalue() }
            // CTX_BLOCK_TIMESTAMP
            case 0x0002 { word := timestamp() }
            // CTX_BLOCK_NUMBER
            case 0x0003 { word := number() }
            // CTX_CHAIN_ID
            case 0x0004 { word := chainid() }
            // CTX_TX_ORIGIN
            case 0x0005 { word := origin() }
            // CTX_BASE_FEE
            case 0x0006 { word := basefee() }
            // CTX_GAS_PRICE
            case 0x0007 { word := gasprice() }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Be16 } from "./Be16.sol";

import { CalldataReader } from "./CalldataReader.sol";
import { OpCode } from "./OpCode.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";

import { LibBytes } from "solady/utils/LibBytes.sol";

/// @title PolicyEnforcer
/// @notice Enforces that `callData` complies with a `policy`.
library PolicyEnforcer {
    /*/////////////////////////////////////////////////////////////////////////
                                        ERRORS
    ////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when policy validation fails.
    error PolicyViolation(uint32 groupIndex, uint32 ruleIndex);

    /// @notice Thrown when the function selector does not match the policy header.
    error SelectorMismatch(bytes4 expected, bytes4 actual);

    /// @notice Thrown when an unknown operator code is encountered.
    error UnknownOperator(uint8 opCode);

    /// @notice Thrown when an unknown context property ID is requested.
    error UnknownContextProperty(uint16 contextId);

    /// @notice Thrown when calldata is too short to contain a selector.
    error MissingSelector();

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
    /// @dev Requires a structurally validated policy blob; behavior on an unvalidated blob is undefined.
    /// @param policy The policy blob with embedded descriptor.
    /// @param callData The calldata to validate.
    function enforce(bytes memory policy, bytes calldata callData) internal view {
        (bool ok, uint32 failedGroup, uint32 failedRule) = _evalPolicy(policy, callData);
        if (!ok) revert PolicyViolation(failedGroup, failedRule);
    }

    /// @notice Returns true if `callData` complies with `policy`.
    /// @dev Requires a structurally validated policy blob; behavior on an unvalidated blob is undefined.
    /// Reverts on abort violations and integrity errors; returns false for group-local violations.
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
    /// @dev Offsets are wire-bounded: a blob offset never exceeds the buffer length and every field
    /// added to one is bounded by its own wire width, so no sum in this body can wrap.
    function _evalPolicy(
        bytes memory policy,
        bytes calldata callData
    )
        private
        view
        returns (bool ok, uint32 failingGroup, uint32 failingRule)
    {
        unchecked {
            // Parse the policy header once; every later field read reuses these offsets.
            uint8 policyHeader = _byteAt(policy, PF.POLICY_HEADER_OFFSET);

            // Determine base offset and validate selector if present.
            uint256 baseOffset;
            if (policyHeader & PF.FLAG_NO_SELECTOR == 0) {
                bytes4 expectedSelector = bytes4(LibBytes.load(policy, PF.POLICY_SELECTOR_OFFSET));
                require(callData.length >= PF.POLICY_SELECTOR_SIZE, MissingSelector());
                bytes4 actualSelector = bytes4(LibBytes.loadCalldata(callData, 0));
                require(expectedSelector == actualSelector, SelectorMismatch(expectedSelector, actualSelector));
                baseOffset = PF.POLICY_SELECTOR_SIZE;
            }

            // Groups sit past the embedded descriptor, whose bytes evaluation never reads.
            uint256 descLength = Be16.readUnchecked(policy, PF.POLICY_DESC_LENGTH_OFFSET);
            uint256 groupCountOffset = PF.POLICY_HEADER_PREFIX + descLength;
            uint8 groups = _byteAt(policy, groupCountOffset);
            if (groups == 0) return (false, 0, 0);

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

    /// @dev Evaluates the group at `groupOffset`. Returns the verdict, the failing rule index
    /// (zero when the group passes), and the offset one past the group's last rule.
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

    /// @dev Evaluates a single rule. Returns true if rule passes.
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
            uint256 pathStart = ruleOffset + PF.RULE_PATH_OFFSET;

            if (_byteAt(policy, ruleOffset + PF.RULE_SCOPE_OFFSET) == PF.SCOPE_CONTEXT) {
                bytes32 value = _readContext(Be16.readUnchecked(policy, pathStart));
                // forgefmt: disable-next-item
                (uint8 contextOpCode, uint256 contextDataOffset, uint16 contextDataLength) = _operatorAt(
                    policy, pathStart + PF.PATH_STEP_SIZE
                );
                // forgefmt: disable-next-item
                return _applyOperator(
                    contextOpCode, value, 32, TypeCode.UINT256, policy, contextDataOffset, contextDataLength
                );
            }

            // The hint addresses the target on its own; path bytes are skipped by depth arithmetic.
            uint256 depth = _byteAt(policy, ruleOffset + PF.RULE_DEPTH_OFFSET);
            uint256 hintOffset = pathStart + depth * PF.PATH_STEP_SIZE;
            uint8 header = _byteAt(policy, hintOffset);
            uint256 hopCount = header & PF.HINT_HOP_COUNT_MASK;
            uint8 kind = header >> PF.HINT_KIND_SHIFT;
            uint256 hopsOffset = hintOffset + PF.HINT_HEADER_SIZE;

            return kind == PF.HINT_KIND_NONE
                ? _evalUnquantified(policy, baseOffset, callData, hopsOffset, hopCount)
                : _evalQuantified(policy, baseOffset, callData, hopsOffset, hopCount, kind);
        }
    }

    /// @dev Evaluates the rule whose hop chain reaches a single target.
    /// @dev Offsets are wire-bounded as in `_evalPolicy`, so no sum in this body can wrap.
    function _evalUnquantified(
        bytes memory policy,
        uint256 baseOffset,
        bytes calldata callData,
        uint256 hopsOffset,
        uint256 hopCount
    )
        private
        view
        returns (bool)
    {
        unchecked {
            uint256 targetOffset = hopsOffset + hopCount * PF.HINT_HOP_SIZE;
            uint256 target = hopCount == 0 ? baseOffset : _chain(policy, callData, baseOffset, hopsOffset, hopCount);

            // The block and the operator fields behind it are contiguous, so one load right-aligns
            // targetDelta(32) | targetMeta(16) | typeCode(8) | opCode(8) | dataLength(16).
            uint256 tail = uint256(LibBytes.load(policy, targetOffset)) >> (256 - 8 * PF.HINT_TARGET_OPERATOR_SIZE);
            uint256 targetBlock = tail >> (8 * (PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE));
            // forge-lint: disable-next-line(unsafe-typecast) the low byte of the block is the type code.
            uint8 typeCode = uint8(targetBlock);
            target += targetBlock >> 24;

            // forge-lint: disable-next-line(unsafe-typecast) the operator code is one byte of the tail.
            uint8 opCode = uint8(tail >> (8 * PF.RULE_DATALENGTH_SIZE));
            // forge-lint: disable-next-line(unsafe-typecast) the data length is the tail's low two bytes.
            uint16 dataLength = uint16(tail);
            uint256 dataOffset = targetOffset + PF.HINT_TARGET_OPERATOR_SIZE;
            bytes32 word = CalldataReader.loadWord(callData, target);

            // A dynamic target's chain ends at its payload, so the word there is the declared length.
            if (TypeRule.hasCalldataLength(typeCode)) {
                uint256 length = uint256(word);
                _requireExtent(callData, target, length, _payloadStride(typeCode, targetBlock));
                return _applyOperator(opCode, bytes32(0), length, typeCode, policy, dataOffset, dataLength);
            }

            require(TypeRule.isCanonical(word, typeCode), NonCanonicalValue(typeCode, word));
            return _applyOperator(opCode, word, 32, typeCode, policy, dataOffset, dataLength);
        }
    }

    /// @dev Evaluates the rule whose frame iterates the elements of one array.
    /// @dev Offsets are wire-bounded as in `_evalPolicy`, and the element count the frame yields is
    /// capped, so no sum in this body can wrap.
    function _evalQuantified(
        bytes memory policy,
        uint256 baseOffset,
        bytes calldata callData,
        uint256 hopsOffset,
        uint256 hopCount,
        uint8 kind
    )
        private
        view
        returns (bool)
    {
        unchecked {
            uint256 frameOffset = hopsOffset + hopCount * PF.HINT_HOP_SIZE;
            // The frame prefix right-aligns to arrayDelta(32) | count(16) | meta(16).
            uint256 frame = uint256(LibBytes.load(policy, frameOffset)) >> (256 - 8 * PF.HINT_FRAME_PREFIX_SIZE);

            uint256 elems = _chain(policy, callData, baseOffset, hopsOffset, hopCount) + (frame >> 32);
            uint256 count = (frame >> 16) & type(uint16).max;

            // A frame declaring no count spans a dynamic array, whose length word precedes its elements.
            if (count == 0) {
                count = uint256(CalldataReader.loadWord(callData, elems));
                elems += 32;
            }
            require(
                count <= PF.MAX_QUANTIFIED_ARRAY_LENGTH, QuantifierLimitExceeded(count, PF.MAX_QUANTIFIED_ARRAY_LENGTH)
            );

            bool isUniversal = kind == PF.HINT_KIND_ALL;
            if (count == 0) return isUniversal;

            uint256 suffixHeaderOffset = frameOffset + PF.HINT_FRAME_PREFIX_SIZE;
            uint256 suffixHopCount = _byteAt(policy, suffixHeaderOffset) & PF.HINT_HOP_COUNT_MASK;
            uint256 suffixHops = suffixHeaderOffset + PF.HINT_HEADER_SIZE;
            uint256 targetOffset = suffixHops + suffixHopCount * PF.HINT_HOP_SIZE;

            // Every element shares one target type and one operator, so both resolve before iterating.
            // The target block right-aligns to targetDelta(32) | targetMeta(16) | typeCode(8).
            uint256 targetBlock = uint256(LibBytes.load(policy, targetOffset)) >> (256 - 8 * PF.HINT_TARGET_SIZE);
            // forge-lint: disable-next-line(unsafe-typecast) the low byte of the block is the type code.
            uint8 typeCode = uint8(targetBlock);
            uint256 targetDelta = targetBlock >> 24;
            // forgefmt: disable-next-item
            (uint8 opCode, uint256 dataOffset, uint16 dataLength) = _operatorAt(
                policy, targetOffset + PF.HINT_TARGET_SIZE
            );

            bool hasLength = TypeRule.hasCalldataLength(typeCode);
            uint256 payloadStride;
            uint8 canonMode;
            uint256 canonBits;
            if (hasLength) {
                payloadStride = _payloadStride(typeCode, targetBlock);
            } else {
                // Every element shares the target's declared type, so its encoding resolves once.
                (canonMode, canonBits) = TypeRule.canonicalSpec(typeCode);
            }

            uint256 elemStride = (frame & PF.HINT_META_STRIDE_MASK) * 32;
            bool elemIsDynamic = frame & PF.HINT_META_ELEM_DYNAMIC != 0;

            for (uint256 index = 0; index < count; ++index) {
                uint256 slot = elems + index * elemStride;
                uint256 elem = elemIsDynamic ? _follow(callData, elems, slot) : slot;
                uint256 base = suffixHopCount == 0 ? elem : _chain(policy, callData, elem, suffixHops, suffixHopCount);
                uint256 target = base + targetDelta;
                bytes32 word = CalldataReader.loadWord(callData, target);

                bool elemResult;
                if (hasLength) {
                    uint256 length = uint256(word);
                    _requireExtent(callData, target, length, payloadStride);
                    elemResult = _applyOperator(opCode, bytes32(0), length, typeCode, policy, dataOffset, dataLength);
                } else {
                    require(TypeRule.checkCanonical(canonMode, canonBits, word), NonCanonicalValue(typeCode, word));
                    elemResult = _applyOperator(opCode, word, 32, typeCode, policy, dataOffset, dataLength);
                }

                // Universal quantification short-circuits on failure, existential on success.
                if (elemResult != isUniversal) return elemResult;
            }

            return isUniversal; // Universal: all passed, Existential: none passed.
        }
    }

    /// @dev Follows `hopCount` hop entries from `base` and returns the calldata offset they reach.
    /// @dev Offsets stay clear of wrapping throughout: a resolved base never exceeds the calldata
    /// length, and every field added to one is bounded by its wire width, so only the sums that add
    /// a calldata-supplied word can reach the top of the range and each of those is guarded first.
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
                    uint256 length = uint256(CalldataReader.loadWord(callData, elems));
                    require(index < length, CalldataReader.ArrayIndexOutOfBounds(index, length));
                    elems += 32;
                }

                uint256 slot = elems + index * (hop & PF.HINT_META_STRIDE_MASK) * 32;
                base = hop & PF.HINT_META_ELEM_DYNAMIC != 0 ? _follow(callData, elems, slot) : slot;
            }

            return base;
        }
    }

    /// @dev Returns `from` advanced by the offset word at `at`.
    /// @dev Requires `from <= at`, which makes the load's own bounds check cover `from` as well and
    /// leaves the comparison below sufficient to rule out a wrapping sum.
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

    /// @dev Reads the operator fields that follow a rule's hint block.
    function _operatorAt(
        bytes memory policy,
        uint256 opCursor
    )
        private
        pure
        returns (uint8 opCode, uint256 dataOffset, uint16 dataLength)
    {
        opCode = _byteAt(policy, opCursor);
        uint256 dataLengthOffset = opCursor + PF.RULE_OPCODE_SIZE;
        dataLength = Be16.readUnchecked(policy, dataLengthOffset);
        dataOffset = dataLengthOffset + PF.RULE_DATALENGTH_SIZE;
    }

    /// @dev Reads the byte at `offset`. The caller frames `offset` within the buffer.
    function _byteAt(bytes memory data, uint256 offset) private pure returns (uint8) {
        return uint8(bytes1(LibBytes.load(data, offset)));
    }

    /// @dev Applies operator to `value` using operator payload in `policy[dataOffset : dataOffset+dataLength)`.
    /// @dev Assumes dataLength matches the operator's expected payload size.
    function _applyOperator(
        uint8 opCode,
        bytes32 value,
        uint256 valueLength,
        uint8 typeCode,
        bytes memory policy,
        uint256 dataOffset,
        uint16 dataLength
    )
        private
        view
        returns (bool)
    {
        uint8 base = opCode & ~OpCode.NOT;
        bool result;

        // forgefmt: disable-next-item
        if (base == OpCode.EQ) {
            result = value == LibBytes.load(policy, dataOffset);

        } else if (base == OpCode.GT) {
            bytes32 operandRaw = LibBytes.load(policy, dataOffset);
            result = TypeRule.isSigned(typeCode)
                ? int256(uint256(value)) > int256(uint256(operandRaw))
                : uint256(value) > uint256(operandRaw);

        } else if (base == OpCode.LT) {
            bytes32 operandRaw = LibBytes.load(policy, dataOffset);
            result = TypeRule.isSigned(typeCode)
                ? int256(uint256(value)) < int256(uint256(operandRaw))
                : uint256(value) < uint256(operandRaw);

        } else if (base == OpCode.GTE) {
            bytes32 operandRaw = LibBytes.load(policy, dataOffset);
            result = TypeRule.isSigned(typeCode)
                ? int256(uint256(value)) >= int256(uint256(operandRaw))
                : uint256(value) >= uint256(operandRaw);

        } else if (base == OpCode.LTE) {
            bytes32 operandRaw = LibBytes.load(policy, dataOffset);
            result = TypeRule.isSigned(typeCode)
                ? int256(uint256(value)) <= int256(uint256(operandRaw))
                : uint256(value) <= uint256(operandRaw);

        } else if (base == OpCode.BETWEEN) {
            bytes32 lowerRaw;
            bytes32 upperRaw;
            assembly ("memory-safe") {
                let ptr := add(add(policy, 32), dataOffset)
                lowerRaw := mload(ptr)
                upperRaw := mload(add(ptr, 32))
            }

            if (TypeRule.isSigned(typeCode)) {
                int256 val = int256(uint256(value));
                int256 lower = int256(uint256(lowerRaw));
                int256 upper = int256(uint256(upperRaw));
                result = val >= lower && val <= upper;
            } else {
                uint256 val = uint256(value);
                uint256 lower = uint256(lowerRaw);
                uint256 upper = uint256(upperRaw);
                result = val >= lower && val <= upper;
            }

        } else if (base == OpCode.IN) {
            result = _checkIn(value, policy, dataOffset, dataLength);

        } else if (base == OpCode.BITMASK_ALL) {
            bytes32 mask = LibBytes.load(policy, dataOffset);
            result = (value & mask) == mask;

        } else if (base == OpCode.BITMASK_ANY) {
            bytes32 mask = LibBytes.load(policy, dataOffset);
            result = (value & mask) != bytes32(0);

        } else if (base == OpCode.BITMASK_NONE) {
            bytes32 mask = LibBytes.load(policy, dataOffset);
            result = (value & mask) == bytes32(0);

        } else if (base == OpCode.LENGTH_EQ) {
            uint256 operand = uint256(LibBytes.load(policy, dataOffset));
            result = valueLength == operand;

        } else if (base == OpCode.LENGTH_GT) {
            uint256 operand = uint256(LibBytes.load(policy, dataOffset));
            result = valueLength > operand;

        } else if (base == OpCode.LENGTH_LT) {
            uint256 operand = uint256(LibBytes.load(policy, dataOffset));
            result = valueLength < operand;

        } else if (base == OpCode.LENGTH_GTE) {
            uint256 operand = uint256(LibBytes.load(policy, dataOffset));
            result = valueLength >= operand;

        } else if (base == OpCode.LENGTH_LTE) {
            uint256 operand = uint256(LibBytes.load(policy, dataOffset));
            result = valueLength <= operand;

        } else if (base == OpCode.LENGTH_BETWEEN) {
            uint256 lower;
            uint256 upper;
            assembly ("memory-safe") {
                let ptr := add(add(policy, 32), dataOffset)
                lower := mload(ptr)
                upper := mload(add(ptr, 32))
            }
            result = valueLength >= lower && valueLength <= upper;

        // Last in the chain so the branch costs nothing on the other operators.
        } else if (base == OpCode.EQ_CTX) {
            uint256 operand = uint256(LibBytes.load(policy, dataOffset));
            // The whole word is checked so a truncating cast cannot alias garbage to a defined ID.
            // forge-lint: disable-next-line(unsafe-typecast) the revert argument is diagnostic only.
            require(operand <= PF.CTX_MAX, UnknownContextProperty(uint16(operand)));
            // forge-lint: disable-next-line(unsafe-typecast) bounded by the check above.
            result = value == _readContext(uint16(operand));

        } else {
            revert UnknownOperator(base);
        }

        return (opCode & OpCode.NOT) != 0 ? !result : result;
    }

    /// @dev Checks if `value` is in the set of operands.
    /// Operands are packed as consecutive sorted 32-byte values.
    /// Uses linear scan for small sets (<=6 elements) and binary search for larger sets.
    /// Binary search adapted from Solady LibSort._searchSorted: 1-indexed search over the
    /// packed operands, where adjBase mimics the array length slot. Unsigned-only,
    /// membership-only — the signed bias and index-return of the original are dropped.
    /// Assumes dataLength > 0 and dataLength % 32 == 0.
    function _checkIn(
        bytes32 value,
        bytes memory policy,
        uint256 dataOffset,
        uint16 dataLength
    )
        private
        pure
        returns (bool found)
    {
        assembly ("memory-safe") {
            let base := add(add(policy, 32), dataOffset)
            // Linear scan for small sets (<=6 elements).
            switch lt(shr(5, dataLength), 7)
            case 1 {
                let end := add(base, dataLength)
                for { let ptr := base } lt(ptr, end) { ptr := add(ptr, 32) } {
                    if eq(value, mload(ptr)) {
                        found := 1
                        break
                    }
                }
            }
            default {
                // Binary search over 1-indexed positions, so the base is biased down one word.
                let adjBase := sub(base, 32)
                let l := 1
                let h := shr(5, dataLength)
                let t := 0
                let mid := 0
                for { } 1 { } {
                    mid := shr(1, add(l, h))
                    t := mload(add(adjBase, shl(5, mid)))
                    if or(gt(l, h), eq(t, value)) { break }
                    if iszero(gt(value, t)) {
                        h := add(mid, not(0))
                        continue
                    }
                    l := add(mid, 1)
                }
                found := and(eq(t, value), iszero(iszero(mid)))
            }
        }
    }

    /// @dev Reads context property by ID.
    function _readContext(uint16 contextPropertyId) private view returns (bytes32 v) {
        assembly ("memory-safe") {
            switch contextPropertyId
            // CTX_MSG_SENDER
            case 0x0000 { v := caller() }
            // CTX_MSG_VALUE
            case 0x0001 { v := callvalue() }
            // CTX_BLOCK_TIMESTAMP
            case 0x0002 { v := timestamp() }
            // CTX_BLOCK_NUMBER
            case 0x0003 { v := number() }
            // CTX_CHAIN_ID
            case 0x0004 { v := chainid() }
            // CTX_TX_ORIGIN
            case 0x0005 { v := origin() }
            // CTX_BASE_FEE
            case 0x0006 { v := basefee() }
            // CTX_GAS_PRICE
            case 0x0007 { v := gasprice() }
            default {
                // Revert with UnknownContextProperty(contextPropertyId).
                mstore(0, 0x33abc51300000000000000000000000000000000000000000000000000000000)
                mstore(4, contextPropertyId)
                revert(0, 36)
            }
        }
    }
}

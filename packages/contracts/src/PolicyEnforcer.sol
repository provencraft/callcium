// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Be16 } from "./Be16.sol";

import { CalldataReader } from "./CalldataReader.sol";
import { Descriptor } from "./Descriptor.sol";
import { DescriptorFormat as DF } from "./DescriptorFormat.sol";
import { OpCode } from "./OpCode.sol";
import { OpRule } from "./OpRule.sol";
import { Path } from "./Path.sol";
import { Policy } from "./Policy.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";

import { LibBytes } from "solady/utils/LibBytes.sol";

/// @title PolicyEnforcer
/// @notice Enforces that `callData` complies with a `policy`.
library PolicyEnforcer {
    /// @dev Evaluation state passed between helper functions to reduce stack depth.
    struct EvalState {
        /// The policy blob being evaluated.
        bytes policy;
        /// The descriptor extracted from policy.
        bytes desc;
        /// CalldataReader configuration with base offset.
        CalldataReader.Config config;
    }

    /// @dev Pre-parsed rule fields to avoid redundant policy blob reads.
    struct RuleView {
        /// The rule scope (context or calldata).
        uint8 scope;
        /// The path depth.
        uint8 depth;
        /// The operator code (may include NOT flag).
        uint8 opCode;
        /// Byte offset where the path array starts within the policy blob.
        uint256 pathStart;
        /// Byte offset of the operator data payload within the policy blob.
        uint256 dataOffset;
        /// Length of the operator data payload.
        uint16 dataLength;
    }

    /// @dev Quantifier evaluation parameters.
    struct QParams {
        /// The operator code without the NOT flag.
        uint8 opBase;
        /// The full operator code (may include NOT flag).
        uint8 opCode;
        /// Length of the operator data payload.
        uint16 dataLength;
        /// Offset of the operator data payload within the policy blob.
        uint256 dataOffset;
        /// True if the path continues past the quantifier.
        bool hasSuffix;
        /// True for ALL/ALL_OR_EMPTY, false for ANY.
        bool isUniversal;
    }

    /// @dev Mutable state for the quantifier iteration loop.
    struct QLoopState {
        /// The loaded value (32 bytes for scalars, zero for dynamic types).
        bytes32 value;
        /// Length in bytes of the loaded value.
        uint256 valueLength;
        /// The TypeCode of the resolved value.
        uint8 typeCode;
    }

    /// @dev Path scratch capacity in steps (be16 per step). Must equal `PF.MAX_PATH_DEPTH`;
    /// a local literal is required because cross-library constants cannot size fixed arrays.
    uint8 internal constant MAX_PATH_DEPTH = 32;

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

    /// @notice Thrown when nested quantifiers are used (unsupported).
    error NestedQuantifiersUnsupported();

    /// @notice Thrown when array exceeds max length for quantified iteration.
    error QuantifierLimitExceeded(uint256 length, uint256 maxLength);

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
    function _evalPolicy(
        bytes memory policy,
        bytes calldata callData
    )
        private
        view
        returns (bool ok, uint32 failingGroup, uint32 failingRule)
    {
        // Determine base offset and validate selector if present.
        uint32 baseOffset;
        if (Policy.isSelectorless(policy)) {
            baseOffset = 0;
        } else {
            bytes4 expectedSelector = Policy.selector(policy);
            require(callData.length >= PF.POLICY_SELECTOR_SIZE, MissingSelector());
            bytes4 actualSelector = bytes4(LibBytes.loadCalldata(callData, 0));
            require(expectedSelector == actualSelector, SelectorMismatch(expectedSelector, actualSelector));
            baseOffset = uint32(PF.POLICY_SELECTOR_SIZE);
        }

        // Extract descriptor from policy and initialize evaluation state.
        EvalState memory state = EvalState({
            policy: policy, desc: Policy.descriptor(policy), config: CalldataReader.Config({ baseOffset: baseOffset })
        });

        // Validate the descriptor version once; locateSteps skips this check per rule.
        uint8 formatVersion = Descriptor.version(state.desc);
        require(formatVersion == DF.VERSION, Descriptor.UnsupportedVersion(formatVersion));

        uint8 groups = Policy.groupCount(policy);
        if (groups == 0) return (false, 0, 0);

        // Evaluate groups with OR semantics: first passing group succeeds.
        uint256 groupOffset = Policy.groupAt(policy, 0);
        for (uint32 groupIndex; groupIndex < groups; ++groupIndex) {
            (bool groupOk, uint32 failingRuleIndex, uint256 groupEnd) = _evalGroup(state, callData, groupOffset);
            if (groupOk) return (true, 0, 0);
            failingGroup = groupIndex;
            failingRule = failingRuleIndex;
            groupOffset = groupEnd;
        }

        return (false, failingGroup, failingRule);
    }

    /// @dev Evaluates the group at `groupOffset`. Returns the verdict, the failing rule index
    /// (zero when the group passes), and the offset one past the group's last rule.
    function _evalGroup(
        EvalState memory state,
        bytes calldata callData,
        uint256 groupOffset
    )
        private
        view
        returns (bool groupOk, uint32 failingRule, uint256 groupEnd)
    {
        uint32 groupSize = Policy.groupSize(state.policy, groupOffset);
        uint16 ruleCount = Policy.ruleCount(state.policy, groupOffset);
        groupEnd = groupOffset + PF.GROUP_HEADER_SIZE + groupSize;

        uint256 ruleOffset = groupOffset + PF.GROUP_HEADER_SIZE;

        for (uint32 ruleIndex; ruleIndex < ruleCount; ++ruleIndex) {
            uint16 ruleSize = Policy.ruleSize(state.policy, ruleOffset);

            bool ruleOk = _evalRule(state, callData, ruleOffset);
            if (!ruleOk) return (false, ruleIndex, groupEnd);

            unchecked {
                ruleOffset += ruleSize;
            }
        }

        require(ruleOffset == groupEnd, Policy.UnexpectedEnd());
        return (true, 0, groupEnd);
    }

    /// @dev Reads all rule fields from the policy blob in a single pass.
    /// Eliminates redundant reads of pathDepth and ruleSize that occur when calling
    /// Policy.scope(), Policy.pathDepth(), Policy.opCode(), and Policy.dataView() individually.
    function _parseRule(bytes memory policy, uint256 ruleOffset) private pure returns (RuleView memory rule) {
        rule.scope = uint8(policy[ruleOffset + PF.RULE_SCOPE_OFFSET]);
        rule.depth = uint8(policy[ruleOffset + PF.RULE_DEPTH_OFFSET]);
        rule.pathStart = ruleOffset + PF.RULE_PATH_OFFSET;

        uint256 opCodeOffset = rule.pathStart + uint256(rule.depth) * PF.PATH_STEP_SIZE;
        rule.opCode = uint8(policy[opCodeOffset]);

        uint256 dataLengthOffset = opCodeOffset + PF.RULE_OPCODE_SIZE;
        rule.dataLength = Be16.readUnchecked(policy, dataLengthOffset);
        rule.dataOffset = dataLengthOffset + PF.RULE_DATALENGTH_SIZE;
    }

    /// @dev Evaluates a single rule. Returns true if rule passes.
    function _evalRule(EvalState memory state, bytes calldata callData, uint256 ruleOffset)
        private
        view
        returns (bool)
    {
        RuleView memory rule = _parseRule(state.policy, ruleOffset);
        require(rule.depth <= MAX_PATH_DEPTH, CalldataReader.PathTooDeep(rule.depth, MAX_PATH_DEPTH));

        uint8 opBase = rule.opCode & ~OpCode.NOT;

        bytes32 value;
        uint256 valueLength;
        uint8 typeCode;

        if (rule.scope == PF.SCOPE_CALLDATA) {
            bool isQuantified;
            bool quantifiedResult;
            // forgefmt: disable-next-item
            (value, valueLength, typeCode, isQuantified, quantifiedResult) = _loadCalldataValue(
                state, callData, rule, opBase
            );

            if (isQuantified) return quantifiedResult;
        } else {
            (value, valueLength, typeCode) = _loadContextValue(state.policy, rule);
        }

        return _applyOperator(rule.opCode, value, valueLength, typeCode, state.policy, rule.dataOffset, rule.dataLength);
    }

    /// @dev Loads a value from calldata at the path specified by the rule.
    /// @return value The loaded value (32 bytes for scalars, zero for dynamic types).
    /// @return valueLength Length in bytes (32 for scalars, actual length for dynamic).
    /// @return typeCode The type code of the resolved value, used for signed comparison.
    /// @return isQuantified True if the path contains a quantifier.
    /// @return quantifiedResult The result of quantifier evaluation if isQuantified is true.
    function _loadCalldataValue(
        EvalState memory state,
        bytes calldata callData,
        RuleView memory rule,
        uint8 opBase
    )
        private
        pure
        returns (bytes32 value, uint256 valueLength, uint8 typeCode, bool isQuantified, bool quantifiedResult)
    {
        uint8 quantifierIndex;
        uint16 quantifierType;

        // Scan the rule's path steps for a quantifier.
        for (uint256 i; i < rule.depth; ++i) {
            uint16 step = Be16.readUnchecked(state.policy, rule.pathStart + i * 2);

            if (step >= Path.ANY) {
                require(quantifierType == 0, NestedQuantifiersUnsupported());
                // forge-lint: disable-next-line(unsafe-typecast) i <= MAX_PATH_DEPTH (32)
                quantifierIndex = uint8(i);
                quantifierType = step;
            }
        }

        // Quantified path: delegate to specialized handler.
        if (quantifierType != 0) {
            quantifiedResult = _evalQuantifiedPath(state, callData, rule, quantifierIndex, quantifierType, opBase);
            return (bytes32(0), 0, 0, true, quantifiedResult);
        }

        // Resolve the path to a calldata location, reading steps directly from the policy blob.
        CalldataReader.Location memory loc =
            CalldataReader.locateSteps(state.desc, callData, state.policy, rule.pathStart, rule.depth, state.config);

        // Extract type code for signed integer comparison in _applyOperator.
        typeCode = loc.typeCode;

        // Load the value: scalars (32-byte static) get the actual value,
        // dynamic types (bytes, string, arrays) get length only.
        if (!loc.isDynamic && loc.staticSize == 32) {
            value = TypeRule.canonicalize(CalldataReader.loadScalar(loc, callData), typeCode);
            valueLength = 32;
        } else {
            require(!OpRule.isValueOp(opBase), CalldataReader.NotScalar(typeCode));
            value = bytes32(0);
            valueLength = CalldataReader.loadSlice(state.desc, loc, callData).length;
        }
    }

    /// @dev Evaluates a quantified path by iterating array elements.
    function _evalQuantifiedPath(
        EvalState memory state,
        bytes calldata callData,
        RuleView memory rule,
        uint8 quantifierIndex,
        uint16 quantifierType,
        uint8 opBase
    )
        private
        pure
        returns (bool)
    {
        // Locate the array via the path prefix before the quantifier, then take its shape.
        CalldataReader.Location memory arrayLoc = CalldataReader.locateSteps(
            state.desc, callData, state.policy, rule.pathStart, quantifierIndex, state.config
        );
        CalldataReader.ArrayShape memory shape = CalldataReader.arrayShape(state.desc, callData, arrayLoc);

        require(
            shape.length <= PF.MAX_QUANTIFIED_ARRAY_LENGTH,
            QuantifierLimitExceeded(shape.length, PF.MAX_QUANTIFIED_ARRAY_LENGTH)
        );

        // Empty array semantics: ALL_OR_EMPTY (vacuous truth) vs ANY/ALL (false).
        if (shape.length == 0) return quantifierType == Path.ALL_OR_EMPTY;

        QParams memory params;
        params.opBase = opBase;
        params.hasSuffix = rule.depth > quantifierIndex + 1;
        params.isUniversal = (quantifierType == Path.ALL_OR_EMPTY || quantifierType == Path.ALL);
        params.opCode = rule.opCode;
        params.dataOffset = rule.dataOffset;
        params.dataLength = rule.dataLength;

        Descriptor.TypeInfo memory elemTypeInfo;
        if (!params.hasSuffix) {
            elemTypeInfo.code = shape.elementTypeCode;
            elemTypeInfo.isDynamic = shape.elementIsDynamic;
            elemTypeInfo.staticSize = shape.elementIsDynamic ? 0 : shape.elementStaticSize;
        }

        QLoopState memory loop;
        // Each iteration allocates scratch memory (element Location, suffix descent).
        // After copying results into `loop`, free-memory pointer rewinds to this checkpoint.
        // Prevents corruption: escaping references from one iteration would be overwritten.
        uint256 memCheckpoint;
        assembly ("memory-safe") {
            memCheckpoint := mload(0x40)
        }
        // Element iteration: O(1) per element via arrayElementAt.
        for (uint256 elemIndex = 0; elemIndex < shape.length; ++elemIndex) {
            CalldataReader.Location memory elemLoc = CalldataReader.arrayElementAt(shape, elemIndex, callData);

            if (params.hasSuffix) {
                // Descend through suffix path.
                (loop.value, loop.valueLength, loop.typeCode) = _descendAndLoad(
                    state, callData, rule.pathStart, elemLoc, quantifierIndex + 1, rule.depth, params.opBase
                );
            } else {
                // Element is the target.
                loop.typeCode = elemTypeInfo.code;
                if (!elemTypeInfo.isDynamic && elemTypeInfo.staticSize == 32) {
                    loop.value = TypeRule.canonicalize(CalldataReader.loadScalar(elemLoc, callData), loop.typeCode);
                    loop.valueLength = 32;
                } else {
                    require(!OpRule.isValueOp(params.opBase), CalldataReader.NotScalar(loop.typeCode));
                    loop.value = bytes32(0);
                    loop.valueLength = CalldataReader.loadSlice(state.desc, elemLoc, callData).length;
                }
            }

            bool elemResult = _applyOperator(
                params.opCode,
                loop.value,
                loop.valueLength,
                loop.typeCode,
                state.policy,
                params.dataOffset,
                params.dataLength
            );

            // Short-circuit.
            if (params.isUniversal && !elemResult) return false;
            if (!params.isUniversal && elemResult) return true;

            assembly ("memory-safe") {
                mstore(0x40, memCheckpoint)
            }
        }

        return params.isUniversal; // Universal: all passed, Existential: none passed.
    }

    /// @dev Descends from element location through suffix path.
    function _descendAndLoad(
        EvalState memory state,
        bytes calldata callData,
        uint256 pathStart,
        CalldataReader.Location memory startLoc,
        uint8 startStep,
        uint8 endDepth,
        uint8 opBase
    )
        private
        pure
        returns (bytes32 value, uint256 valueLength, uint8 typeCode)
    {
        CalldataReader.Location memory loc = startLoc;

        for (uint8 i = startStep; i < endDepth; ++i) {
            uint16 step = Be16.readUnchecked(state.policy, pathStart + uint256(i) * 2);
            uint8 code = loc.typeCode;

            if (code == TypeCode.TUPLE) {
                loc = CalldataReader.tupleField(state.desc, loc, step, callData);
            } else if (code == TypeCode.STATIC_ARRAY || code == TypeCode.DYNAMIC_ARRAY) {
                CalldataReader.ArrayShape memory innerShape = CalldataReader.arrayShape(state.desc, callData, loc);
                loc = CalldataReader.arrayElementAt(innerShape, step, callData);
            } else {
                revert CalldataReader.NotComposite(code);
            }
        }

        typeCode = loc.typeCode;
        if (!loc.isDynamic && loc.staticSize == 32) {
            value = TypeRule.canonicalize(CalldataReader.loadScalar(loc, callData), typeCode);
            valueLength = 32;
        } else {
            require(!OpRule.isValueOp(opBase), CalldataReader.NotScalar(typeCode));
            valueLength = CalldataReader.loadSlice(state.desc, loc, callData).length;
            value = bytes32(0);
        }
    }

    /// @dev Loads value from context (msg.sender, msg.value, etc.).
    /// Context values are always 32-byte static and unsigned, so no operator type validation needed.
    function _loadContextValue(
        bytes memory policy,
        RuleView memory rule
    )
        private
        view
        returns (bytes32 value, uint256 valueLength, uint8 typeCode)
    {
        uint16 contextPropertyId = Be16.readUnchecked(policy, rule.pathStart);
        return (_readContext(contextPropertyId), 32, TypeCode.UINT256);
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
        pure
        returns (bool)
    {
        uint8 base = opCode & ~OpCode.NOT;
        bool result;

        // forgefmt: disable-next-item
        if (base == OpCode.EQ) {
            result = value == LibBytes.load(policy, dataOffset);

        } else if (base == OpCode.GT) {
            bytes32 operandRaw = LibBytes.load(policy, dataOffset);
            // int256 cast produces slt/sgt; required for correct two's complement ordering of signed integers.
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
            assembly {
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
            assembly {
                let ptr := add(add(policy, 32), dataOffset)
                lower := mload(ptr)
                upper := mload(add(ptr, 32))
            }
            result = valueLength >= lower && valueLength <= upper;

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
        assembly {
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
                // Binary search using 1-indexed access: adjBase = base - 32,
                // so that mload(adjBase + 32*i) reads element i-1 (0-based).
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Be16 } from "./Be16.sol";
import { Constraint } from "./Constraint.sol";
import { Policy } from "./Policy.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { DynamicBufferLib } from "solady/utils/DynamicBufferLib.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { LibBytes } from "solady/utils/LibBytes.sol";

/// @notice Canonical representation of a policy (human-friendly, Constraint-based).
struct PolicyData {
    /// True if the policy targets raw ABI calldata without a selector.
    bool isSelectorless;
    /// The function selector (bytes4(0) when selectorless).
    bytes4 selector;
    /// The function descriptor bytes.
    bytes descriptor;
    /// Constraint groups (OR-ed groups, AND-ed constraints within).
    Constraint[][] groups;
}

/// @title PolicyCoder
/// @notice Canonical binary encoding and decoding for policies.
library PolicyCoder {
    using DynamicBufferLib for DynamicBufferLib.DynamicBuffer;
    using EfficientHashLib for bytes;

    /// @notice A single binary rule for encoding.
    struct Rule {
        /// SCOPE_CONTEXT or SCOPE_CALLDATA.
        uint8 scope;
        /// BE16-encoded path.
        bytes path;
        /// Full operator: opCode(1) || data.
        bytes operator;
        /// Compiled hint block; empty for context rules. Recomputed on encode.
        bytes hint;
    }

    /// @notice A group of rules AND-ed together.
    struct Group {
        /// The rules in this group.
        Rule[] rules;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the group count exceeds the 1-byte header field.
    /// @param count The number of groups.
    error GroupCountOverflow(uint256 count);

    /// @notice Thrown when the rule count exceeds the 2-byte header field.
    /// @param groupIndex The group index.
    /// @param count The number of rules in the group.
    error RuleCountOverflow(uint256 groupIndex, uint256 count);

    /// @notice Thrown when a rule body exceeds the 2-byte size field.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    /// @param size The computed rule size.
    error RuleSizeOverflow(uint256 groupIndex, uint256 ruleIndex, uint256 size);

    /// @notice Thrown when the path has no steps.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    error EmptyPath(uint256 groupIndex, uint256 ruleIndex);

    /// @notice Thrown when the path has an odd byte length.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    error MalformedPath(uint256 groupIndex, uint256 ruleIndex);

    /// @notice Thrown when the path depth exceeds the maximum.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    /// @param depth The computed depth.
    error PathTooDeep(uint256 groupIndex, uint256 ruleIndex, uint256 depth);

    /// @notice Thrown when an operator payload is missing its op code byte.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    error InvalidOperatorBytes(uint256 groupIndex, uint256 ruleIndex);

    /// @notice Thrown when the policy has no groups.
    error EmptyPolicy();

    /// @notice Thrown when a group has no rules.
    /// @param groupIndex The group index.
    error EmptyGroup(uint256 groupIndex);

    /// @notice Thrown when a context-scope rule has a path depth other than one.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    error InvalidContextPath(uint256 groupIndex, uint256 ruleIndex);

    /// @notice Thrown when the descriptor length exceeds the 2-byte field.
    /// @param length The descriptor length.
    error DescLengthOverflow(uint256 length);

    /*//////////////////////////////////////////////////////////////////////////
                                    FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Encodes `groups` into the canonical policy blob with embedded descriptor.
    /// @dev Canonicalization ensures the same logical policy always produces identical bytes,
    /// regardless of the order rules or groups are provided. This is critical for deterministic
    /// policy hashing and onchain verification.
    /// @param groups The groups to encode.
    /// @param selector The 4-byte function selector.
    /// @param desc The function descriptor to embed.
    /// @return The encoded policy blob.
    function encode(Group[] memory groups, bytes4 selector, bytes memory desc) internal pure returns (bytes memory) {
        return _encode(groups, PF.POLICY_VERSION, selector, desc);
    }

    /// @notice Encodes policy data into a canonical blob.
    /// @param data The policy data to encode.
    /// @return The encoded policy blob.
    function encode(PolicyData memory data) internal pure returns (bytes memory) {
        Group[] memory groups = _flatten(data.groups);
        uint8 header = PF.POLICY_VERSION | (data.isSelectorless ? PF.FLAG_NO_SELECTOR : 0);
        // Selector slot is defined as zero for selectorless policies regardless of what the caller provides.
        bytes4 selector = data.isSelectorless ? bytes4(0) : data.selector;
        return _encode(groups, header, selector, data.descriptor);
    }

    /// @notice Decodes a policy blob into policy data.
    /// @dev Groups rules by (scope, path) to reconstruct constraints.
    /// @param policy The encoded policy blob.
    /// @return data The decoded policy data.
    function decode(bytes memory policy) internal pure returns (PolicyData memory data) {
        Policy.validate(policy);

        data.isSelectorless = Policy.isSelectorless(policy);
        data.selector = data.isSelectorless ? bytes4(0) : Policy.selector(policy);
        data.descriptor = Policy.descriptor(policy);

        uint8 groupCount = Policy.groupCount(policy);
        data.groups = new Constraint[][](groupCount);

        uint256 groupOffset = Policy.groupAt(policy, 0);
        for (uint32 groupIndex; groupIndex < groupCount; ++groupIndex) {
            data.groups[groupIndex] = _decodeGroup(policy, groupOffset);
            groupOffset += PF.GROUP_HEADER_SIZE + Policy.groupSize(policy, groupOffset);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Encodes groups into a policy blob with the given header byte.
    function _encode(
        Group[] memory groups,
        uint8 header,
        bytes4 selector,
        bytes memory desc
    )
        private
        pure
        returns (bytes memory)
    {
        uint256 groupCount = groups.length;
        require(groupCount != 0, EmptyPolicy());
        require(groupCount <= type(uint8).max, GroupCountOverflow(groupCount));

        // Canonicalization step 1: compile hints, then sort rules within each group.
        _compileAndSortRules(groups, desc);

        uint256 descLength = desc.length;
        require(descLength <= type(uint16).max, DescLengthOverflow(descLength));

        // Policy header: header(1) | selector(4) | descLength(2) | desc(N) | groupCount(1).
        DynamicBufferLib.DynamicBuffer memory buffer;
        // forge-lint: disable-next-line(unsafe-typecast)
        buffer = buffer.pUint8(header).pBytes4(selector).pUint16(uint16(descLength)).p(desc);
        // forge-lint: disable-next-line(unsafe-typecast)
        buffer = buffer.pUint8(uint8(groupCount));

        // Canonicalization step 2: a lone group is already in canonical position, so its rules go
        // straight into the output. Group header: ruleCount(2) | groupSize(4).
        if (groupCount == 1) {
            Rule[] memory rules = groups[0].rules;
            buffer = buffer.pUint16(uint16(rules.length)).pUint32(uint32(_measureGroup(rules, 0)));
            return _emitRules(buffer, rules).data;
        }

        // Several groups are ordered by ascending hash over their rule bytes, so each is serialized
        // first and its bytes copied out in that order.
        bytes[] memory groupRules = new bytes[](groupCount);
        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            Rule[] memory rules = groups[groupIndex].rules;
            _measureGroup(rules, groupIndex);
            DynamicBufferLib.DynamicBuffer memory groupBuffer;
            groupRules[groupIndex] = _emitRules(groupBuffer, rules).data;
        }

        uint256[] memory order = _groupOrder(groupRules);
        for (uint256 position; position < groupCount; ++position) {
            uint256 groupIndex = order[position];
            bytes memory rules = groupRules[groupIndex];
            buffer = buffer.pUint16(uint16(groups[groupIndex].rules.length)).pUint32(uint32(rules.length)).p(rules);
        }
        return buffer.data;
    }

    /// @dev Returns the total wire size of a group's rules, checking that the group's counts and
    /// each rule's fields fit their encoded field widths.
    /// The total is implied to fit uint32: ruleCount and each ruleSize both fit uint16.
    function _measureGroup(Rule[] memory rules, uint256 groupIndex) private pure returns (uint256 groupSize) {
        uint256 ruleCount = rules.length;
        require(ruleCount != 0, EmptyGroup(groupIndex));
        require(ruleCount <= type(uint16).max, RuleCountOverflow(groupIndex, ruleCount));

        for (uint256 ruleIndex; ruleIndex < ruleCount; ++ruleIndex) {
            Rule memory rule = rules[ruleIndex];

            if (rule.scope == PF.SCOPE_CONTEXT) {
                require(rule.path.length >> 1 == 1, InvalidContextPath(groupIndex, ruleIndex));
            }

            uint256 ruleSize = _ruleSize(rule.path.length, rule.hint.length, rule.operator.length - 1);
            require(ruleSize <= type(uint16).max, RuleSizeOverflow(groupIndex, ruleIndex, ruleSize));

            groupSize += ruleSize;
        }
    }

    /// @dev Appends every rule's wire encoding to `buffer`.
    function _emitRules(
        DynamicBufferLib.DynamicBuffer memory buffer,
        Rule[] memory rules
    )
        private
        pure
        returns (DynamicBufferLib.DynamicBuffer memory)
    {
        uint256 ruleCount = rules.length;
        for (uint256 ruleIndex; ruleIndex < ruleCount; ++ruleIndex) {
            buffer = _emitRule(buffer, rules[ruleIndex]);
        }
        return buffer;
    }

    /// @dev Compiles every calldata rule's hint, then sorts each group's rules in place.
    /// Rules sort by (scope, pathDepth, pathBytes, op) so equivalent rule sets always serialize
    /// identically. Hints compile first because they are part of the rule bytes the group hash covers.
    function _compileAndSortRules(Group[] memory groups, bytes memory desc) private pure {
        uint256 groupCount = groups.length;
        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            Rule[] memory rulesToSort = groups[groupIndex].rules;
            uint256 ruleCount = rulesToSort.length;
            for (uint256 ruleIndex; ruleIndex < ruleCount; ++ruleIndex) {
                _compileRuleHint(rulesToSort[ruleIndex], desc, groupIndex, ruleIndex);
            }
            _sort(rulesToSort);
        }
    }

    /// @dev Checks a rule's variable-length fields and compiles the hint of a calldata rule.
    function _compileRuleHint(Rule memory rule, bytes memory desc, uint256 groupIndex, uint256 ruleIndex) private pure {
        require(rule.operator.length >= 1, InvalidOperatorBytes(groupIndex, ruleIndex));
        uint256 pathLength = rule.path.length;
        require(pathLength != 0, EmptyPath(groupIndex, ruleIndex));
        require((pathLength & 1) == 0, MalformedPath(groupIndex, ruleIndex));
        require(pathLength >> 1 <= PF.MAX_PATH_DEPTH, PathTooDeep(groupIndex, ruleIndex, pathLength >> 1));
        rule.hint = rule.scope == PF.SCOPE_CALLDATA ? Policy.compileHint(desc, rule.path) : bytes("");
    }

    /// @dev Sorts rules in-place by (scope, pathDepth, pathBytes, op).
    function _sort(Rule[] memory rules) private pure {
        uint256 ruleCount = rules.length;
        for (uint256 ruleIndex = 1; ruleIndex < ruleCount; ++ruleIndex) {
            Rule memory key = rules[ruleIndex];
            uint256 insertPos = ruleIndex;
            while (insertPos > 0 && _less(key, rules[insertPos - 1])) {
                rules[insertPos] = rules[insertPos - 1];
                unchecked {
                    --insertPos;
                }
            }
            rules[insertPos] = key;
        }
    }

    /// @dev Returns true if `left` should come before `right`
    /// per sort key: (scope, pathDepth, pathBytes, opCode, opData).
    function _less(Rule memory left, Rule memory right) private pure returns (bool) {
        if (left.scope != right.scope) return left.scope < right.scope;

        uint256 leftDepth = left.path.length >> 1;
        uint256 rightDepth = right.path.length >> 1;
        if (leftDepth != rightDepth) return leftDepth < rightDepth;

        int256 pathComparison = LibBytes.cmp(left.path, right.path);
        if (pathComparison != 0) return pathComparison < 0;

        // Tie-break by operator for deterministic canonicalization.
        return LibBytes.cmp(left.operator, right.operator) < 0;
    }

    /// @dev Returns the group indices ordered by ascending hash of each group's serialized rules.
    function _groupOrder(bytes[] memory groupRules) private pure returns (uint256[] memory order) {
        uint256 groupCount = groupRules.length;

        bytes32[] memory hashes = EfficientHashLib.malloc(groupCount);
        order = new uint256[](groupCount);
        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            hashes[groupIndex] = groupRules[groupIndex].hash();
            order[groupIndex] = groupIndex;
        }

        for (uint256 position = 1; position < groupCount; ++position) {
            uint256 keyIndex = order[position];
            bytes32 keyHash = hashes[position];
            uint256 insertPos = position;
            while (insertPos > 0 && keyHash < hashes[insertPos - 1]) {
                order[insertPos] = order[insertPos - 1];
                hashes[insertPos] = hashes[insertPos - 1];
                unchecked {
                    --insertPos;
                }
            }
            order[insertPos] = keyIndex;
            hashes[insertPos] = keyHash;
        }
    }

    /// @dev Returns the wire size of a rule with the given field lengths, including its size field.
    function _ruleSize(uint256 pathLength, uint256 hintLength, uint256 dataLength) private pure returns (uint256) {
        return PF.RULE_FIXED_OVERHEAD + pathLength + hintLength + dataLength;
    }

    /// @dev Appends one rule's wire encoding to `buffer`:
    /// size(2) | scope(1) | depth(1) | path | hint | opCode(1) | dataLength(2) | data.
    function _emitRule(
        DynamicBufferLib.DynamicBuffer memory buffer,
        Rule memory rule
    )
        private
        pure
        returns (DynamicBufferLib.DynamicBuffer memory)
    {
        bytes memory path = rule.path;
        bytes memory operator = rule.operator;
        bytes memory hint = rule.hint;
        uint8 depth = uint8(path.length / PF.PATH_STEP_SIZE);
        uint16 dataLength = uint16(operator.length - 1);
        uint16 ruleSize = uint16(_ruleSize(path.length, hint.length, dataLength));
        // forgefmt: disable-next-item
        return buffer
            .pUint16(ruleSize)
            .pUint8(rule.scope)
            .pUint8(depth)
            .p(path)
            .p(hint)
            .pUint8(uint8(operator[0]))
            .pUint16(dataLength)
            .p(LibBytes.slice(operator, 1, operator.length));
    }

    /// @dev Decodes the group at `groupOffset` from the policy blob into Constraints.
    function _decodeGroup(bytes memory policy, uint256 groupOffset) private pure returns (Constraint[] memory) {
        uint16 ruleCount = Policy.ruleCount(policy, groupOffset);

        if (ruleCount == 0) return new Constraint[](0);

        // First pass: read all rules into temporary arrays.
        Rule[] memory rules = new Rule[](ruleCount);
        uint256 ruleOffset = groupOffset + PF.GROUP_HEADER_SIZE;

        for (uint256 ruleIndex; ruleIndex < ruleCount; ++ruleIndex) {
            rules[ruleIndex] = _readRule(policy, ruleOffset);
            ruleOffset += Policy.ruleSize(policy, ruleOffset);
        }

        // Second pass: group rules by (scope, path) into Constraints.
        return _groupRulesIntoConstraints(rules);
    }

    /// @dev Reads a single rule from a validated policy blob at the given offset.
    function _readRule(bytes memory policy, uint256 ruleOffset) private pure returns (Rule memory rule) {
        rule.scope = Policy.scope(policy, ruleOffset);
        uint8 depth = Policy.pathDepth(policy, ruleOffset);

        uint256 pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
        rule.path = LibBytes.slice(policy, pathStart, pathStart + uint256(depth) * PF.PATH_STEP_SIZE);

        (uint256 hintOffset, uint256 hintSize) = Policy.hintView(policy, ruleOffset);
        rule.hint = LibBytes.slice(policy, hintOffset, hintOffset + hintSize);

        // The rule is framed by prior validation, so the operator fields sit directly after the hint.
        uint256 opCodeOffset = hintOffset + hintSize;
        uint16 dataLength = Be16.readUnchecked(policy, opCodeOffset + PF.RULE_OPCODE_SIZE);
        uint256 dataOffset = opCodeOffset + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;
        rule.operator =
            abi.encodePacked(policy[opCodeOffset], LibBytes.slice(policy, dataOffset, dataOffset + dataLength));
    }

    /// @dev Groups rules by (scope, path, hint) into Constraints. The hint joins the key so that
    /// rules whose stored hints diverge stay separate constraints instead of collapsing into one.
    function _groupRulesIntoConstraints(Rule[] memory rules) private pure returns (Constraint[] memory) {
        uint256 ruleCount = rules.length;
        if (ruleCount == 0) return new Constraint[](0);

        // Single pass: allocate worst-case (every rule could have a unique path), fill, then trim.
        Constraint[] memory constraints = new Constraint[](ruleCount);
        bytes32[] memory keys = new bytes32[](ruleCount);
        uint256 uniqueCount;

        for (uint256 i; i < ruleCount; ++i) {
            bytes32 key = abi.encodePacked(rules[i].scope, rules[i].path, rules[i].hint).hash();

            uint256 matchIndex = type(uint256).max;
            for (uint256 j; j < uniqueCount; ++j) {
                if (keys[j] == key) {
                    matchIndex = j;
                    break;
                }
            }

            if (matchIndex == type(uint256).max) {
                // Allocate operators at worst-case size so later appends can grow in-place
                // via assembly without reallocation, then trim to actual count of 1.
                bytes[] memory operators = new bytes[](ruleCount);
                operators[0] = rules[i].operator;
                assembly ("memory-safe") {
                    mstore(operators, 1)
                }
                // forgefmt: disable-next-item
                constraints[uniqueCount] = Constraint({
                    scope: rules[i].scope, path: rules[i].path, operators: operators, hint: rules[i].hint
                });
                keys[uniqueCount] = key;
                ++uniqueCount;
            } else {
                // Append into the pre-allocated slack. The array carries its logical length, so
                // the length word grows before the write.
                bytes[] memory operators = constraints[matchIndex].operators;
                uint256 operatorCount = operators.length;
                assembly ("memory-safe") {
                    mstore(operators, add(operatorCount, 1))
                }
                operators[operatorCount] = rules[i].operator;
            }
        }

        assembly ("memory-safe") {
            mstore(constraints, uniqueCount)
        }
        return constraints;
    }

    /// @dev Flattens constraint groups into rule groups (one rule per operator).
    function _flatten(Constraint[][] memory constraintGroups) private pure returns (Group[] memory flatGroups) {
        uint256 groupCount = constraintGroups.length;
        flatGroups = new Group[](groupCount);

        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            Constraint[] memory constraints = constraintGroups[groupIndex];
            uint256 constraintCount = constraints.length;

            uint256 ruleCount;
            for (uint256 constraintIndex; constraintIndex < constraintCount; ++constraintIndex) {
                ruleCount += constraints[constraintIndex].operators.length;
            }

            Rule[] memory rules = new Rule[](ruleCount);
            uint256 ruleIndex;

            for (uint256 constraintIndex; constraintIndex < constraintCount; ++constraintIndex) {
                Constraint memory constraint = constraints[constraintIndex];
                bytes[] memory operators = constraint.operators;
                uint256 operatorCount = operators.length;

                for (uint256 operatorIndex; operatorIndex < operatorCount; ++operatorIndex) {
                    // forgefmt: disable-next-item
                    rules[ruleIndex++] = Rule({
                        scope: constraint.scope, path: constraint.path, operator: operators[operatorIndex], hint: ""
                    });
                }
            }

            flatGroups[groupIndex] = Group({ rules: rules });
        }
    }
}

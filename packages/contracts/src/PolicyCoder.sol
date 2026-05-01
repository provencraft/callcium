// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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

    /// @notice Thrown when the path is empty or has an odd byte length.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    error InvalidPathBytes(uint256 groupIndex, uint256 ruleIndex);

    /// @notice Thrown when the path depth exceeds the 1-byte depth field.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    /// @param depth The computed depth.
    error PathDepthOverflow(uint256 groupIndex, uint256 ruleIndex, uint256 depth);

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

        // Canonicalization step 1: sort rules within each group.
        // Rules are sorted by (scope, pathDepth, pathBytes, op) so equivalent rule sets always serialize identically.
        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            Rule[] memory rulesToSort = groups[groupIndex].rules;
            uint256 ruleCount = rulesToSort.length;
            for (uint256 ruleIndex; ruleIndex < ruleCount; ++ruleIndex) {
                require(rulesToSort[ruleIndex].operator.length >= 1, InvalidOperatorBytes(groupIndex, ruleIndex));
            }
            _sort(rulesToSort);
        }

        // Canonicalization step 2: sort groups by hash of their (now-sorted) rules.
        // This ensures group order is deterministic.
        _sortGroups(groups);

        // Validate descriptor length fits in 2-byte field.
        uint256 descLength = desc.length;
        require(descLength <= type(uint16).max, DescLengthOverflow(descLength));

        // Policy header: header(1) | selector(4) | descLength(2) | desc(N) | groupCount(1).
        DynamicBufferLib.DynamicBuffer memory buffer;
        // forge-lint: disable-next-line(unsafe-typecast)
        buffer = buffer.pUint8(header).pBytes4(selector).pUint16(uint16(descLength)).p(desc);
        // forge-lint: disable-next-line(unsafe-typecast)
        buffer = buffer.pUint8(uint8(groupCount));

        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            Rule[] memory rules = groups[groupIndex].rules;
            uint256 ruleCount = rules.length;
            require(ruleCount != 0, EmptyGroup(groupIndex));
            require(ruleCount <= type(uint16).max, RuleCountOverflow(groupIndex, ruleCount));

            // First pass: compute sizes and validate format constraints.
            // We need sizes upfront because the format requires size prefixes before content.
            // Validations ensure values fit their encoded field widths and that path bytes are well-formed.
            uint256 groupSize;
            uint16[] memory ruleSizes = new uint16[](ruleCount);
            for (uint256 ruleIndex; ruleIndex < ruleCount; ++ruleIndex) {
                Rule memory rule = rules[ruleIndex];
                uint256 pathLength = rule.path.length;
                require(pathLength != 0 && (pathLength & 1) == 0, InvalidPathBytes(groupIndex, ruleIndex));

                uint256 depth = pathLength >> 1;
                require(depth <= type(uint8).max, PathDepthOverflow(groupIndex, ruleIndex, depth));
                if (rule.scope == PF.SCOPE_CONTEXT) require(depth == 1, InvalidContextPath(groupIndex, ruleIndex));

                bytes memory operator = rule.operator;
                uint256 dataLength = operator.length - 1;
                uint256 ruleSize = PF.RULE_FIXED_OVERHEAD + pathLength + dataLength;
                require(ruleSize <= type(uint16).max, RuleSizeOverflow(groupIndex, ruleIndex, ruleSize));

                // forge-lint: disable-next-line(unsafe-typecast)
                ruleSizes[ruleIndex] = uint16(ruleSize);
                groupSize += ruleSize;
            }

            // Implied by: ruleCount <= uint16.max and each ruleSize <= uint16.max.
            // Max groupSize = 0xFFFF * 0xFFFF < 2**32.
            assert(groupSize <= type(uint32).max);

            // Group header: ruleCount(2) | groupSize(4).
            // forge-lint: disable-next-line(unsafe-typecast)
            buffer = buffer.pUint16(uint16(ruleCount)).pUint32(uint32(groupSize));

            // Second pass: emit each rule.
            for (uint256 ruleIndex; ruleIndex < ruleCount; ++ruleIndex) {
                Rule memory rule = rules[ruleIndex];
                bytes memory path = rule.path;
                bytes memory operator = rule.operator;

                // Extract rule metadata for encoding.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint8 depth = uint8(path.length / PF.PATH_STEP_SIZE);
                // forge-lint: disable-next-line(unsafe-typecast)
                uint8 opCode = uint8(operator[0]);
                // forge-lint: disable-next-line(unsafe-typecast)
                uint16 dataLength = uint16(operator.length - 1);

                // Pack the rule: size(2) | scope(1) | depth(1) | path(2*depth) | opCode(1) | dataLength(2) | data(N)
                // forgefmt: disable-next-item
                buffer = buffer
                    .pUint16(ruleSizes[ruleIndex])
                    .pUint8(rule.scope)
                    .pUint8(depth)
                    .p(path)
                    .pUint8(opCode)
                    .pUint16(dataLength)
                    .p(LibBytes.slice(operator, 1, operator.length));
            }
        }
        return buffer.data;
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

        for (uint32 groupIndex; groupIndex < groupCount; ++groupIndex) {
            data.groups[groupIndex] = _decodeGroup(policy, groupIndex);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

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

    /// @dev Sorts groups in-place by hash of their sorted rules.
    function _sortGroups(Group[] memory groups) private pure {
        uint256 groupCount = groups.length;
        if (groupCount <= 1) return;

        bytes32[] memory hashes = EfficientHashLib.malloc(groupCount);
        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            hashes[groupIndex] = _groupHash(groups[groupIndex]);
        }

        for (uint256 groupIndex = 1; groupIndex < groupCount; ++groupIndex) {
            Group memory keyGroup = groups[groupIndex];
            bytes32 keyHash = hashes[groupIndex];
            uint256 insertPos = groupIndex;
            while (insertPos > 0 && keyHash < hashes[insertPos - 1]) {
                groups[insertPos] = groups[insertPos - 1];
                hashes[insertPos] = hashes[insertPos - 1];
                unchecked {
                    --insertPos;
                }
            }
            groups[insertPos] = keyGroup;
            hashes[insertPos] = keyHash;
        }
    }

    /// @dev Computes a canonical hash for a group from its sorted rules.
    function _groupHash(Group memory group) private pure returns (bytes32) {
        Rule[] memory rules = group.rules;
        uint256 ruleCount = rules.length;

        DynamicBufferLib.DynamicBuffer memory buffer;
        for (uint256 ruleIndex; ruleIndex < ruleCount; ++ruleIndex) {
            Rule memory rule = rules[ruleIndex];
            bytes memory path = rule.path;
            bytes memory operator = rule.operator;
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 depth = uint8(path.length / PF.PATH_STEP_SIZE);
            // forge-lint: disable-next-line(unsafe-typecast)
            uint16 dataLength = uint16(operator.length - 1);
            // forge-lint: disable-next-line(unsafe-typecast)
            uint16 ruleSize = uint16(PF.RULE_FIXED_OVERHEAD + path.length + dataLength);

            // Full wire encoding: size(2) | scope(1) | depth(1) | path | opCode(1) | dataLength(2) | data.
            // forgefmt: disable-next-item
            buffer = buffer
                .pUint16(ruleSize)
                .pUint8(rule.scope)
                .pUint8(depth)
                .p(path)
                .pUint8(uint8(operator[0]))
                .pUint16(dataLength)
                .p(LibBytes.slice(operator, 1, operator.length));
        }
        return buffer.data.hash();
    }

    /// @dev Decodes a single group from the policy blob into Constraints.
    function _decodeGroup(bytes memory policy, uint32 groupIndex) private pure returns (Constraint[] memory) {
        uint256 groupOffset = Policy.groupAt(policy, groupIndex);
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

    /// @dev Reads a single rule from the policy blob at the given offset.
    function _readRule(bytes memory policy, uint256 ruleOffset) private pure returns (Rule memory rule) {
        rule.scope = Policy.scope(policy, ruleOffset);
        uint8 depth = Policy.pathDepth(policy, ruleOffset);

        rule.path = new bytes(uint256(depth) * PF.PATH_STEP_SIZE);
        for (uint256 i; i < depth; ++i) {
            uint16 step = Policy.pathStep(policy, ruleOffset, i);
            Be16.write(rule.path, i * 2, step);
        }

        uint8 opCode = Policy.opCode(policy, ruleOffset);
        (uint256 dataOffset, uint16 dataLength) = Policy.dataView(policy, ruleOffset);

        rule.operator = new bytes(1 + dataLength);
        rule.operator[0] = bytes1(opCode);
        for (uint256 i; i < dataLength; ++i) {
            rule.operator[1 + i] = policy[dataOffset + i];
        }
    }

    /// @dev Groups rules by (scope, path) into Constraints.
    function _groupRulesIntoConstraints(Rule[] memory rules) private pure returns (Constraint[] memory) {
        uint256 ruleCount = rules.length;
        if (ruleCount == 0) return new Constraint[](0);

        // Single pass: allocate worst-case (every rule could have a unique path), fill, then trim.
        Constraint[] memory constraints = new Constraint[](ruleCount);
        bytes32[] memory keys = new bytes32[](ruleCount);
        uint256 uniqueCount;

        for (uint256 i; i < ruleCount; ++i) {
            bytes32 key = abi.encodePacked(rules[i].scope, rules[i].path).hash();

            // Find existing constraint for this key.
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
                    scope: rules[i].scope, path: rules[i].path, operators: operators
                });
                keys[uniqueCount] = key;
                ++uniqueCount;
            } else {
                // Append operator into the pre-allocated slack. The array was trimmed to its
                // logical length, so we must bump it via assembly before the Solidity write
                // to avoid an out-of-bounds revert.
                bytes[] memory operators = constraints[matchIndex].operators;
                uint256 operatorCount = operators.length;
                assembly ("memory-safe") {
                    mstore(operators, add(operatorCount, 1))
                }
                operators[operatorCount] = rules[i].operator;
            }
        }

        // Trim constraints array and each operators array.
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
                        scope: constraint.scope, path: constraint.path, operator: operators[operatorIndex]
                    });
                }
            }

            flatGroups[groupIndex] = Group({ rules: rules });
        }
    }
}

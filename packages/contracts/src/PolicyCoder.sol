// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Be16 } from "./Be16.sol";
import { Descriptor } from "./Descriptor.sol";
import { Hint } from "./Hint.sol";
import { OpCode } from "./OpCode.sol";
import { OpRule } from "./OpRule.sol";
import { Path } from "./Path.sol";
import { Policy } from "./Policy.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { TypeRule } from "./TypeRule.sol";
import { LibBytes } from "./vendor/solady/utils/LibBytes.sol";

/// @notice A test or a context test of a loop body.
struct BodyRule {
    /// SCOPE_CONTEXT or SCOPE_CALLDATA.
    uint8 scope;
    /// BE16-encoded path from the element. A context test's path is its property ID.
    bytes path;
    /// The hint a blob carries for the path. The hint is empty for a context test and in data not read from a blob.
    bytes hint;
    /// Encoded operator: opCode(1) || each operand value as a 32-byte word, a context property as its ID.
    bytes operator;
}

/// @notice A rule of a group: a test, a context test or a loop.
struct Rule {
    /// SCOPE_CONTEXT, SCOPE_CALLDATA or SCOPE_LOOP.
    uint8 scope;
    /// A loop's quantifier, or zero for a test.
    uint8 quantifier;
    /// BE16-encoded path from the arguments, a loop's to its array. A context test's path is its property ID.
    bytes path;
    /// The hint a blob carries for the path, a loop's frame hint. The hint is empty for a context test and in data
    /// not read from a blob.
    bytes hint;
    /// A test's encoded operator, as a body rule's. The operator is empty for a loop.
    bytes operator;
    /// A loop's body, or empty for a test.
    BodyRule[] body;
}

/// @notice A policy: its selector, its descriptor and its groups of rules.
struct PolicyData {
    /// True if the policy targets raw ABI calldata without a selector.
    bool isSelectorless;
    /// The function selector, unused when selectorless.
    bytes4 selector;
    /// The function descriptor bytes.
    bytes descriptor;
    /// Rule groups (OR-ed groups, AND-ed rules within).
    Rule[][] groups;
}

/// @title PolicyCoder
/// @notice Encoder of policies in canonical form, and decoder of policy blobs.
library PolicyCoder {
    /// @dev A rule with its bytes.
    struct Keyed {
        /// @dev The rule.
        Rule rule;
        /// @dev The rule's size-free bytes, its key in the canonical order.
        bytes key;
        /// @dev The rule's bytes after its `ruleSize`, each body rule framed.
        bytes content;
    }

    /// @dev Descriptor offset standing for the arguments as a starting point. The descriptor header contains no node.
    uint256 private constant ARGUMENTS = 0;

    /// @dev The `pathDepth` of a context test, whose path is its property ID.
    uint8 private constant CONTEXT_PATH_DEPTH = 1;

    /*//////////////////////////////////////////////////////////////////////////
                                      ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the policy has more groups than `groupCount` can represent.
    /// @param count The number of groups.
    error GroupCountOverflow(uint256 count);

    /// @notice Thrown when a group has more rules than `ruleCount` can represent.
    /// @param groupIndex The group index.
    /// @param count The number of rules.
    error RuleCountOverflow(uint256 groupIndex, uint256 count);

    /// @notice Thrown when a rule is larger than `ruleSize` can represent.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    /// @param size The rule size in bytes.
    error RuleSizeOverflow(uint256 groupIndex, uint256 ruleIndex, uint256 size);

    /// @notice Thrown when a rule path is empty.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    error EmptyPath(uint256 groupIndex, uint256 ruleIndex);

    /// @notice Thrown when a rule path has an odd byte length.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    error MalformedPath(uint256 groupIndex, uint256 ruleIndex);

    /// @notice Thrown when a rule path exceeds the maximum depth, counted across the enclosing loop.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    /// @param depth The path depth.
    error PathTooDeep(uint256 groupIndex, uint256 ruleIndex, uint256 depth);

    /// @notice Thrown when an operator is not an opcode followed by one or more 32-byte words, or a context property
    /// operand by one ID.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    error InvalidOperatorBytes(uint256 groupIndex, uint256 ruleIndex);

    /// @notice Thrown when the policy has no groups.
    error EmptyPolicy();

    /// @notice Thrown when a group has no rules.
    /// @param groupIndex The group index.
    error EmptyGroup(uint256 groupIndex);

    /// @notice Thrown when a context test's path is not one step.
    /// @param groupIndex The group index.
    /// @param ruleIndex The rule index within the group.
    error InvalidContextPath(uint256 groupIndex, uint256 ruleIndex);

    /// @notice Thrown when the descriptor is longer than `descLength` can represent.
    /// @param length The descriptor length.
    error DescLengthOverflow(uint256 length);

    /// @notice Thrown when a rule's scope is not a defined value.
    /// @param scope The scope value.
    error UnknownScope(uint8 scope);

    /// @notice Thrown when a loop's quantifier is not a defined value.
    /// @param quantifier The quantifier value.
    error UnknownQuantifier(uint8 quantifier);

    /// @notice Thrown when an operator's comparison does not apply to its target's type.
    /// @param opCode The operator code.
    /// @param typeCode The target's type code.
    error OperatorTargetMismatch(uint8 opCode, uint8 typeCode);

    /// @notice Thrown when a constant is not a value of its operand type.
    /// @param word The 32-byte word of the constant.
    /// @param typeCode The target's type code.
    error OutOfPhysicalBounds(bytes32 word, uint8 typeCode);

    /*//////////////////////////////////////////////////////////////////////////
                                    FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Encodes the canonical form of a policy: each group normalized, its rules and the groups sorted by their
    /// size-free bytes, repeats dropped.
    /// @param data The policy.
    /// @return The policy blob.
    function encode(PolicyData memory data) internal pure returns (bytes memory) {
        Rule[][] memory groups = data.groups;
        uint256 groupCount = groups.length;
        require(groupCount != 0, EmptyPolicy());
        bytes memory desc = data.descriptor;
        require(desc.length <= type(uint16).max, DescLengthOverflow(desc.length));

        bytes[] memory keys = new bytes[](groupCount);
        bytes[] memory encodedGroups = new bytes[](groupCount);
        for (uint256 groupIndex = 0; groupIndex < groupCount; ++groupIndex) {
            (keys[groupIndex], encodedGroups[groupIndex]) = _encodeGroup(desc, groups[groupIndex], groupIndex);
        }
        groupCount = _sortGroups(keys, encodedGroups);
        require(groupCount <= type(uint8).max, GroupCountOverflow(groupCount));

        uint8 header = (PF.MAJOR << PF.MAJOR_SHIFT) | (PF.MINOR << PF.MINOR_SHIFT);
        if (data.isSelectorless) header |= PF.FLAG_NO_SELECTOR;
        // Selector slot is defined as zero for selectorless policies regardless of what the caller provides.
        bytes4 selector = data.isSelectorless ? bytes4(0) : data.selector;
        // forge-lint: disable-next-line(unsafe-typecast) bounded by the `*Overflow` checks above.
        bytes memory blob = abi.encodePacked(header, selector, uint16(desc.length), desc, uint8(groupCount));
        for (uint256 position = 0; position < groupCount; ++position) {
            blob = bytes.concat(blob, encodedGroups[position]);
        }
        return blob;
    }

    /// @notice Decodes a policy blob into the policy it states.
    /// @dev Reverts with the storage validation error of a blob that fails it. Reverts with the metadata error of a
    /// descriptor whose composite node disagrees with its children.
    /// @param policy The policy blob.
    /// @return data The decoded policy, each operand loaded to its 32-byte word.
    function decode(bytes memory policy) internal pure returns (PolicyData memory data) {
        Policy.validate(policy);

        data.isSelectorless = Policy.isSelectorless(policy);
        data.selector = data.isSelectorless ? bytes4(0) : Policy.selector(policy);
        uint256 descLength = Be16.readUnchecked(policy, PF.POLICY_DESC_LENGTH_OFFSET);
        uint256 groupCountOffset = PF.POLICY_DESC_OFFSET + descLength;
        data.descriptor = LibBytes.slice(policy, PF.POLICY_DESC_OFFSET, groupCountOffset);
        Descriptor.validateMeta(data.descriptor);

        uint256 groupCount = uint8(policy[groupCountOffset]);
        data.groups = new Rule[][](groupCount);
        uint256 offset = groupCountOffset + PF.POLICY_GROUP_COUNT_SIZE;
        for (uint256 groupIndex = 0; groupIndex < groupCount; ++groupIndex) {
            Rule[] memory rules = new Rule[](Be16.readUnchecked(policy, offset + PF.GROUP_RULECOUNT_OFFSET));
            offset += PF.GROUP_HEADER_SIZE;
            for (uint256 ruleIndex = 0; ruleIndex < rules.length; ++ruleIndex) {
                rules[ruleIndex] = _readRule(policy, offset);
                offset += Be16.readUnchecked(policy, offset);
            }
            data.groups[groupIndex] = rules;
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Encodes a group in canonical form: its size-free bytes, and its bytes with the group header.
    function _encodeGroup(
        bytes memory desc,
        Rule[] memory rules,
        uint256 groupIndex
    )
        private
        pure
        returns (bytes memory key, bytes memory encoded)
    {
        uint256 ruleCount = rules.length;
        require(ruleCount != 0, EmptyGroup(groupIndex));

        // Every rule in canonical form, bodies first; then loops joined, context tests hoisted, and the rules sorted.
        Rule[] memory normalized = new Rule[](ruleCount);
        for (uint256 ruleIndex = 0; ruleIndex < ruleCount; ++ruleIndex) {
            _checkRule(rules[ruleIndex], groupIndex, ruleIndex);
            normalized[ruleIndex] = _normalizeRule(desc, rules[ruleIndex]);
        }
        Keyed[] memory finished = _finish(desc, _hoistContext(_joinLoops(desc, normalized)), ARGUMENTS);

        ruleCount = finished.length;
        require(ruleCount <= type(uint16).max, RuleCountOverflow(groupIndex, ruleCount));
        bytes memory ruleBytes;
        for (uint256 ruleIndex = 0; ruleIndex < ruleCount; ++ruleIndex) {
            uint256 ruleSize = finished[ruleIndex].content.length + PF.RULE_SIZE_SIZE;
            require(ruleSize <= type(uint16).max, RuleSizeOverflow(groupIndex, ruleIndex, ruleSize));
            // forge-lint: disable-next-line(unsafe-typecast) bounded by the `RuleSizeOverflow` check above.
            ruleBytes = bytes.concat(ruleBytes, bytes2(uint16(ruleSize)), finished[ruleIndex].content);
            key = bytes.concat(key, finished[ruleIndex].key);
        }
        // forge-lint: disable-next-line(unsafe-typecast) bounded by the `Rule*Overflow` checks above.
        encoded = abi.encodePacked(uint16(ruleCount), uint32(ruleBytes.length), ruleBytes);
    }

    /// @dev Requires the rule's fields to have the shapes the encoder reads.
    function _checkRule(Rule memory rule, uint256 groupIndex, uint256 ruleIndex) private pure {
        if (rule.scope != PF.SCOPE_LOOP) {
            _checkTest(rule.scope, rule.path, rule.operator, 0, groupIndex, ruleIndex);
            return;
        }
        require(
            rule.quantifier == PF.QUANTIFIER_ALL || rule.quantifier == PF.QUANTIFIER_ANY,
            UnknownQuantifier(rule.quantifier)
        );
        uint256 arrayDepth = _checkPath(rule.path, true, 0, groupIndex, ruleIndex);
        BodyRule[] memory body = rule.body;
        for (uint256 bodyIndex = 0; bodyIndex < body.length; ++bodyIndex) {
            BodyRule memory test = body[bodyIndex];
            _checkTest(test.scope, test.path, test.operator, arrayDepth, groupIndex, ruleIndex);
        }
    }

    /// @dev Requires a test's operator to be an opcode and one or more 32-byte words, and its path to have the shape
    /// its scope reads. A calldata test follows `depthBefore` steps of an enclosing loop.
    function _checkTest(
        uint8 scope,
        bytes memory path,
        bytes memory operator,
        uint256 depthBefore,
        uint256 groupIndex,
        uint256 ruleIndex
    )
        private
        pure
    {
        uint256 operatorLength = operator.length;
        require(operatorLength > 1 && (operatorLength - 1) % 32 == 0, InvalidOperatorBytes(groupIndex, ruleIndex));
        // A context property operand is one ID within its field.
        if (_source(operator) == OpCode.SOURCE_CONTEXT) {
            require(
                operatorLength == 33 && uint256(LibBytes.load(operator, 1)) <= type(uint16).max,
                InvalidOperatorBytes(groupIndex, ruleIndex)
            );
        }
        if (scope == PF.SCOPE_CONTEXT) {
            require(path.length == PF.PROPERTY_ID_SIZE, InvalidContextPath(groupIndex, ruleIndex));
        } else if (scope == PF.SCOPE_CALLDATA) {
            _checkPath(path, depthBefore == 0, depthBefore, groupIndex, ruleIndex);
        } else {
            revert UnknownScope(scope);
        }
    }

    /// @dev Requires a calldata path to be whole steps, nonempty where `required`, and within `MAX_PATH_DEPTH` with
    /// the `depthBefore` steps of an enclosing loop. Returns the depth reached.
    function _checkPath(
        bytes memory path,
        bool required,
        uint256 depthBefore,
        uint256 groupIndex,
        uint256 ruleIndex
    )
        private
        pure
        returns (uint256 depth)
    {
        uint256 pathLength = path.length;
        require(!required || pathLength != 0, EmptyPath(groupIndex, ruleIndex));
        require(pathLength % PF.PATH_STEP_SIZE == 0, MalformedPath(groupIndex, ruleIndex));
        depth = depthBefore + pathLength / PF.PATH_STEP_SIZE;
        require(depth <= PF.MAX_PATH_DEPTH, PathTooDeep(groupIndex, ruleIndex, depth));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   NORMALIZATION
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the rule in canonical form: its operator positive and no one-member set, a context pair with the
    /// lower ID as subject, a loop's body finished.
    function _normalizeRule(bytes memory desc, Rule memory rule) private pure returns (Rule memory) {
        if (rule.scope != PF.SCOPE_LOOP) return _normalizeTest(rule.scope, rule.path, rule.operator);

        BodyRule[] memory body = rule.body;
        Rule[] memory tests = new Rule[](body.length);
        for (uint256 bodyIndex = 0; bodyIndex < body.length; ++bodyIndex) {
            BodyRule memory test = body[bodyIndex];
            tests[bodyIndex] = _normalizeTest(test.scope, test.path, test.operator);
        }
        return _loop(desc, rule.quantifier, rule.path, tests);
    }

    /// @dev Returns the test with its operator in canonical form and, for a context test against another context
    /// property, the lower ID as subject.
    function _normalizeTest(
        uint8 scope,
        bytes memory path,
        bytes memory operator
    )
        private
        pure
        returns (Rule memory test)
    {
        test.scope = scope;
        test.path = path;
        test.operator = _normalizeOperator(operator);
        if (scope != PF.SCOPE_CONTEXT || _source(test.operator) != OpCode.SOURCE_CONTEXT) return test;

        uint8 opCode = uint8(test.operator[0]);
        uint8 swapped = _swap(opCode & OpCode.COMPARISON_MASK);
        uint256 other = uint256(LibBytes.load(test.operator, 1));
        uint16 property = Path.atUnchecked(path, 0);
        if (swapped == 0 || other >= property) return test;

        // forge-lint: disable-next-line(unsafe-typecast) bounded by the comparison with `property` above.
        test.path = Path.encode(uint16(other));
        test.operator = abi.encodePacked((opCode & ~OpCode.COMPARISON_MASK) | swapped, uint256(property));
    }

    /// @dev Returns the operator without NOT where a positive comparison expresses the negation, and a one-member
    /// constant set as an equality.
    function _normalizeOperator(bytes memory operator) private pure returns (bytes memory normalized) {
        uint8 opCode = uint8(operator[0]);
        uint8 comparison = opCode & OpCode.COMPARISON_MASK;
        if (opCode & OpCode.NOT != 0) {
            uint8 positive = _negation(comparison);
            if (positive != 0) opCode = (opCode & ~(OpCode.NOT | OpCode.COMPARISON_MASK)) | positive;
        }
        if (comparison == OpCode.IN && _source(operator) == OpCode.SOURCE_CONSTANT && operator.length == 33) {
            opCode = (opCode & ~OpCode.COMPARISON_MASK) | OpCode.EQ;
        }
        normalized = LibBytes.slice(operator, 0, operator.length);
        normalized[0] = bytes1(opCode);
    }

    /// @dev Returns the loop over the array at `arrayPath` with its body finished.
    function _loop(
        bytes memory desc,
        uint8 quantifier,
        bytes memory arrayPath,
        Rule[] memory tests
    )
        private
        pure
        returns (Rule memory loop)
    {
        Hint.Compiled memory compiled = Hint.compileLoop(desc, arrayPath);
        Hint.requireCompiled(compiled, arrayPath, 0);
        Keyed[] memory finished = _finish(desc, tests, compiled.node);

        loop.scope = PF.SCOPE_LOOP;
        loop.quantifier = quantifier;
        loop.path = arrayPath;
        loop.body = new BodyRule[](finished.length);
        for (uint256 bodyIndex = 0; bodyIndex < finished.length; ++bodyIndex) {
            Rule memory test = finished[bodyIndex].rule;
            loop.body[bodyIndex] = BodyRule(test.scope, test.path, test.hint, test.operator);
        }
    }

    /// @dev Joins every `ALL` loop into the first `ALL` loop over the same array. `ANY` loops stay apart: they are
    /// independent existentials.
    function _joinLoops(bytes memory desc, Rule[] memory rules) private pure returns (Rule[] memory joined) {
        uint256 ruleCount = rules.length;
        joined = new Rule[](ruleCount);
        bool[] memory consumed = new bool[](ruleCount);
        uint256 joinedCount = 0;
        for (uint256 ruleIndex = 0; ruleIndex < ruleCount; ++ruleIndex) {
            if (consumed[ruleIndex]) continue;
            Rule memory rule = rules[ruleIndex];
            if (_isAllLoop(rule)) {
                Rule[] memory tests = _bodyRules(rule.body);
                for (uint256 laterIndex = ruleIndex + 1; laterIndex < ruleCount; ++laterIndex) {
                    Rule memory later = rules[laterIndex];
                    if (!_isAllLoop(later) || !LibBytes.eq(later.path, rule.path)) continue;
                    tests = _concat(tests, _bodyRules(later.body));
                    consumed[laterIndex] = true;
                }
                rule = _loop(desc, PF.QUANTIFIER_ALL, rule.path, tests);
            }
            joined[joinedCount++] = rule;
        }
        _truncate(joined, joinedCount);
    }

    /// @dev Moves the context tests of every `ANY` loop whose body contains a calldata test into the group:
    /// `∃i.(P ∧ Q(i)) ≡ P ∧ ∃i.Q(i)`.
    function _hoistContext(Rule[] memory rules) private pure returns (Rule[] memory hoisted) {
        uint256 ruleCount = rules.length;
        uint256 hoistedCount = 0;
        for (uint256 ruleIndex = 0; ruleIndex < ruleCount; ++ruleIndex) {
            if (_hoists(rules[ruleIndex])) hoistedCount += _countScope(rules[ruleIndex].body, PF.SCOPE_CONTEXT);
        }
        if (hoistedCount == 0) return rules;

        hoisted = new Rule[](ruleCount + hoistedCount);
        uint256 position = ruleCount;
        for (uint256 ruleIndex = 0; ruleIndex < ruleCount; ++ruleIndex) {
            Rule memory rule = rules[ruleIndex];
            hoisted[ruleIndex] = rule;
            if (!_hoists(rule)) continue;

            BodyRule[] memory body = rule.body;
            BodyRule[] memory kept = new BodyRule[](body.length - _countScope(body, PF.SCOPE_CONTEXT));
            uint256 keptCount = 0;
            for (uint256 bodyIndex = 0; bodyIndex < body.length; ++bodyIndex) {
                BodyRule memory test = body[bodyIndex];
                if (test.scope == PF.SCOPE_CONTEXT) hoisted[position++] = _rule(test);
                else kept[keptCount++] = test;
            }
            hoisted[ruleIndex] = Rule(PF.SCOPE_LOOP, rule.quantifier, rule.path, rule.hint, "", kept);
        }
    }

    /// @dev Returns the rules sorted by their size-free bytes, repeats dropped and lone range pairs fused. Fusing counts
    /// distinct rules, so it follows dropping repeats. A range can repeat a rule already
    /// present, so sorting follows fusing.
    function _finish(bytes memory desc, Rule[] memory rules, uint256 start) private pure returns (Keyed[] memory) {
        Keyed[] memory keyed = new Keyed[](rules.length);
        for (uint256 ruleIndex = 0; ruleIndex < rules.length; ++ruleIndex) {
            keyed[ruleIndex] = _keyed(desc, rules[ruleIndex], start);
        }
        return _sortRules(_fuseRanges(desc, _sortRules(keyed), start));
    }

    /// @dev Fuses each lone pair of bounds on one subject into a range: the lower bound becomes the range, the upper
    /// bound leaves. The range is defined as the pair, so no bound needs comparing.
    function _fuseRanges(bytes memory desc, Keyed[] memory keyed, uint256 start) private pure returns (Keyed[] memory) {
        uint256 ruleCount = keyed.length;
        Keyed[] memory fused = new Keyed[](ruleCount);
        uint256 fusedCount = 0;
        for (uint256 ruleIndex = 0; ruleIndex < ruleCount; ++ruleIndex) {
            Rule memory rule = keyed[ruleIndex].rule;
            (bool isBound, bool isLength, bool isLower) = _bound(rule);
            uint256 partner = isBound ? _lonePartner(keyed, rule, isLength, isLower) : type(uint256).max;
            if (partner == type(uint256).max) {
                fused[fusedCount++] = keyed[ruleIndex];
            } else if (isLower) {
                Rule memory range;
                range.scope = rule.scope;
                range.path = rule.path;
                range.operator = abi.encodePacked(
                    isLength ? OpCode.LENGTH_BETWEEN : OpCode.BETWEEN,
                    LibBytes.load(rule.operator, 1),
                    LibBytes.load(keyed[partner].rule.operator, 1)
                );
                fused[fusedCount++] = _keyed(desc, range, start);
            }
        }
        _truncate(fused, fusedCount);
        return fused;
    }

    /// @dev Returns the index of the other bound of the lone pair `rule` belongs to, or `type(uint256).max` unless one
    /// rule bounds each side of its subject.
    function _lonePartner(
        Keyed[] memory keyed,
        Rule memory rule,
        bool isLength,
        bool isLower
    )
        private
        pure
        returns (uint256 partner)
    {
        uint256 sameSide = 0;
        uint256 otherSide = 0;
        for (uint256 ruleIndex = 0; ruleIndex < keyed.length; ++ruleIndex) {
            Rule memory candidate = keyed[ruleIndex].rule;
            (bool isBound, bool candidateIsLength, bool candidateIsLower) = _bound(candidate);
            if (!isBound || candidateIsLength != isLength || candidate.scope != rule.scope) continue;
            if (!LibBytes.eq(candidate.path, rule.path)) continue;
            if (candidateIsLower == isLower) {
                ++sameSide;
            } else {
                ++otherSide;
                partner = ruleIndex;
            }
        }
        if (sameSide != 1 || otherSide != 1) partner = type(uint256).max;
    }

    /// @dev Returns whether the rule places a bound, an unnegated constant `GTE`, `LTE`, `LENGTH_GTE` or `LENGTH_LTE`.
    /// If the rule places a bound, also returns whether it bounds a length and whether it bounds from below.
    function _bound(Rule memory rule) private pure returns (bool isBound, bool isLength, bool isLower) {
        if (rule.scope == PF.SCOPE_LOOP || rule.operator.length != 33) return (false, false, false);
        uint8 opCode = uint8(rule.operator[0]);
        if (opCode == OpCode.GTE) return (true, false, true);
        if (opCode == OpCode.LTE) return (true, false, false);
        if (opCode == OpCode.LENGTH_GTE) return (true, true, true);
        if (opCode == OpCode.LENGTH_LTE) return (true, true, false);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     ENCODING
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the rule with its size-free bytes and its content, its paths compiled from the starting point at
    /// `start`.
    function _keyed(bytes memory desc, Rule memory rule, uint256 start) private pure returns (Keyed memory keyed) {
        keyed.rule = rule;
        if (rule.scope != PF.SCOPE_LOOP) {
            keyed.key = _testBytes(desc, rule.scope, rule.path, rule.operator, start);
            keyed.content = keyed.key;
            return keyed;
        }

        Hint.Compiled memory compiled = Hint.compileLoop(desc, rule.path);
        Hint.requireCompiled(compiled, rule.path, 0);
        BodyRule[] memory body = rule.body;
        // forgefmt: disable-next-item
        bytes memory head = bytes.concat(
            bytes1(PF.SCOPE_LOOP), bytes1(rule.quantifier), _depth(rule.path), rule.path, compiled.hint,
            bytes2(_u16(body.length))
        );
        keyed.key = head;
        keyed.content = head;
        for (uint256 bodyIndex = 0; bodyIndex < body.length; ++bodyIndex) {
            BodyRule memory test = body[bodyIndex];
            bytes memory testBytes = _testBytes(desc, test.scope, test.path, test.operator, compiled.node);
            keyed.key = bytes.concat(keyed.key, testBytes);
            keyed.content = bytes.concat(keyed.content, bytes2(_u16(testBytes.length + PF.RULE_SIZE_SIZE)), testBytes);
        }
    }

    /// @dev Returns a test's size-free bytes, its path compiled from the starting point at `start`.
    function _testBytes(
        bytes memory desc,
        uint8 scope,
        bytes memory path,
        bytes memory operator,
        uint256 start
    )
        private
        pure
        returns (bytes memory)
    {
        if (scope == PF.SCOPE_CONTEXT) {
            uint16 contextPropertyId = Path.atUnchecked(path, 0);
            bytes memory contextOperator = _writeOperator(operator, TypeRule.contextPropertyType(contextPropertyId));
            return abi.encodePacked(PF.SCOPE_CONTEXT, CONTEXT_PATH_DEPTH, contextPropertyId, contextOperator);
        }

        Hint.Compiled memory compiled =
            start == ARGUMENTS ? Hint.compileTest(desc, path) : Hint.compileTest(desc, start, path);
        Hint.requireCompiled(compiled, path, 0);
        (uint8 typeCode,,,) = Descriptor.inspect(desc, compiled.node);
        bytes memory calldataOperator = _writeOperator(operator, typeCode);
        return bytes.concat(bytes1(PF.SCOPE_CALLDATA), _depth(path), path, compiled.hint, calldataOperator);
    }

    /// @dev Returns the operator as the wire carries it against a target of `typeCode`: `opCode | dataLength | data`.
    /// Each constant is narrowed to its operand type's width, and a context property is written as its ID.
    function _writeOperator(bytes memory operator, uint8 typeCode) private pure returns (bytes memory) {
        uint8 opCode = uint8(operator[0]);
        uint8 operandType = OpRule.operandTypeOf(opCode & OpCode.COMPARISON_MASK, typeCode);
        require(operandType != 0, OperatorTargetMismatch(opCode, typeCode));

        bytes memory data;
        if (_source(operator) == OpCode.SOURCE_CONTEXT) {
            data = abi.encodePacked(_u16(uint256(LibBytes.load(operator, 1))));
        } else {
            (uint8 mode, uint256 bits, uint256 width) = TypeRule.canonicalSpec(operandType);
            // Each value is written as a whole word, its next neighbour overwriting the tail, so the buffer runs one
            // word past the widest data the operator's words narrow to.
            data = new bytes(operator.length - 1 + 32);
            uint256 dataSize = 0;
            for (uint256 offset = 1; offset < operator.length; offset += 32) {
                bytes32 word = LibBytes.load(operator, offset);
                require(TypeRule.checkCanonical(mode, bits, word), OutOfPhysicalBounds(word, operandType));
                // A narrow value fills the low bytes of its word, a left-aligned one the high bytes.
                bytes32 narrowed = mode == TypeRule.CANON_LEFT ? word : word << (256 - 8 * width);
                assembly ("memory-safe") {
                    mstore(add(add(data, 32), dataSize), narrowed)
                }
                dataSize += width;
            }
            assembly ("memory-safe") {
                mstore(data, dataSize)
            }
        }
        return abi.encodePacked(opCode, _u16(data.length), data);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     DECODING
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Reads the root rule at `ruleOffset`.
    function _readRule(bytes memory policy, uint256 ruleOffset) private pure returns (Rule memory rule) {
        uint8 scope = uint8(policy[ruleOffset + PF.RULE_SCOPE_OFFSET]);
        if (scope != PF.SCOPE_LOOP) return _rule(_readTest(policy, ruleOffset));

        rule.scope = scope;
        rule.quantifier = uint8(policy[ruleOffset + PF.RULE_QUANTIFIER_OFFSET]);
        uint256 pathStart = ruleOffset + PF.LOOP_DEPTH_OFFSET + PF.RULE_DEPTH_SIZE;
        uint256 hintOffset = pathStart + uint256(uint8(policy[ruleOffset + PF.LOOP_DEPTH_OFFSET])) * PF.PATH_STEP_SIZE;
        rule.path = LibBytes.slice(policy, pathStart, hintOffset);

        // The body follows the frame hint: its hops, the frame prefix, then `ruleCount`.
        uint256 hopCount = uint8(policy[hintOffset]);
        uint256 bodyOffset = hintOffset + PF.HINT_HEADER_SIZE + hopCount * PF.HINT_HOP_SIZE + PF.HINT_FRAME_PREFIX_SIZE;
        rule.hint = LibBytes.slice(policy, hintOffset, bodyOffset);
        rule.body = new BodyRule[](Be16.readUnchecked(policy, bodyOffset));
        uint256 testOffset = bodyOffset + PF.GROUP_RULECOUNT_SIZE;
        for (uint256 bodyIndex = 0; bodyIndex < rule.body.length; ++bodyIndex) {
            rule.body[bodyIndex] = _readTest(policy, testOffset);
            testOffset += Be16.readUnchecked(policy, testOffset);
        }
    }

    /// @dev Reads the test or context test at `ruleOffset`, each constant loaded to its 32-byte word.
    function _readTest(bytes memory policy, uint256 ruleOffset) private pure returns (BodyRule memory test) {
        test.scope = uint8(policy[ruleOffset + PF.RULE_SCOPE_OFFSET]);
        uint256 pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
        uint256 opOffset;
        uint8 typeCode;
        if (test.scope == PF.SCOPE_CONTEXT) {
            opOffset = pathStart + PF.PROPERTY_ID_SIZE;
            test.path = LibBytes.slice(policy, pathStart, opOffset);
            typeCode = TypeRule.contextPropertyType(Be16.readUnchecked(policy, pathStart));
        } else {
            // The hint addresses the target: its hops, then the target block ending in the type code.
            uint256 depth = uint8(policy[ruleOffset + PF.RULE_DEPTH_OFFSET]);
            uint256 hintOffset = pathStart + depth * PF.PATH_STEP_SIZE;
            test.path = LibBytes.slice(policy, pathStart, hintOffset);
            uint256 hopCount = uint8(policy[hintOffset]);
            uint256 targetOffset = hintOffset + PF.HINT_HEADER_SIZE + hopCount * PF.HINT_HOP_SIZE;
            typeCode = uint8(policy[targetOffset + PF.HINT_TARGET_TYPECODE_OFFSET]);
            opOffset = targetOffset + PF.HINT_TARGET_SIZE;
            test.hint = LibBytes.slice(policy, hintOffset, opOffset);
        }

        uint8 opCode = uint8(policy[opOffset]);
        uint256 dataLength = Be16.readUnchecked(policy, opOffset + PF.RULE_OPCODE_SIZE);
        uint256 dataOffset = opOffset + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;
        test.operator = abi.encodePacked(opCode);
        if (_source(test.operator) == OpCode.SOURCE_CONTEXT) {
            test.operator = abi.encodePacked(opCode, uint256(Be16.readUnchecked(policy, dataOffset)));
            return test;
        }
        uint8 operandType = OpRule.operandTypeOf(opCode & OpCode.COMPARISON_MASK, typeCode);
        (uint8 mode,, uint256 width) = TypeRule.canonicalSpec(operandType);
        uint256 valueCount = dataLength / width;
        // forge-lint: disable-next-line(divide-before-multiply) storage validation makes the data whole values.
        bytes memory operator = new bytes(PF.RULE_OPCODE_SIZE + valueCount * 32);
        operator[0] = bytes1(opCode);
        for (uint256 i = 0; i < valueCount; ++i) {
            bytes32 word = TypeRule.loadOperand(LibBytes.load(policy, dataOffset + i * width), mode, width);
            assembly ("memory-safe") {
                mstore(add(add(operator, 33), mul(i, 32)), word)
            }
        }
        test.operator = operator;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Sorts groups by their size-free bytes in place, drops repeats, and returns the number of distinct groups.
    function _sortGroups(bytes[] memory keys, bytes[] memory encodedGroups) private pure returns (uint256 count) {
        for (uint256 position = 1; position < keys.length; ++position) {
            bytes memory key = keys[position];
            bytes memory encoded = encodedGroups[position];
            uint256 insertAt = position;
            while (insertAt > 0 && LibBytes.cmp(key, keys[insertAt - 1]) < 0) {
                keys[insertAt] = keys[insertAt - 1];
                encodedGroups[insertAt] = encodedGroups[insertAt - 1];
                --insertAt;
            }
            keys[insertAt] = key;
            encodedGroups[insertAt] = encoded;
        }
        for (uint256 position = 0; position < keys.length; ++position) {
            if (count != 0 && LibBytes.eq(keys[position], keys[count - 1])) continue;
            keys[count] = keys[position];
            encodedGroups[count] = encodedGroups[position];
            ++count;
        }
    }

    /// @dev Sorts keyed rules by their size-free bytes in place and drops repeats.
    function _sortRules(Keyed[] memory keyed) private pure returns (Keyed[] memory) {
        for (uint256 position = 1; position < keyed.length; ++position) {
            Keyed memory entry = keyed[position];
            uint256 insertAt = position;
            while (insertAt > 0 && LibBytes.cmp(entry.key, keyed[insertAt - 1].key) < 0) {
                keyed[insertAt] = keyed[insertAt - 1];
                --insertAt;
            }
            keyed[insertAt] = entry;
        }
        uint256 count = 0;
        for (uint256 position = 0; position < keyed.length; ++position) {
            if (count != 0 && LibBytes.eq(keyed[position].key, keyed[count - 1].key)) continue;
            keyed[count++] = keyed[position];
        }
        _truncate(keyed, count);
        return keyed;
    }

    /// @dev Returns whether the rule is an `ALL` loop.
    function _isAllLoop(Rule memory rule) private pure returns (bool) {
        return rule.scope == PF.SCOPE_LOOP && rule.quantifier == PF.QUANTIFIER_ALL;
    }

    /// @dev Returns whether the rule is an `ANY` loop whose body contains a calldata test. Such a loop gives its
    /// context tests to the group.
    function _hoists(Rule memory rule) private pure returns (bool) {
        return rule.scope == PF.SCOPE_LOOP && rule.quantifier == PF.QUANTIFIER_ANY
            && _countScope(rule.body, PF.SCOPE_CALLDATA) != 0;
    }

    /// @dev Returns the number of body rules of `scope`.
    function _countScope(BodyRule[] memory body, uint8 scope) private pure returns (uint256 count) {
        for (uint256 bodyIndex = 0; bodyIndex < body.length; ++bodyIndex) {
            if (body[bodyIndex].scope == scope) ++count;
        }
    }

    /// @dev Returns the body rules as rules.
    function _bodyRules(BodyRule[] memory body) private pure returns (Rule[] memory rules) {
        rules = new Rule[](body.length);
        for (uint256 bodyIndex = 0; bodyIndex < body.length; ++bodyIndex) {
            rules[bodyIndex] = _rule(body[bodyIndex]);
        }
    }

    /// @dev Returns the body rule as a rule.
    function _rule(BodyRule memory test) private pure returns (Rule memory rule) {
        rule.scope = test.scope;
        rule.path = test.path;
        rule.hint = test.hint;
        rule.operator = test.operator;
    }

    /// @dev Returns `first` followed by `second`.
    function _concat(Rule[] memory first, Rule[] memory second) private pure returns (Rule[] memory joined) {
        joined = new Rule[](first.length + second.length);
        for (uint256 index = 0; index < first.length; ++index) {
            joined[index] = first[index];
        }
        for (uint256 index = 0; index < second.length; ++index) {
            joined[first.length + index] = second[index];
        }
    }

    /// @dev Returns the operand source of an encoded operator.
    function _source(bytes memory operator) private pure returns (uint8) {
        return (uint8(operator[0]) & ~OpCode.NOT) >> OpCode.SOURCE_SHIFT;
    }

    /// @dev Returns the comparison equal to `NOT comparison`, or zero where none is.
    function _negation(uint8 comparison) private pure returns (uint8) {
        if (comparison == OpCode.GT) return OpCode.LTE;
        if (comparison == OpCode.LT) return OpCode.GTE;
        if (comparison == OpCode.GTE) return OpCode.LT;
        if (comparison == OpCode.LTE) return OpCode.GT;
        if (comparison == OpCode.BITMASK_ANY) return OpCode.BITMASK_NONE;
        if (comparison == OpCode.BITMASK_NONE) return OpCode.BITMASK_ANY;
        if (comparison == OpCode.LENGTH_GT) return OpCode.LENGTH_LTE;
        if (comparison == OpCode.LENGTH_LT) return OpCode.LENGTH_GTE;
        if (comparison == OpCode.LENGTH_GTE) return OpCode.LENGTH_LT;
        if (comparison == OpCode.LENGTH_LTE) return OpCode.LENGTH_GT;
        return 0;
    }

    /// @dev Returns the comparison that holds with subject and operand exchanged, or zero where a context operand
    /// takes none.
    function _swap(uint8 comparison) private pure returns (uint8) {
        if (comparison == OpCode.EQ) return OpCode.EQ;
        if (comparison == OpCode.GT) return OpCode.LT;
        if (comparison == OpCode.LT) return OpCode.GT;
        if (comparison == OpCode.GTE) return OpCode.LTE;
        if (comparison == OpCode.LTE) return OpCode.GTE;
        return 0;
    }

    /// @dev Returns the depth of a path as its one-byte wire field.
    function _depth(bytes memory path) private pure returns (bytes1) {
        // forge-lint: disable-next-line(unsafe-typecast) bounded by `MAX_PATH_DEPTH`.
        return bytes1(uint8(path.length / PF.PATH_STEP_SIZE));
    }

    /// @dev Returns `value` as a two-byte wire field. Requires `value` to fit two bytes.
    function _u16(uint256 value) private pure returns (uint16) {
        // forge-lint: disable-next-line(unsafe-typecast) bounded by the precondition.
        return uint16(value);
    }

    /// @dev Shortens `rules` to its first `count` entries.
    function _truncate(Rule[] memory rules, uint256 count) private pure {
        assembly ("memory-safe") {
            mstore(rules, count)
        }
    }

    /// @dev Shortens `keyed` to its first `count` entries.
    function _truncate(Keyed[] memory keyed, uint256 count) private pure {
        assembly ("memory-safe") {
            mstore(keyed, count)
        }
    }
}

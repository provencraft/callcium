// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Be16 } from "./Be16.sol";
import { Descriptor } from "./Descriptor.sol";
import { Hint } from "./Hint.sol";
import { IssueCode } from "./IssueCode.sol";
import { IssueCollector } from "./IssueCollector.sol";
import { OpCode } from "./OpCode.sol";
import { Policy } from "./Policy.sol";
import { BodyRule, PolicyCoder, PolicyData, Rule } from "./PolicyCoder.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";
import { Issue, RuleLocation, ValidationIssue } from "./ValidationIssue.sol";
import { LibBytes } from "./vendor/solady/utils/LibBytes.sol";

/// @title PolicyValidator
/// @notice Build-time validation of policy blobs (PV-1 to PV-9).
library PolicyValidator {
    using IssueCollector for IssueCollector.Buffer;

    /// @dev State threaded through the checks of a blob's rules.
    struct Walk {
        /// @dev The descriptor.
        bytes desc;
        /// @dev The issues found.
        IssueCollector.Buffer issues;
        /// @dev Identities of the loops of the current group a rule was dropped from.
        bytes32[] lostLoops;
        /// @dev Number of entries of `lostLoops` written.
        uint256 lostCount;
    }

    /// @dev The values of a subject as keys: `width`-bit patterns ordered unsigned, a signed one with its top bit
    /// flipped.
    struct Domain {
        /// @dev The pattern width in bits.
        uint256 width;
        /// @dev The greatest key.
        uint256 max;
        /// @dev The top bit of a signed type's pattern, zero otherwise.
        uint256 flip;
        /// @dev The bits below a left-aligned type's pattern in its word, zero otherwise.
        uint256 shift;
    }

    /// @dev A rule's condition on its subject's key: a range, a set, fixed bits, or relations to a context property.
    struct Literal {
        /// @dev `LITERAL_RANGE`, `LITERAL_SET`, `LITERAL_BITS` or `LITERAL_RELATION`.
        uint8 kind;
        /// @dev Whether the condition is inverted.
        bool negated;
        /// @dev Range: the least key.
        uint256 lower;
        /// @dev Range: the greatest key. The range is empty when `upper` is below `lower`.
        uint256 upper;
        /// @dev Set: the member keys.
        uint256[] members;
        /// @dev Bits: the bits set.
        uint256 ones;
        /// @dev Bits: the bits clear.
        uint256 zeros;
        /// @dev Relation: the context property.
        uint256 property;
        /// @dev Relation: the relations to the property's value admitted, of `LESS`, `EQUAL` and `GREATER`.
        uint256 relations;
    }

    /// @dev A rule on a subject: where it lies, its literal, the context properties it reads and the sides it bounds.
    struct SubjectRule {
        /// @dev The rule.
        RuleLocation location;
        /// @dev Its condition.
        Literal literal;
        /// @dev The context properties it reads, one bit per ID.
        uint256 reads;
        /// @dev The sides of the range it bounds, of `LOWER_SIDE` and `UPPER_SIDE`.
        uint256 sides;
    }

    /// @dev The first `count` literals, the one at `flipped` negated, with their range and fixed bits folded.
    struct Conjunction {
        /// @dev The literals.
        Literal[] literals;
        /// @dev Number of leading `literals` in the conjunction.
        uint256 count;
        /// @dev Index of the literal negated, or `NO_LITERAL`.
        uint256 flipped;
        /// @dev The least key the ranges and context relations admit.
        uint256 lower;
        /// @dev The greatest key the ranges and context relations admit.
        uint256 upper;
        /// @dev The bits the literals fix set.
        uint256 ones;
        /// @dev The bits the literals fix clear.
        uint256 zeros;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                       CONSTANTS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Literal kinds.
    uint8 private constant LITERAL_RANGE = 0;
    uint8 private constant LITERAL_SET = 1;
    uint8 private constant LITERAL_BITS = 2;
    uint8 private constant LITERAL_RELATION = 3;

    /// @dev Relations of a subject to a context property's value: below it, equal to it, above it.
    uint256 private constant LESS = 1;
    uint256 private constant EQUAL = 2;
    uint256 private constant GREATER = 4;
    uint256 private constant ANY_RELATION = LESS | EQUAL | GREATER;

    /// @dev Sides of a subject's range a rule bounds.
    uint256 private constant LOWER_SIDE = 1;
    uint256 private constant UPPER_SIDE = 2;

    /// @dev Index of no literal.
    uint256 private constant NO_LITERAL = type(uint256).max;

    /// @dev Context property of a calldata subject.
    uint256 private constant NO_PROPERTY = type(uint256).max;

    /*/////////////////////////////////////////////////////////////////////////
                                        ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when validation reports any issue.
    /// @param issues Every issue found.
    error ValidationError(Issue[] issues);

    /*/////////////////////////////////////////////////////////////////////////
                                       FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Validates a policy blob (PV-1 to PV-9).
    /// @dev Reverts with the storage validation error of a blob that fails it. Storage validation runs first, because
    /// the descriptor check reads the descriptor before anything is decoded. Reverts with a format overflow error when
    /// a group's normal form exceeds a format limit. Issues of PV-1 to PV-7 name a rule where the blob stores it.
    /// Issues of PV-8 and PV-9 name the group where the blob stores it. They name a rule by its position in the normal
    /// form of the rules left in the group. A rule is left if it raises no PV-2, PV-3, PV-5 or PV-6 issue and no PV-4
    /// issue on a test. PV-8 skips a loop that lost a body test to such an issue.
    /// @param policy The policy blob.
    /// @return Every issue found, or one issue alone when the descriptor is not valid.
    function validate(bytes memory policy) internal pure returns (Issue[] memory) {
        Policy.validate(policy);
        Walk memory walk;
        uint256 descEnd = PF.POLICY_DESC_OFFSET + Be16.readUnchecked(policy, PF.POLICY_DESC_LENGTH_OFFSET);
        walk.desc = LibBytes.slice(policy, PF.POLICY_DESC_OFFSET, descEnd);
        (Descriptor.MetaFault fault, uint256 offset) = Descriptor.tryValidateMeta(walk.desc);
        if (fault != Descriptor.MetaFault.None) {
            walk.issues.push(ValidationIssue.invalidDescriptor(offset));
            return walk.issues.toArray();
        }

        PolicyData memory data = PolicyCoder.decode(policy);
        Rule[][] memory groups = data.groups;
        data.groups = new Rule[][](1);
        for (uint256 groupIndex = 0; groupIndex < groups.length; ++groupIndex) {
            _checkGroup(walk, data, groups[groupIndex], groupIndex);
        }
        return walk.issues.toArray();
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Pushes the issues of a group's rules. Then pushes the PV-8 and PV-9 issues of the normal form of the rules
    /// left, encoded as the only group of `data`.
    function _checkGroup(
        Walk memory walk,
        PolicyData memory data,
        Rule[] memory rules,
        uint256 groupIndex
    )
        private
        pure
    {
        Rule[] memory kept = new Rule[](rules.length);
        uint256 keptCount = 0;
        walk.lostCount = 0;
        for (uint256 ruleIndex = 0; ruleIndex < rules.length; ++ruleIndex) {
            (bool isKept, Rule memory rule) = _checkRule(walk, rules[ruleIndex], groupIndex, ruleIndex);
            if (isKept) kept[keptCount++] = rule;
        }
        if (keptCount == 0) return;
        _truncate(kept, keptCount);
        data.groups[0] = kept;
        Rule[] memory normal = PolicyCoder.decode(PolicyCoder.encode(data)).groups[0];
        _checkBodies(walk, normal, groupIndex);
        _checkGroupSubjects(walk, normal, groupIndex);
    }

    /// @dev Pushes the issues of a root rule. Returns the rule, a loop without the body tests left without a target, or
    /// false when an issue leaves it without a target to analyze.
    function _checkRule(
        Walk memory walk,
        Rule memory rule,
        uint256 groupIndex,
        uint256 ruleIndex
    )
        private
        pure
        returns (bool isKept, Rule memory kept)
    {
        RuleLocation memory location = RuleLocation({
            groupIndex: groupIndex,
            ruleIndex: ruleIndex,
            bodyRuleIndex: ValidationIssue.NO_INDEX,
            scope: rule.scope,
            path: rule.path,
            operator: rule.operator
        });
        if (rule.scope != PF.SCOPE_LOOP) {
            BodyRule memory test = BodyRule(rule.scope, rule.path, rule.hint, rule.operator);
            return (_checkTest(walk, test, false, 0, location), rule);
        }

        uint256 bodyLength = rule.body.length;
        isKept = _checkLoop(walk, rule, location);
        if (!isKept || rule.body.length < bodyLength) _recordLost(walk, rule);
        return (isKept, rule);
    }

    /// @dev Pushes the issues of a loop and its body, dropping the body tests left without a target. Returns false when
    /// its array path does not compile or no body test is left.
    function _checkLoop(Walk memory walk, Rule memory loop, RuleLocation memory location) private pure returns (bool) {
        Hint.Compiled memory compiled = Hint.compileLoop(walk.desc, loop.path);
        if (compiled.fault == Hint.FAULT_NOT_ARRAY) {
            walk.issues.push(ValidationIssue.quantifierOnNonArray(location, compiled.bound));
            return false;
        }
        if (compiled.fault != Hint.FAULT_NONE) {
            walk.issues.push(ValidationIssue.unnavigablePath(location, compiled.stepIndex, compiled.bound));
            return false;
        }
        if (!LibBytes.eq(compiled.hint, loop.hint)) walk.issues.push(ValidationIssue.hintMismatch(location));
        uint256 count = _frameCount(compiled.hint);
        if (count > PF.MAX_QUANTIFIED_ARRAY_LENGTH) {
            walk.issues.push(ValidationIssue.quantifierOverStaticLimit(location, count, PF.MAX_QUANTIFIED_ARRAY_LENGTH));
        }

        BodyRule[] memory body = loop.body;
        uint256 keptCount = 0;
        for (uint256 bodyIndex = 0; bodyIndex < body.length; ++bodyIndex) {
            BodyRule memory test = body[bodyIndex];
            RuleLocation memory testLocation = RuleLocation({
                groupIndex: location.groupIndex,
                ruleIndex: location.ruleIndex,
                bodyRuleIndex: bodyIndex,
                scope: test.scope,
                path: test.path,
                operator: test.operator
            });
            if (_checkTest(walk, test, true, compiled.node, testLocation)) body[keptCount++] = test;
        }
        _truncate(body, keptCount);
        return keptCount != 0;
    }

    /// @dev Pushes the issues of a test, from the arguments or, when `inBody`, from the loop element whose node lies at
    /// `element`. Returns false when an issue leaves it without a target to analyze or its hint differs from its
    /// path's.
    function _checkTest(
        Walk memory walk,
        BodyRule memory test,
        bool inBody,
        uint256 element,
        RuleLocation memory location
    )
        private
        pure
        returns (bool)
    {
        uint8 typeCode;
        bool hintMatches = true;
        if (test.scope == PF.SCOPE_CONTEXT) {
            typeCode = TypeRule.contextPropertyType(Be16.readUnchecked(test.path, 0));
        } else {
            Hint.Compiled memory compiled =
                inBody ? Hint.compileTest(walk.desc, element, test.path) : Hint.compileTest(walk.desc, test.path);
            if (compiled.fault != Hint.FAULT_NONE) {
                walk.issues.push(ValidationIssue.unnavigablePath(location, compiled.stepIndex, compiled.bound));
                return false;
            }
            hintMatches = LibBytes.eq(compiled.hint, test.hint);
            if (!hintMatches) walk.issues.push(ValidationIssue.hintMismatch(location));
            typeCode = uint8(walk.desc[compiled.node]);
        }
        // A test whose hint differs from its path's has constants sized to the hint's type, so it leaves the analysis.
        return _checkOperator(walk, test.operator, typeCode, location) && hintMatches;
    }

    /// @dev Pushes the PV-5 and PV-6 issues of an operator against a target of `typeCode`. Returns false when the
    /// operator raises an issue.
    function _checkOperator(
        Walk memory walk,
        bytes memory operator,
        uint8 typeCode,
        RuleLocation memory location
    )
        private
        pure
        returns (bool)
    {
        uint8 opCode = uint8(operator[0]);
        uint8 comparison = opCode & OpCode.COMPARISON_MASK;
        if ((opCode & ~OpCode.NOT) >> OpCode.SOURCE_SHIFT == OpCode.SOURCE_CONTEXT) {
            uint256 contextPropertyId = uint256(LibBytes.load(operator, 1));
            // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the operand word's property ID.
            uint8 propertyType = TypeRule.contextPropertyType(uint16(contextPropertyId));
            if (_pairsWithContext(comparison, typeCode, propertyType)) return true;
            walk.issues.push(ValidationIssue.contextTypeMismatch(location, contextPropertyId, typeCode));
            return false;
        }

        (bytes32 code, string memory message) = _incompatibility(comparison, typeCode);
        if (code != bytes32(0)) {
            walk.issues.push(ValidationIssue.fromOpRule(code, message, location, opCode));
            return false;
        }
        if (typeCode != TypeCode.BOOL) return true;
        for (uint256 offset = 1; offset < operator.length; offset += 32) {
            uint256 value = uint256(LibBytes.load(operator, offset));
            if (value > 1) {
                walk.issues.push(ValidationIssue.outOfPhysicalBounds(location, value));
                return false;
            }
        }
        return true;
    }

    /// @dev Returns the code and message a constant comparison raises against its target type, or a zero code
    /// when the comparison applies.
    function _incompatibility(
        uint8 comparison,
        uint8 typeCode
    )
        private
        pure
        returns (bytes32 code, string memory message)
    {
        bool isOrdering = comparison == OpCode.GT || comparison == OpCode.LT || comparison == OpCode.GTE
            || comparison == OpCode.LTE || comparison == OpCode.BETWEEN;
        if (isOrdering && !_isNumeric(typeCode)) {
            return (IssueCode.NUMERIC_OP_ON_NON_NUMERIC, "Comparison operator used on non-numeric type");
        }
        if (comparison == OpCode.IN && typeCode == TypeCode.BOOL) {
            return (IssueCode.IN_ON_BOOL, "IN operator used on boolean type");
        }
        bool isMask =
            comparison == OpCode.BITMASK_ALL || comparison == OpCode.BITMASK_ANY || comparison == OpCode.BITMASK_NONE;
        if (isMask && (typeCode == TypeCode.BOOL || typeCode == TypeCode.FUNCTION)) {
            return (IssueCode.BITMASK_ON_INVALID, "Bitmask operator used on incompatible type");
        }
    }

    /// @dev Returns true when a context operand of `propertyType` pairs with a target of `typeCode` under `comparison`.
    function _pairsWithContext(uint8 comparison, uint8 typeCode, uint8 propertyType) private pure returns (bool) {
        if (_isUnsigned(typeCode)) return propertyType == TypeCode.UINT256;
        return comparison == OpCode.EQ && typeCode == TypeCode.ADDRESS && propertyType == TypeCode.ADDRESS;
    }

    /// @dev Returns true for a `uintN` type code.
    function _isUnsigned(uint8 typeCode) private pure returns (bool) {
        return typeCode >= TypeCode.UINT8 && typeCode <= TypeCode.UINT256;
    }

    /// @dev Returns true for a `uintN` or `intN` type code.
    function _isNumeric(uint8 typeCode) private pure returns (bool) {
        return _isUnsigned(typeCode) || (typeCode >= TypeCode.INT8 && typeCode <= TypeCode.INT256);
    }

    /// @dev Returns the declared length a loop's frame hint carries, or zero for a dynamic array.
    function _frameCount(bytes memory hint) private pure returns (uint256) {
        uint256 hopCount = uint8(hint[0]);
        return Be16.readUnchecked(hint, PF.HINT_HEADER_SIZE + hopCount * PF.HINT_HOP_SIZE + PF.HINT_FRAME_COUNT_OFFSET);
    }

    /// @dev Pushes a PV-8 issue for each loop of a group's normal form whose body contains no calldata test. Skips a
    /// loop if the group lost a test from a loop with the same quantifier and array path.
    function _checkBodies(Walk memory walk, Rule[] memory rules, uint256 groupIndex) private pure {
        for (uint256 ruleIndex = 0; ruleIndex < rules.length; ++ruleIndex) {
            Rule memory rule = rules[ruleIndex];
            if (rule.scope != PF.SCOPE_LOOP || _isLost(walk, rule) || _readsElement(rule.body)) continue;
            walk.issues
                .push(
                    ValidationIssue.contextOnlyBody(
                        RuleLocation({
                            groupIndex: groupIndex,
                            ruleIndex: ruleIndex,
                            bodyRuleIndex: ValidationIssue.NO_INDEX,
                            scope: rule.scope,
                            path: rule.path,
                            operator: ""
                        })
                    )
                );
        }
    }

    /// @dev Returns true when a body contains a calldata test.
    function _readsElement(BodyRule[] memory body) private pure returns (bool) {
        for (uint256 bodyIndex = 0; bodyIndex < body.length; ++bodyIndex) {
            if (body[bodyIndex].scope == PF.SCOPE_CALLDATA) return true;
        }
        return false;
    }

    /// @dev Records a loop a rule was dropped from, by its quantifier and array path.
    function _recordLost(Walk memory walk, Rule memory loop) private pure {
        if (walk.lostCount == walk.lostLoops.length) {
            bytes32[] memory grown = new bytes32[](walk.lostCount == 0 ? 1 : walk.lostCount * 2);
            for (uint256 i = 0; i < walk.lostCount; ++i) {
                grown[i] = walk.lostLoops[i];
            }
            walk.lostLoops = grown;
        }
        walk.lostLoops[walk.lostCount++] = _loopKey(loop);
    }

    /// @dev Returns true when a loop with the quantifier and array path of `loop` lost a rule.
    function _isLost(Walk memory walk, Rule memory loop) private pure returns (bool) {
        bytes32 key = _loopKey(loop);
        for (uint256 i = 0; i < walk.lostCount; ++i) {
            if (walk.lostLoops[i] == key) return true;
        }
        return false;
    }

    /// @dev Returns the identity of a loop within its group across normalization: its quantifier and its array path.
    function _loopKey(Rule memory loop) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(loop.quantifier, loop.path));
    }

    /// @dev Pushes the PV-9 issues of a group's normal form: its tests and context tests, then each loop body apart.
    function _checkGroupSubjects(Walk memory walk, Rule[] memory rules, uint256 groupIndex) private pure {
        uint256 testCount = 0;
        for (uint256 ruleIndex = 0; ruleIndex < rules.length; ++ruleIndex) {
            if (rules[ruleIndex].scope != PF.SCOPE_LOOP) ++testCount;
        }
        BodyRule[] memory tests = new BodyRule[](testCount);
        RuleLocation[] memory locations = new RuleLocation[](testCount);
        testCount = 0;
        for (uint256 ruleIndex = 0; ruleIndex < rules.length; ++ruleIndex) {
            Rule memory rule = rules[ruleIndex];
            if (rule.scope == PF.SCOPE_LOOP) continue;
            tests[testCount] = BodyRule(rule.scope, rule.path, rule.hint, rule.operator);
            locations[testCount++] = RuleLocation({
                groupIndex: groupIndex,
                ruleIndex: ruleIndex,
                bodyRuleIndex: ValidationIssue.NO_INDEX,
                scope: rule.scope,
                path: rule.path,
                operator: rule.operator
            });
        }
        _checkSubjects(walk, tests, locations);

        for (uint256 ruleIndex = 0; ruleIndex < rules.length; ++ruleIndex) {
            Rule memory rule = rules[ruleIndex];
            if (rule.scope != PF.SCOPE_LOOP) continue;
            RuleLocation[] memory bodyLocations = new RuleLocation[](rule.body.length);
            for (uint256 bodyRuleIndex = 0; bodyRuleIndex < rule.body.length; ++bodyRuleIndex) {
                BodyRule memory test = rule.body[bodyRuleIndex];
                bodyLocations[bodyRuleIndex] = RuleLocation({
                    groupIndex: groupIndex,
                    ruleIndex: ruleIndex,
                    bodyRuleIndex: bodyRuleIndex,
                    scope: test.scope,
                    path: test.path,
                    operator: test.operator
                });
            }
            _checkSubjects(walk, rule.body, bodyLocations);
        }
    }

    /// @dev Pushes the PV-9 issues of the tests of a group or a loop body, subject by subject in order of first
    /// appearance.
    function _checkSubjects(Walk memory walk, BodyRule[] memory tests, RuleLocation[] memory locations) private pure {
        bool[] memory done = new bool[](tests.length);
        for (uint256 first = 0; first < tests.length; ++first) {
            if (done[first]) continue;
            BodyRule memory subject = tests[first];
            uint256 subjectProperty = NO_PROPERTY;
            uint8 typeCode;
            if (subject.scope == PF.SCOPE_CONTEXT) {
                uint16 contextPropertyId = Be16.readUnchecked(subject.path, 0);
                subjectProperty = contextPropertyId;
                typeCode = TypeRule.contextPropertyType(contextPropertyId);
            } else {
                typeCode = uint8(subject.hint[subject.hint.length - 1]);
            }
            Domain memory domain = _domainOf(typeCode);

            uint256 ruleCount = 0;
            for (uint256 index = first; index < tests.length; ++index) {
                if (_onSubject(tests[index], subject)) ++ruleCount;
            }
            SubjectRule[] memory rules = new SubjectRule[](ruleCount);
            ruleCount = 0;
            for (uint256 index = first; index < tests.length; ++index) {
                if (!_onSubject(tests[index], subject)) continue;
                done[index] = true;
                rules[ruleCount++] = _subjectRule(domain, tests[index], locations[index], subjectProperty);
            }
            _checkSubject(walk, domain, TypeRule.hasCalldataLength(typeCode), rules);
        }
    }

    /// @dev Returns true when `test` compares the subject of `subject`.
    function _onSubject(BodyRule memory test, BodyRule memory subject) private pure returns (bool) {
        return test.scope == subject.scope && LibBytes.eq(test.path, subject.path);
    }

    /// @dev Returns a test as a rule on its subject, whose context property is `subjectProperty` for a context test.
    function _subjectRule(
        Domain memory domain,
        BodyRule memory test,
        RuleLocation memory location,
        uint256 subjectProperty
    )
        private
        pure
        returns (SubjectRule memory rule)
    {
        rule.location = location;
        (rule.literal, rule.sides) = _literalOf(domain, test.operator, subjectProperty);
        if (subjectProperty != NO_PROPERTY) rule.reads = 1 << subjectProperty;
        if (rule.literal.kind == LITERAL_RELATION) rule.reads |= 1 << rule.literal.property;
    }

    /// @dev Pushes the PV-9 issues of the rules on one subject, in normal-form order. If the rules stop being
    /// satisfiable together, pushes one issue for the rule at which they stop, and nothing else. Otherwise, pushes an
    /// issue for each rule that holds for every value and context and for each other rule the others imply. Then,
    /// among the rules not yet named, pushes an issue for each constant bound looser than the tightest on its side.
    function _checkSubject(
        Walk memory walk,
        Domain memory domain,
        bool isLength,
        SubjectRule[] memory rules
    )
        private
        pure
    {
        Literal[] memory literals = new Literal[](rules.length);
        for (uint256 index = 0; index < rules.length; ++index) {
            literals[index] = rules[index].literal;
        }
        for (uint256 count = 1; count <= literals.length; ++count) {
            if (_satisfiable(domain, literals, count, NO_LITERAL)) continue;
            walk.issues.push(ValidationIssue.contradictoryRule(rules[count - 1].location));
            return;
        }

        bool[] memory named = new bool[](rules.length);
        Literal[] memory single = new Literal[](1);
        for (uint256 index = 0; index < rules.length; ++index) {
            SubjectRule memory rule = rules[index];
            single[0] = rule.literal;
            if (rule.reads == 0 && !_satisfiable(domain, single, 1, 0)) {
                walk.issues.push(ValidationIssue.vacuousRule(rule.location));
                named[index] = true;
                continue;
            }
            uint256 othersRead = 0;
            for (uint256 other = 0; other < rules.length; ++other) {
                if (other != index) othersRead |= rules[other].reads;
            }
            if (rule.reads & ~othersRead != 0 || _satisfiable(domain, literals, literals.length, index)) continue;
            walk.issues.push(ValidationIssue.redundantRule(rule.location));
            named[index] = true;
        }
        _checkBounds(walk, domain, isLength, rules, named);
    }

    /// @dev Pushes an issue for each constant bound of a rule not in `named` looser than the tightest on its side among
    /// those rules.
    function _checkBounds(
        Walk memory walk,
        Domain memory domain,
        bool isLength,
        SubjectRule[] memory rules,
        bool[] memory named
    )
        private
        pure
    {
        uint256 tightestLower = 0;
        uint256 tightestUpper = domain.max;
        for (uint256 index = 0; index < rules.length; ++index) {
            Literal memory literal = rules[index].literal;
            if (named[index] || literal.kind != LITERAL_RANGE) continue;
            if (rules[index].sides & LOWER_SIDE != 0 && literal.lower > tightestLower) tightestLower = literal.lower;
            if (rules[index].sides & UPPER_SIDE != 0 && literal.upper < tightestUpper) tightestUpper = literal.upper;
        }
        for (uint256 index = 0; index < rules.length; ++index) {
            SubjectRule memory rule = rules[index];
            if (named[index] || rule.literal.kind != LITERAL_RANGE) continue;
            uint256 bound = 0;
            uint256 tightest = 0;
            if (rule.sides & LOWER_SIDE != 0 && rule.literal.lower < tightestLower) {
                (bound, tightest) = (rule.literal.lower, tightestLower);
            } else if (rule.sides & UPPER_SIDE != 0 && rule.literal.upper > tightestUpper) {
                (bound, tightest) = (rule.literal.upper, tightestUpper);
            } else {
                continue;
            }
            walk.issues
                .push(
                    ValidationIssue.dominatedBound(
                        isLength, rule.location, _wordOf(domain, bound), _wordOf(domain, tightest)
                    )
                );
        }
    }

    /// @dev Returns the domain of a subject of `typeCode`. A length compares as 256 bits.
    function _domainOf(uint8 typeCode) private pure returns (Domain memory domain) {
        (uint8 mode, uint256 bits,) = TypeRule.canonicalSpec(typeCode);
        domain.width = mode == TypeRule.CANON_SIGNED ? 8 * (bits + 1) : bits;
        domain.max = type(uint256).max >> (256 - domain.width);
        if (mode == TypeRule.CANON_SIGNED) domain.flip = 1 << (domain.width - 1);
        if (mode == TypeRule.CANON_LEFT) domain.shift = 256 - domain.width;
    }

    /// @dev Returns the pattern a loaded word contains.
    function _patternOf(Domain memory domain, uint256 word) private pure returns (uint256) {
        return (word >> domain.shift) & domain.max;
    }

    /// @dev Returns the key of the operand value at `index` of an operator.
    function _keyAt(Domain memory domain, bytes memory operator, uint256 index) private pure returns (uint256) {
        return _patternOf(domain, uint256(LibBytes.load(operator, 1 + 32 * index))) ^ domain.flip;
    }

    /// @dev Returns the word a key of a numeric or length subject loads from.
    function _wordOf(Domain memory domain, uint256 key) private pure returns (uint256) {
        uint256 pattern = key ^ domain.flip;
        return pattern & domain.flip == 0 ? pattern : pattern | ~domain.max;
    }

    /// @dev Returns the relations to a context property's value a comparison admits.
    function _relationsOf(uint8 comparison) private pure returns (uint256) {
        if (comparison == OpCode.EQ) return EQUAL;
        if (comparison == OpCode.GT) return GREATER;
        if (comparison == OpCode.LT) return LESS;
        if (comparison == OpCode.GTE) return GREATER | EQUAL;
        return LESS | EQUAL;
    }

    /// @dev Returns the literal of an operator on a subject, and the sides it bounds. `subjectProperty` is the context
    /// property a context test compares, which a context operand naming it equals.
    function _literalOf(
        Domain memory domain,
        bytes memory operator,
        uint256 subjectProperty
    )
        private
        pure
        returns (Literal memory literal, uint256 sides)
    {
        uint8 opCode = uint8(operator[0]);
        bool negated = opCode & OpCode.NOT != 0;
        uint8 comparison = opCode & OpCode.COMPARISON_MASK;

        if ((opCode & ~OpCode.NOT) >> OpCode.SOURCE_SHIFT == OpCode.SOURCE_CONTEXT) {
            uint256 property = uint256(LibBytes.load(operator, 1));
            uint256 relations = _relationsOf(comparison);
            if (property != subjectProperty) {
                literal.kind = LITERAL_RELATION;
                literal.property = property;
                literal.relations = relations;
            } else if (relations & EQUAL != 0) {
                literal.upper = domain.max;
            } else {
                literal.lower = 1;
            }
        } else if (comparison == OpCode.EQ || comparison == OpCode.LENGTH_EQ) {
            literal.kind = LITERAL_SET;
            literal.members = new uint256[](1);
            literal.members[0] = _keyAt(domain, operator, 0);
        } else if (comparison == OpCode.IN) {
            literal.kind = LITERAL_SET;
            literal.members = new uint256[]((operator.length - 1) / 32);
            for (uint256 index = 0; index < literal.members.length; ++index) {
                literal.members[index] = _keyAt(domain, operator, index);
            }
        } else if (comparison == OpCode.GT || comparison == OpCode.LENGTH_GT) {
            uint256 key = _keyAt(domain, operator, 0);
            (literal.lower, literal.upper) = key == domain.max ? (1, 0) : (key + 1, domain.max);
            sides = LOWER_SIDE;
        } else if (comparison == OpCode.LT || comparison == OpCode.LENGTH_LT) {
            uint256 key = _keyAt(domain, operator, 0);
            (literal.lower, literal.upper) = key == 0 ? (1, 0) : (0, key - 1);
            sides = UPPER_SIDE;
        } else if (comparison == OpCode.GTE || comparison == OpCode.LENGTH_GTE) {
            (literal.lower, literal.upper) = (_keyAt(domain, operator, 0), domain.max);
            sides = LOWER_SIDE;
        } else if (comparison == OpCode.LTE || comparison == OpCode.LENGTH_LTE) {
            literal.upper = _keyAt(domain, operator, 0);
            sides = UPPER_SIDE;
        } else if (comparison == OpCode.BETWEEN || comparison == OpCode.LENGTH_BETWEEN) {
            (literal.lower, literal.upper) = (_keyAt(domain, operator, 0), _keyAt(domain, operator, 1));
            sides = LOWER_SIDE | UPPER_SIDE;
        } else {
            // A mask's top bit asks the opposite of a signed key's top bit.
            uint256 mask = _patternOf(domain, uint256(LibBytes.load(operator, 1)));
            uint256 set = mask & (domain.max ^ domain.flip);
            uint256 flipped = mask & domain.flip;
            literal.kind = LITERAL_BITS;
            (literal.ones, literal.zeros) = comparison == OpCode.BITMASK_ALL ? (set, flipped) : (flipped, set);
            literal.negated = comparison == OpCode.BITMASK_ANY;
        }
        literal.negated = literal.negated != negated;
        if (negated) sides = 0;
    }

    /// @dev Returns true when the literal at `index` is negated in a conjunction.
    function _isNegated(Conjunction memory conjunction, uint256 index) private pure returns (bool) {
        return conjunction.literals[index].negated != (index == conjunction.flipped);
    }

    /// @dev Returns true when some key and some context meet the first `count` literals, the literal at `flipped`
    /// negated. A context property each literal reads is present.
    function _satisfiable(
        Domain memory domain,
        Literal[] memory literals,
        uint256 count,
        uint256 flipped
    )
        private
        pure
        returns (bool)
    {
        Conjunction memory conjunction = Conjunction(literals, count, flipped, 0, domain.max, 0, 0);
        uint256[] memory relations = new uint256[](uint256(PF.CTX_MAX) + 1);
        for (uint256 property = 0; property < relations.length; ++property) {
            relations[property] = ANY_RELATION;
        }
        uint256 firstSet = NO_LITERAL;
        for (uint256 index = 0; index < count; ++index) {
            Literal memory literal = literals[index];
            bool negated = _isNegated(conjunction, index);
            if (literal.kind == LITERAL_RELATION) {
                relations[literal.property] &= negated ? ANY_RELATION ^ literal.relations : literal.relations;
            } else if (negated) {
                continue;
            } else if (literal.kind == LITERAL_RANGE) {
                if (literal.lower > conjunction.lower) conjunction.lower = literal.lower;
                if (literal.upper < conjunction.upper) conjunction.upper = literal.upper;
            } else if (literal.kind == LITERAL_BITS) {
                conjunction.ones |= literal.ones;
                conjunction.zeros |= literal.zeros;
            } else if (firstSet == NO_LITERAL) {
                firstSet = index;
            }
        }

        // A context property's value lies anywhere in its type, so the relations left to it bound the subject's key.
        for (uint16 property = 0; property <= PF.CTX_MAX; ++property) {
            uint256 held = relations[property];
            if (held == 0) return false;
            if (held == LESS) {
                uint256 propertyMax = _domainOf(TypeRule.contextPropertyType(property)).max;
                if (propertyMax - 1 < conjunction.upper) conjunction.upper = propertyMax - 1;
            }
            if (held == GREATER && conjunction.lower < 1) conjunction.lower = 1;
        }
        if (conjunction.ones & conjunction.zeros != 0 || conjunction.lower > conjunction.upper) return false;

        if (firstSet != NO_LITERAL) {
            uint256[] memory members = literals[firstSet].members;
            for (uint256 index = 0; index < members.length; ++index) {
                if (_admits(conjunction, members[index])) return true;
            }
            return false;
        }

        // Each step passes one hole or one excluded key, so the walk takes at most one step per literal member.
        (bool found, uint256 key) = _nextKey(conjunction, domain.max, conjunction.lower);
        while (found && key <= conjunction.upper) {
            (bool excluded, uint256 end) = _excludedTo(conjunction, key);
            if (!excluded) return true;
            if (end >= conjunction.upper) return false;
            (found, key) = _nextKey(conjunction, domain.max, end + 1);
        }
        return false;
    }

    /// @dev Returns true when `key` meets every literal of a conjunction.
    function _admits(Conjunction memory conjunction, uint256 key) private pure returns (bool) {
        if (key < conjunction.lower || key > conjunction.upper || !_meetsBits(conjunction, key)) return false;
        for (uint256 index = 0; index < conjunction.count; ++index) {
            Literal memory literal = conjunction.literals[index];
            if (literal.kind == LITERAL_SET && _contains(literal.members, key) == _isNegated(conjunction, index)) {
                return false;
            }
        }
        (bool excluded,) = _excludedTo(conjunction, key);
        return !excluded;
    }

    /// @dev Returns whether `key` lies in a negated range or set of a conjunction, and the greatest key that literal
    /// excludes from `key` on.
    function _excludedTo(Conjunction memory conjunction, uint256 key)
        private
        pure
        returns (bool excluded, uint256 end)
    {
        for (uint256 index = 0; index < conjunction.count; ++index) {
            Literal memory literal = conjunction.literals[index];
            if (!_isNegated(conjunction, index)) continue;
            if (literal.kind == LITERAL_RANGE && literal.lower <= key && key <= literal.upper) {
                return (true, literal.upper);
            }
            if (literal.kind == LITERAL_SET && _contains(literal.members, key)) return (true, key);
        }
    }

    /// @dev Returns true when `members` contains `key`.
    function _contains(uint256[] memory members, uint256 key) private pure returns (bool) {
        for (uint256 index = 0; index < members.length; ++index) {
            if (members[index] == key) return true;
        }
        return false;
    }

    /// @dev Returns true when `key` meets the fixed bits and every negated bits literal of a conjunction.
    function _meetsBits(Conjunction memory conjunction, uint256 key) private pure returns (bool) {
        if (key & conjunction.ones != conjunction.ones || key & conjunction.zeros != 0) return false;
        for (uint256 index = 0; index < conjunction.count; ++index) {
            Literal memory literal = conjunction.literals[index];
            if (literal.kind != LITERAL_BITS || !_isNegated(conjunction, index)) continue;
            if (key & literal.ones == literal.ones && key & literal.zeros == 0) return false;
        }
        return true;
    }

    /// @dev Returns the least key from `from` up that meets the fixed bits and every negated bits literal. If `from`
    /// meets these conditions, the key is `from`. Otherwise the key sets the lowest clear bit of `from` that can be set
    /// and keeps the bits of `from` above that bit. The key completes the bits below that bit, least first.
    function _nextKey(
        Conjunction memory conjunction,
        uint256 max,
        uint256 from
    )
        private
        pure
        returns (bool found, uint256 key)
    {
        if (_meetsBits(conjunction, from)) return (true, from);
        for (uint256 bit = 1; bit != 0 && bit <= max; bit <<= 1) {
            if (from & bit != 0) continue;
            uint256 fixedBits = max ^ (bit - 1);
            key = (from & fixedBits) | bit;
            if (!_completable(conjunction, max, fixedBits, key)) continue;
            for (uint256 lowBit = bit >> 1; lowBit != 0; lowBit >>= 1) {
                fixedBits |= lowBit;
                if (!_completable(conjunction, max, fixedBits, key)) key |= lowBit;
            }
            return (true, key);
        }
        return (false, 0);
    }

    /// @dev Returns true when some key whose bits in `fixedBits` are those of `key` meets the fixed bits and every
    /// negated bits literal.
    function _completable(
        Conjunction memory conjunction,
        uint256 max,
        uint256 fixedBits,
        uint256 key
    )
        private
        pure
        returns (bool)
    {
        if (key & conjunction.zeros != 0 || conjunction.ones & fixedBits & ~key != 0) return false;
        uint256 known = fixedBits | conjunction.ones | conjunction.zeros;
        return _solvable(conjunction, max, known, key | conjunction.ones);
    }

    /// @dev Returns true when some assignment of the bits outside `known` meets every negated bits literal, with the
    /// known bits as in `value`. Propagates the literals left with one free bit, then branches on the free bits of the
    /// first literal left open, each branch meeting that literal. Therefore the recursion runs at most one level
    /// per negated bits literal.
    function _solvable(
        Conjunction memory conjunction,
        uint256 max,
        uint256 known,
        uint256 value
    )
        private
        pure
        returns (bool)
    {
        uint256 openOnes = 0;
        uint256 openZeros = 0;
        uint256 index = 0;
        while (index < conjunction.count) {
            Literal memory literal = conjunction.literals[index++];
            if (literal.kind != LITERAL_BITS || !_isNegated(conjunction, index - 1)) continue;
            if (literal.ones & known & ~value != 0 || literal.zeros & known & value != 0) continue;
            uint256 ones = literal.ones & max & ~known;
            uint256 zeros = literal.zeros & max & ~known;
            uint256 free = ones | zeros;
            if (free == 0) return false;
            if (free & (free - 1) == 0) {
                known |= free;
                value = ones == 0 ? value | free : value & ~free;
                (openOnes, openZeros, index) = (0, 0, 0);
            } else if (openOnes | openZeros == 0) {
                (openOnes, openZeros) = (ones, zeros);
            }
        }
        if (openOnes | openZeros == 0) return true;

        // Each branch clears one free bit the literal wants set, or sets one it wants clear; a failed branch's bit then
        // takes the other value.
        for (uint256 free = openOnes | openZeros; free != 0; free &= free - 1) {
            uint256 bit;
            unchecked {
                bit = free & (~free + 1);
            }
            uint256 meeting = openOnes & bit != 0 ? value & ~bit : value | bit;
            if (_solvable(conjunction, max, known | bit, meeting)) return true;
            known |= bit;
            value = meeting ^ bit;
        }
        return false;
    }

    /// @dev Shortens `rules` to its first `count` entries.
    function _truncate(Rule[] memory rules, uint256 count) private pure {
        assembly ("memory-safe") {
            mstore(rules, count)
        }
    }

    /// @dev Shortens `body` to its first `count` entries.
    function _truncate(BodyRule[] memory body, uint256 count) private pure {
        assembly ("memory-safe") {
            mstore(body, count)
        }
    }
}

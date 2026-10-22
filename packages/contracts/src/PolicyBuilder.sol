// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Constraint, Operator } from "./Constraint.sol";
import { DescriptorBuilder } from "./DescriptorBuilder.sol";
import { Hint } from "./Hint.sol";
import { OpCode } from "./OpCode.sol";
import { OpRule } from "./OpRule.sol";
import { Path } from "./Path.sol";
import { BodyRule, PolicyCoder, PolicyData, Rule } from "./PolicyCoder.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { PolicyValidator } from "./PolicyValidator.sol";
import { SignatureParser } from "./SignatureParser.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";
import { Issue } from "./ValidationIssue.sol";
import { LibBytes } from "./vendor/solady/utils/LibBytes.sol";

/// @notice Internal state for drafting a policy.
struct PolicyDraft {
    /// The policy data, its rules as added.
    PolicyData data;
}

using PolicyBuilder for PolicyDraft global;

/// @title PolicyBuilder
/// @notice Fluent API for drafting policies from constraints.
library PolicyBuilder {
    /*/////////////////////////////////////////////////////////////////////////
                                        ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the constraint has no operators.
    error NoConstraintOperators();

    /// @notice Thrown when a context-scope path does not have exactly one step.
    /// @param depth The path depth.
    error InvalidContextPath(uint256 depth);

    /// @notice Thrown when a path step lies in the reserved marker range and is neither `Path.ALL` nor `Path.ANY`.
    /// @param path The encoded be16 path.
    /// @param stepIndex The step index of the marker.
    error UnknownPathStep(bytes path, uint256 stepIndex);

    /// @notice Thrown when a path contains more than one quantifier step.
    /// @param path The encoded be16 path.
    /// @param stepIndex The step index of the second quantifier.
    error InvalidNestedLoop(bytes path, uint256 stepIndex);

    /// @notice Thrown when a set contains more members than the data length can represent at its operand type's width.
    error SetTooLarge();

    /// @notice Thrown when a group is empty.
    /// @param groupIndex The index of the empty group.
    error EmptyGroup(uint256 groupIndex);

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a selectorless draft from a comma-separated type list.
    /// @param typesCsv The comma-separated ABI types (for example "uint256,address").
    /// @return draft The initialized draft.
    function createRaw(string memory typesCsv) internal pure returns (PolicyDraft memory draft) {
        draft.data.isSelectorless = true;
        draft.data.selector = bytes4(0);
        draft.data.descriptor = DescriptorBuilder.fromTypes(typesCsv);
        draft.data.groups = new Rule[][](1);
        draft.data.groups[0] = new Rule[](0);
    }

    /// @notice Creates a draft from a function signature.
    /// @param signature The function signature.
    /// @return draft The initialized draft.
    function create(string memory signature) internal pure returns (PolicyDraft memory draft) {
        (bytes4 selector, string memory typesCsv) = SignatureParser.parseSelectorAndTypes(signature);
        draft = createRaw(typesCsv);
        draft.data.isSelectorless = false;
        draft.data.selector = selector;
    }

    /// @notice Adds a constraint to the active group with validation. A path through `Path.ALL` or `Path.ANY` adds
    /// its operators to the body of the group's loop over that array with that quantifier.
    /// @param draft The draft state.
    /// @param constraint The constraint to add.
    /// @return The updated draft state with the constraint's rules appended.
    function add(PolicyDraft memory draft, Constraint memory constraint) internal pure returns (PolicyDraft memory) {
        require(constraint.operators.length != 0, NoConstraintOperators());

        uint256 depth = Path.validate(constraint.path);
        if (constraint.scope == PF.SCOPE_CONTEXT) _addContextTests(draft, constraint, depth);
        else if (constraint.scope == PF.SCOPE_CALLDATA) _addCalldataTests(draft, constraint, depth);
        else revert PolicyCoder.UnknownScope(constraint.scope);
        return draft;
    }

    /// @notice Starts a new constraint group (OR semantics between groups).
    /// @param draft The draft state.
    /// @return The updated draft state with a new empty group.
    function or(PolicyDraft memory draft) internal pure returns (PolicyDraft memory) {
        uint256 last = draft.data.groups.length - 1;
        require(draft.data.groups[last].length != 0, EmptyGroup(last));

        uint256 newGroupIndex = draft.data.groups.length;

        Rule[][] memory nextGroups = new Rule[][](newGroupIndex + 1);
        for (uint256 i = 0; i < newGroupIndex; ++i) {
            nextGroups[i] = draft.data.groups[i];
        }
        nextGroups[newGroupIndex] = new Rule[](0);

        draft.data.groups = nextGroups;

        return draft;
    }

    /// @notice Builds the final policy blob with strict validation.
    /// @dev Reverts with the storage validation error of a blob that fails it, and with every validation issue when
    /// there is any.
    /// @param draft The draft state to build from.
    /// @return policy The encoded policy blob.
    function build(PolicyDraft memory draft) internal pure returns (bytes memory policy) {
        policy = buildUnsafe(draft);
        Issue[] memory issues = PolicyValidator.validate(policy);
        require(issues.length == 0, PolicyValidator.ValidationError(issues));
    }

    /// @notice Builds the final policy blob without validation.
    /// @dev Skips validation. The resulting policy can be invalid.
    /// @param draft The draft state to build from.
    /// @return The encoded policy blob.
    function buildUnsafe(PolicyDraft memory draft) internal pure returns (bytes memory) {
        return PolicyCoder.encode(draft.data);
    }

    /// @notice Validates the policy that a draft contains.
    /// @param draft The draft state to validate.
    /// @return Every issue validation reports on the encoded policy.
    function validate(PolicyDraft memory draft) internal pure returns (Issue[] memory) {
        return PolicyValidator.validate(buildUnsafe(draft));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Appends a context test per operator of `constraint`, whose path names a context property.
    function _addContextTests(PolicyDraft memory draft, Constraint memory constraint, uint256 depth) private pure {
        // Context paths must be single-step (no nesting into atomic values like msg.sender).
        require(depth == 1, InvalidContextPath(depth));
        uint16 contextPropertyId = Path.atUnchecked(constraint.path, 0);
        require(contextPropertyId <= PF.CTX_MAX, Operator.UnknownContextProperty(contextPropertyId));

        bytes[] memory operators = _checkOperands(constraint, TypeRule.contextPropertyType(contextPropertyId));
        for (uint256 i = 0; i < operators.length; ++i) {
            _appendRule(draft, _test(PF.SCOPE_CONTEXT, constraint.path, operators[i]));
        }
    }

    /// @dev Appends a calldata test per operator of `constraint`. If the path of `constraint` passes a quantifier step,
    /// adds a body test per operator to the group's loop over that array instead.
    function _addCalldataTests(PolicyDraft memory draft, Constraint memory constraint, uint256 depth) private pure {
        bytes memory path = constraint.path;
        bytes memory desc = draft.data.descriptor;
        uint256 quantifierIndex = _quantifierIndex(path, depth);

        if (quantifierIndex == 0) {
            Hint.Compiled memory compiled = Hint.compileTest(desc, path);
            Hint.requireCompiled(compiled, path, 0);
            bytes[] memory operators = _checkOperands(constraint, uint8(desc[compiled.node]));
            for (uint256 i = 0; i < operators.length; ++i) {
                _appendRule(draft, _test(PF.SCOPE_CALLDATA, path, operators[i]));
            }
            return;
        }

        // The quantifier splits the path into the array's path and the body test's path from the element.
        bytes memory arrayPath = LibBytes.slice(path, 0, quantifierIndex * PF.PATH_STEP_SIZE);
        bytes memory bodyPath = LibBytes.slice(path, (quantifierIndex + 1) * PF.PATH_STEP_SIZE, path.length);
        Hint.Compiled memory loop = Hint.compileLoop(desc, arrayPath);
        Hint.requireCompiled(loop, path, 0);
        Hint.Compiled memory target = Hint.compileTest(desc, loop.node, bodyPath);
        Hint.requireCompiled(target, path, quantifierIndex + 1);

        bytes[] memory checked = _checkOperands(constraint, uint8(desc[target.node]));
        BodyRule[] memory tests = new BodyRule[](checked.length);
        for (uint256 i = 0; i < checked.length; ++i) {
            tests[i] = BodyRule(PF.SCOPE_CALLDATA, bodyPath, "", checked[i]);
        }
        uint8 quantifier = Path.atUnchecked(path, quantifierIndex) == Path.ALL ? PF.QUANTIFIER_ALL : PF.QUANTIFIER_ANY;
        _addToLoop(draft, quantifier, arrayPath, tests);
    }

    /// @dev Returns the index of the path's quantifier step, or zero when the path has none. The first step is a
    /// parameter index. Reverts on a second quantifier step and on any other step in the reserved marker range.
    function _quantifierIndex(bytes memory path, uint256 depth) private pure returns (uint256 quantifierIndex) {
        for (uint256 stepIndex = 1; stepIndex < depth; ++stepIndex) {
            uint16 step = Path.atUnchecked(path, stepIndex);
            if (step < PF.PATH_MARKER_BASE) continue;
            require(step == Path.ALL || step == Path.ANY, UnknownPathStep(path, stepIndex));
            require(quantifierIndex == 0, InvalidNestedLoop(path, stepIndex));
            quantifierIndex = stepIndex;
        }
    }

    /// @dev Adds `tests` to the body of the active group's loop over `arrayPath` with `quantifier`, or appends that
    /// loop.
    function _addToLoop(
        PolicyDraft memory draft,
        uint8 quantifier,
        bytes memory arrayPath,
        BodyRule[] memory tests
    )
        private
        pure
    {
        Rule[] memory group = draft.data.groups[draft.data.groups.length - 1];
        for (uint256 i = 0; i < group.length; ++i) {
            Rule memory rule = group[i];
            if (rule.scope != PF.SCOPE_LOOP || rule.quantifier != quantifier || !LibBytes.eq(rule.path, arrayPath)) {
                continue;
            }
            BodyRule[] memory body = new BodyRule[](rule.body.length + tests.length);
            for (uint256 j = 0; j < rule.body.length; ++j) {
                body[j] = rule.body[j];
            }
            for (uint256 j = 0; j < tests.length; ++j) {
                body[rule.body.length + j] = tests[j];
            }
            rule.body = body;
            return;
        }
        _appendRule(draft, Rule(PF.SCOPE_LOOP, quantifier, arrayPath, "", "", tests));
    }

    /// @dev Appends `rule` to the active group.
    function _appendRule(PolicyDraft memory draft, Rule memory rule) private pure {
        uint256 groupIndex = draft.data.groups.length - 1;
        Rule[] memory group = draft.data.groups[groupIndex];
        uint256 count = group.length;

        // The group is allocated at its rule count rounded up to a power of two. A power-of-two count is therefore
        // exactly full, and the slack of a shorter one is memory no other allocation can claim, so appending is a
        // length bump and doubling amortizes to a constant.
        if (count == 0 || (count & (count - 1)) == 0) {
            Rule[] memory grownGroup = new Rule[](count == 0 ? 1 : count * 2);
            for (uint256 i = 0; i < count; ++i) {
                grownGroup[i] = group[i];
            }
            group = grownGroup;
        }
        assembly ("memory-safe") {
            mstore(group, add(count, 1))
        }
        group[count] = rule;
        draft.data.groups[groupIndex] = group;
    }

    /// @dev Returns a test of `scope` at `path` applying `operator`.
    function _test(uint8 scope, bytes memory path, bytes memory operator) private pure returns (Rule memory test) {
        test.scope = scope;
        test.path = path;
        test.operator = operator;
    }

    /// @dev Requires every comparison of `constraint` to apply to a target of `typeCode` and every constant to be a
    /// value of its operand type. Returns the operators with each mask as its operand type's word. Operators of whole
    /// words only are read, so every word written lies within its operator.
    function _checkOperands(
        Constraint memory constraint,
        uint8 typeCode
    )
        private
        pure
        returns (bytes[] memory operators)
    {
        _checkOperandDomain(constraint, typeCode);

        operators = new bytes[](constraint.operators.length);
        for (uint256 i = 0; i < operators.length; ++i) {
            bytes memory operator = constraint.operators[i];
            operators[i] = operator;
            // Only an opcode followed by whole words carries constants to check.
            if (operator.length <= 1 || (operator.length - 1) % 32 != 0) continue;
            uint8 opCode = uint8(operator[0]);
            uint8 comparison = opCode & OpCode.COMPARISON_MASK;
            uint8 operandType = OpRule.operandTypeOf(comparison, typeCode);
            require(operandType != 0, PolicyCoder.OperatorTargetMismatch(opCode, typeCode));
            if ((opCode & ~OpCode.NOT) >> OpCode.SOURCE_SHIFT != OpCode.SOURCE_CONSTANT) continue;

            (uint8 mode, uint256 bits, uint256 width) = TypeRule.canonicalSpec(operandType);
            // The members of a set fill at most what the data length field holds.
            require((operator.length - 1) / 32 <= type(uint16).max / width, SetTooLarge());

            bool isMask = comparison >= OpCode.BITMASK_ALL && comparison <= OpCode.BITMASK_NONE;
            if (isMask) {
                operator = LibBytes.slice(operator, 0, operator.length);
                operators[i] = operator;
            }
            for (uint256 offset = 1; offset < operator.length; offset += 32) {
                bytes32 word = LibBytes.load(operator, offset);
                if (isMask) {
                    // A mask is a bit pattern of the type's width, or -1 for every bit.
                    bool fits = word == bytes32(type(uint256).max) || uint256(word) >> (8 * width) == 0;
                    require(fits, PolicyCoder.OutOfPhysicalBounds(word, operandType));
                    word = TypeRule.loadOperand(word << (256 - 8 * width), mode, width);
                    assembly ("memory-safe") {
                        mstore(add(add(operator, 32), offset), word)
                    }
                } else {
                    require(
                        TypeRule.checkCanonical(mode, bits, word), PolicyCoder.OutOfPhysicalBounds(word, operandType)
                    );
                }
            }
        }
    }

    /// @dev Reverts when an operand of `constraint` folds onto a value `typeCode` admits. A folded operand and that
    /// value encode to one word, so the operands as written are the only place the two stay distinct. Only the extremes
    /// can reach across the range's edge.
    function _checkOperandDomain(Constraint memory constraint, uint8 typeCode) private pure {
        // A negative operand encodes as its unsigned alias's word, which only a whole-word target can hold too.
        if (constraint.leastNegativeOperand < 0 && typeCode == TypeCode.UINT256) {
            // forge-lint: disable-next-line(unsafe-typecast) two's-complement reinterpret: the signed operand's word.
            revert PolicyCoder.OutOfPhysicalBounds(bytes32(uint256(constraint.leastNegativeOperand)), typeCode);
        }

        if (typeCode < TypeCode.INT8 || typeCode > TypeCode.INT256) return;
        // An operand at or above the signed minimum's own word denotes that negative, and every such operand already
        // exceeds the signed maximum.
        (,, uint256 width) = TypeRule.canonicalSpec(typeCode);
        uint256 min = type(uint256).max << (8 * width - 1);
        if (constraint.greatestOperand >= min) {
            revert PolicyCoder.OutOfPhysicalBounds(bytes32(constraint.greatestOperand), typeCode);
        }
    }
}

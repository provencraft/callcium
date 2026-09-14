// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Constraint } from "./Constraint.sol";
import { Descriptor } from "./Descriptor.sol";
import { DescriptorBuilder } from "./DescriptorBuilder.sol";
import { DescriptorFormat as DF } from "./DescriptorFormat.sol";
import { Path } from "./Path.sol";
import { PolicyCoder, PolicyData } from "./PolicyCoder.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { PolicyValidator } from "./PolicyValidator.sol";
import { SignatureParser } from "./SignatureParser.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";
import { Issue } from "./ValidationIssue.sol";
import { LibBytes } from "solady/utils/LibBytes.sol";

/// @notice Internal state for drafting a policy.
struct PolicyDraft {
    /// The canonical policy data.
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

    /// @notice Thrown when the same `(scope,path)` appears twice within a group.
    /// @param scope The constraint scope.
    /// @param path The encoded be16 path.
    error DuplicatePathInGroup(uint8 scope, bytes path);

    /// @notice Thrown when an unsupported scope value is provided.
    /// @param scope The invalid scope value.
    error InvalidScope(uint8 scope);

    /// @notice Thrown when a context-scope path does not have exactly one step.
    /// @param depth The path depth.
    error InvalidContextPath(uint256 depth);

    /// @notice Thrown when a context-scope path references an undefined context property.
    /// @param contextPropertyId The referenced property ID.
    error UnknownContextProperty(uint16 contextPropertyId);

    /// @notice Thrown when an operand lies outside the target type's range and encodes as a value inside it.
    /// @param word The 32-byte encoding the operand produced.
    /// @param typeCode The target's type code.
    error OutOfPhysicalBounds(bytes32 word, uint8 typeCode);

    /// @notice Thrown when a quantifier is used on a non-array node.
    /// @param path The encoded be16 path.
    /// @param stepIndex The step index of the invalid quantifier.
    error QuantifierOnNonArray(bytes path, uint256 stepIndex);

    /// @notice Thrown when a path contains more than one quantifier step.
    /// @param path The encoded be16 path.
    /// @param stepIndex The step index of the second quantifier.
    error NestedQuantifier(bytes path, uint256 stepIndex);

    /// @notice Thrown when a group is empty.
    /// @param groupIndex The index of the empty group.
    error EmptyGroup(uint256 groupIndex);

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a selectorless draft from a comma-separated type list.
    /// @param typesCsv The comma-separated ABI types (e.g. "uint256,address").
    /// @return draft The initialized draft.
    function createRaw(string memory typesCsv) internal pure returns (PolicyDraft memory draft) {
        draft.data.isSelectorless = true;
        draft.data.selector = bytes4(0);
        draft.data.descriptor = DescriptorBuilder.fromTypes(typesCsv);
        draft.data.groups = new Constraint[][](1);
        draft.data.groups[0] = new Constraint[](0);
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

    /// @notice Adds a constraint to the active group with validation.
    /// @param draft The draft state.
    /// @param constraint The constraint to add.
    /// @return The updated draft state with the constraint appended.
    function add(PolicyDraft memory draft, Constraint memory constraint) internal pure returns (PolicyDraft memory) {
        require(constraint.operators.length != 0, NoConstraintOperators());

        // Validate path navigates correctly for the given scope.
        uint256 depth = Path.validate(constraint.path);
        // The target type is read only to check a recorded operand against, and reaching it costs a
        // descriptor walk that a single-step path otherwise skips.
        bool hasOperand = constraint.leastNegativeOperand < 0 || constraint.greatestOperand != 0;
        uint8 targetType;
        if (constraint.scope == PF.SCOPE_CALLDATA) {
            targetType = _validateCalldataPath(draft.data.descriptor, constraint.path, depth, hasOperand);
        } else if (constraint.scope == PF.SCOPE_CONTEXT) {
            targetType = _validateContextPath(constraint.path, depth);
        } else {
            revert InvalidScope(constraint.scope);
        }

        if (hasOperand) _checkOperandDomain(constraint, targetType);

        // Reject duplicate paths within the same group.
        uint256 groupIndex = draft.data.groups.length - 1;
        Constraint[] memory group = draft.data.groups[groupIndex];
        uint256 count = group.length;
        for (uint256 i = 0; i < count; ++i) {
            // forgefmt: disable-next-item
            require(
                group[i].scope != constraint.scope || !LibBytes.eq(group[i].path, constraint.path),
                DuplicatePathInGroup(constraint.scope, constraint.path)
            );
        }

        // The group is allocated at its constraint count rounded up to a power of two. A
        // power-of-two count is therefore exactly full, and the slack of a shorter one is memory no
        // other allocation can claim, so appending is a length bump and doubling amortizes to a
        // constant.
        if (count == 0 || (count & (count - 1)) == 0) {
            Constraint[] memory grownGroup = new Constraint[](count == 0 ? 1 : count * 2);
            for (uint256 i = 0; i < count; ++i) {
                grownGroup[i] = group[i];
            }
            group = grownGroup;
        }
        assembly ("memory-safe") {
            mstore(group, add(count, 1))
        }
        group[count] = constraint;
        draft.data.groups[groupIndex] = group;

        return draft;
    }

    /// @notice Starts a new constraint group (OR semantics between groups).
    /// @param draft The draft state.
    /// @return The updated draft state with a new empty group.
    function or(PolicyDraft memory draft) internal pure returns (PolicyDraft memory) {
        uint256 last = draft.data.groups.length - 1;
        require(draft.data.groups[last].length != 0, EmptyGroup(last));

        uint256 newGroupIndex = draft.data.groups.length;

        Constraint[][] memory nextGroups = new Constraint[][](newGroupIndex + 1);
        for (uint256 i = 0; i < newGroupIndex; ++i) {
            nextGroups[i] = draft.data.groups[i];
        }
        nextGroups[newGroupIndex] = new Constraint[](0);

        draft.data.groups = nextGroups;

        return draft;
    }

    /// @notice Builds the final policy blob with strict validation.
    /// @dev Validates the policy and reverts on any issue.
    /// @param draft The draft state to build from.
    /// @return The encoded policy blob.
    function build(PolicyDraft memory draft) internal pure returns (bytes memory) {
        _requireNonEmpty(draft);

        Issue[] memory issues = PolicyValidator.validate(draft.data);

        if (issues.length > 0) revert PolicyValidator.ValidationError(issues);

        return PolicyCoder.encode(draft.data);
    }

    /// @notice Builds the final policy blob without validation.
    /// @dev Skips validation. The resulting policy may be invalid.
    /// @param draft The draft state to build from.
    /// @return The encoded policy blob.
    function buildUnsafe(PolicyDraft memory draft) internal pure returns (bytes memory) {
        _requireNonEmpty(draft);

        return PolicyCoder.encode(draft.data);
    }

    /// @notice Validates the policy without building.
    /// @dev Use for inspection, debugging, or custom error handling.
    /// @param draft The draft state to validate.
    /// @return All validation issues found.
    function validate(PolicyDraft memory draft) internal pure returns (Issue[] memory) {
        _requireNonEmpty(draft);

        return PolicyValidator.validate(draft.data);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Reverts if any group is empty.
    function _requireNonEmpty(PolicyDraft memory draft) private pure {
        uint256 groupCount = draft.data.groups.length;
        require(groupCount != 0, EmptyGroup(0));
        for (uint256 i = 0; i < groupCount; ++i) {
            require(draft.data.groups[i].length != 0, EmptyGroup(i));
        }
    }

    /// @dev Validates that `path` targets a valid context property and returns its type code.
    function _validateContextPath(bytes memory path, uint256 depth) private pure returns (uint8) {
        // Context paths must be single-step (no nesting into atomic values like msg.sender).
        require(depth == 1, InvalidContextPath(depth));
        // The step must reference a valid context property.
        uint16 contextPropertyId = Path.atUnchecked(path, 0);
        require(contextPropertyId <= PF.CTX_MAX, UnknownContextProperty(contextPropertyId));
        return TypeRule.contextPropertyType(contextPropertyId);
    }

    /// @dev Validates that `path` can be navigated within calldata described by `desc`. Returns the
    /// type code it reaches, or zero when `resolveType` is false and `path` only selects an argument.
    function _validateCalldataPath(
        bytes memory desc,
        bytes memory path,
        uint256 depth,
        bool resolveType
    )
        private
        pure
        returns (uint8 code)
    {
        uint8 paramCount = Descriptor.paramCount(desc);
        uint16 argIndex = Path.atUnchecked(path, 0);
        require(argIndex < paramCount, Descriptor.ParamIndexOutOfBounds(argIndex, paramCount));

        // Single-step paths need no composite descent, so the argument's node is read only when the
        // type is wanted.
        if (depth == 1 && !resolveType) return 0;

        uint256 offset = Descriptor.atUnchecked(desc, argIndex);
        (code,,,) = Descriptor.inspect(desc, offset);

        bool hasQuantifier = false;
        for (uint256 i = 1; i < depth; ++i) {
            (code, offset, hasQuantifier) = _descendPath(desc, offset, code, path, i, hasQuantifier);
        }
    }

    /// @dev Reverts when an operand of `constraint` folds onto a value `typeCode` admits. A folded
    /// operand and that value encode to one word, so the operands as written are the only place
    /// the two stay distinct. Only the extremes can reach across the range's edge.
    function _checkOperandDomain(Constraint memory constraint, uint8 typeCode) private pure {
        // A negative operand occupies the word its unsigned alias does, which only the target
        // holding the whole word can hold too.
        if (constraint.leastNegativeOperand < 0 && typeCode == TypeCode.UINT256) {
            // forge-lint: disable-next-line(unsafe-typecast) intentional int256->uint256 reinterpret.
            revert OutOfPhysicalBounds(bytes32(uint256(constraint.leastNegativeOperand)), typeCode);
        }

        if (typeCode < TypeCode.INT8 || typeCode > TypeCode.INT256) return;
        // An operand at or above the signed minimum's own word denotes that negative, and every
        // such operand already exceeds the signed maximum.
        (uint256 min,) = TypeRule.getDomainLimits(typeCode);
        if (constraint.greatestOperand >= min) {
            revert OutOfPhysicalBounds(bytes32(constraint.greatestOperand), typeCode);
        }
    }

    /// @dev Validates and descends one path step within `desc`.
    function _descendPath(
        bytes memory desc,
        uint256 offset,
        uint8 code,
        bytes memory path,
        uint256 stepIndex,
        bool hasQuantifier
    )
        private
        pure
        returns (uint8 nextCode, uint256 nextOffset, bool nextHasQuantifier)
    {
        uint16 step = Path.atUnchecked(path, stepIndex);
        bool isQuantifier = (step >= Path.ANY);
        bool isArray = (code == TypeCode.STATIC_ARRAY || code == TypeCode.DYNAMIC_ARRAY);
        nextHasQuantifier = hasQuantifier;

        if (isQuantifier) {
            require(isArray, QuantifierOnNonArray(path, stepIndex));
            require(!hasQuantifier, NestedQuantifier(path, stepIndex));
            nextHasQuantifier = true;
        }

        if (code == TypeCode.TUPLE) {
            uint16 fieldCount = Descriptor.tupleFieldCount(desc, offset);
            require(step < fieldCount, Descriptor.TupleFieldOutOfBounds(step, fieldCount));
            nextOffset = Descriptor.tupleFieldOffset(desc, offset, step);
        } else if (isArray) {
            if (code == TypeCode.STATIC_ARRAY && !isQuantifier) {
                uint16 arrayLength = Descriptor.staticArrayLength(desc, offset);
                require(step < arrayLength, Descriptor.StaticArrayIndexOutOfBounds(step, arrayLength));
            }
            nextOffset = offset + DF.ARRAY_HEADER_SIZE;
        } else {
            revert Descriptor.NotComposite(code);
        }

        (nextCode,,,) = Descriptor.inspect(desc, nextOffset);
    }
}

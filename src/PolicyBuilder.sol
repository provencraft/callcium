// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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
import { Issue } from "./ValidationIssue.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";

/// @notice Internal state for drafting a policy.
struct PolicyDraft {
    /// The canonical policy data.
    PolicyData data;
    /// Path hashes used per group for duplicate detection.
    bytes32[][] usedPathHashes;
}

using PolicyBuilder for PolicyDraft global;

/// @title PolicyBuilder
/// @notice Fluent API for drafting policies from constraints.
library PolicyBuilder {
    using EfficientHashLib for bytes;

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

    /// @notice Thrown when the first path step exceeds the number of arguments.
    /// @param argIndex The provided argument index.
    /// @param paramCount The parameter count from descriptor.
    error ArgIndexOutOfBounds(uint256 argIndex, uint256 paramCount);

    /// @notice Thrown when the path cannot be navigated according to scope rules.
    /// @param path The encoded be16 path that failed validation.
    /// @param stepIndex The step index at which navigation failed.
    error InvalidPathNavigation(bytes path, uint256 stepIndex);

    /// @notice Thrown when a tuple field index is out of bounds.
    /// @param fieldIndex The provided field index.
    /// @param fieldCount The tuple field count.
    error TupleFieldOutOfBounds(uint256 fieldIndex, uint256 fieldCount);

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
        draft.usedPathHashes = new bytes32[][](1);
        draft.usedPathHashes[0] = new bytes32[](0);
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
        if (constraint.scope == PF.SCOPE_CALLDATA) {
            _validateCalldataPath(draft.data.descriptor, constraint.path, depth);
        } else if (constraint.scope == PF.SCOPE_CONTEXT) {
            _validateContextPath(constraint.path, depth);
        } else {
            revert InvalidScope(constraint.scope);
        }

        // Reject duplicate paths within the same group.
        bytes32 constraintKey = abi.encodePacked(constraint.scope, constraint.path).hash();
        uint256 groupIndex = draft.data.groups.length - 1;
        bytes32[] memory usedHashes = draft.usedPathHashes[groupIndex];
        uint256 hashCount = usedHashes.length;
        for (uint256 i; i < hashCount; ++i) {
            require(usedHashes[i] != constraintKey, DuplicatePathInGroup(constraint.scope, constraint.path));
        }

        Constraint[] memory group = draft.data.groups[groupIndex];
        uint256 groupLength = group.length;
        Constraint[] memory nextGroup = new Constraint[](groupLength + 1);
        for (uint256 i; i < groupLength; ++i) {
            nextGroup[i] = group[i];
        }
        nextGroup[groupLength] = constraint;
        draft.data.groups[groupIndex] = nextGroup;

        bytes32[] memory nextHashes = new bytes32[](hashCount + 1);
        for (uint256 i; i < hashCount; ++i) {
            nextHashes[i] = usedHashes[i];
        }
        nextHashes[hashCount] = constraintKey;
        draft.usedPathHashes[groupIndex] = nextHashes;

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
        bytes32[][] memory nextUsed = new bytes32[][](newGroupIndex + 1);

        for (uint256 i; i < newGroupIndex; ++i) {
            nextGroups[i] = draft.data.groups[i];
            nextUsed[i] = draft.usedPathHashes[i];
        }

        nextGroups[newGroupIndex] = new Constraint[](0);
        nextUsed[newGroupIndex] = new bytes32[](0);

        draft.data.groups = nextGroups;
        draft.usedPathHashes = nextUsed;

        return draft;
    }

    /// @notice Builds the final policy blob with strict validation.
    /// @dev Validates the policy and reverts on any issue.
    /// @param draft The draft state to build from.
    /// @return The encoded policy bytes.
    function build(PolicyDraft memory draft) internal pure returns (bytes memory) {
        _requireNonEmpty(draft);

        Issue[] memory issues = PolicyValidator.validate(draft.data);

        if (issues.length > 0) revert PolicyValidator.ValidationError(issues);

        return PolicyCoder.encode(draft.data);
    }

    /// @notice Builds the final policy blob without validation.
    /// @dev Skips validation. The resulting policy may be invalid.
    /// @param draft The draft state to build from.
    /// @return The encoded policy bytes.
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
        for (uint256 i; i < groupCount; ++i) {
            require(draft.data.groups[i].length != 0, EmptyGroup(i));
        }
    }

    /// @dev Validates that `path` targets a valid context property.
    function _validateContextPath(bytes memory path, uint256 depth) private pure {
        // Context paths must be single-step (no nesting into atomic values like msg.sender).
        require(depth == 1, InvalidPathNavigation(path, 0));
        // The step must reference a valid context property.
        uint16 contextPropertyId = Path.atUnchecked(path, 0);
        require(contextPropertyId <= PF.CTX_TX_ORIGIN, InvalidPathNavigation(path, 0));
    }

    /// @dev Validates that `path` can be navigated within calldata described by `desc`.
    function _validateCalldataPath(bytes memory desc, bytes memory path, uint256 depth) private pure {
        uint8 paramCount = Descriptor.paramCount(desc);
        uint16 argIndex = Path.atUnchecked(path, 0);
        require(argIndex < paramCount, ArgIndexOutOfBounds(argIndex, paramCount));

        // Single-step paths only select an argument; no composite descent needed.
        if (depth == 1) return;

        uint256 offset = Descriptor.atUnchecked(desc, argIndex);
        (uint8 code,,,) = Descriptor.inspect(desc, offset);

        bool hasQuantifier;
        for (uint256 i = 1; i < depth; ++i) {
            (code, offset, hasQuantifier) = _descendPath(desc, offset, code, path, i, hasQuantifier);
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
            require(step < fieldCount, TupleFieldOutOfBounds(step, fieldCount));
            nextOffset = Descriptor.tupleFieldOffset(desc, offset, step);
        } else if (isArray) {
            if (code == TypeCode.STATIC_ARRAY && !isQuantifier) {
                uint16 arrayLength = Descriptor.staticArrayLength(desc, offset);
                require(step < arrayLength, InvalidPathNavigation(path, stepIndex));
            }
            nextOffset = offset + DF.ARRAY_HEADER_SIZE;
        } else {
            revert InvalidPathNavigation(path, stepIndex);
        }

        (nextCode,,,) = Descriptor.inspect(desc, nextOffset);
    }
}

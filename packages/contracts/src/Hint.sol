// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Descriptor } from "./Descriptor.sol";
import { DescriptorFormat as DF } from "./DescriptorFormat.sol";
import { Path } from "./Path.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { TypeCode } from "./TypeCode.sol";

/// @title Hint
/// @notice Compiler of paths into the hints that address their targets in calldata.
library Hint {
    /// @notice A compiled hint, or the fault that stopped its compilation.
    struct Compiled {
        /// @dev The fault code, or `FAULT_NONE` when the path compiled.
        uint8 fault;
        /// @dev Index of the path step at fault.
        uint256 stepIndex;
        /// @dev The bound the faulting step broke: a parameter, field or element count, or a type code.
        uint256 bound;
        /// @dev The hint as the wire carries it.
        bytes hint;
        /// @dev Descriptor offset of the target node, or of a loop's element node.
        uint256 node;
    }

    /// @dev State threaded through the walk of a path.
    struct Walk {
        /// @dev The hops emitted so far.
        bytes hops;
        /// @dev Byte offset of the current node's head from the chain's last base.
        uint256 delta;
        /// @dev Whether the chain ends inside the current node, which then takes no entry hop.
        bool entered;
        /// @dev Descriptor offset of the current node.
        uint256 node;
    }

    /// @dev No fault: the path compiled.
    uint8 internal constant FAULT_NONE = 0;

    /// @dev A parameter index at or past the parameter count.
    uint8 internal constant FAULT_PARAM_INDEX = 1;

    /// @dev A tuple field index at or past the field count.
    uint8 internal constant FAULT_TUPLE_FIELD = 2;

    /// @dev A static array index at or past the declared length.
    uint8 internal constant FAULT_ARRAY_INDEX = 3;

    /// @dev A step into an elementary node.
    uint8 internal constant FAULT_NOT_COMPOSITE = 4;

    /// @dev A loop over a node that is not an array.
    uint8 internal constant FAULT_NOT_ARRAY = 5;

    /*/////////////////////////////////////////////////////////////////////////
                                        ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a loop's array path reaches a node that is not an array.
    /// @param path The encoded be16 path.
    /// @param stepIndex The step index of the quantifier.
    error QuantifierOnNonArray(bytes path, uint256 stepIndex);

    /*/////////////////////////////////////////////////////////////////////////
                                       FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Compiles a test's hint for `path` from the arguments.
    /// @param desc The descriptor.
    /// @param path The encoded be16 path, its first step a parameter index.
    /// @return compiled The test hint and the target node, or the fault.
    function compileTest(bytes memory desc, bytes memory path) internal pure returns (Compiled memory compiled) {
        Walk memory walk;
        compiled = _walkArguments(desc, path, walk);
        if (compiled.fault == FAULT_NONE) _finishTest(desc, walk, compiled);
    }

    /// @notice Compiles a test's hint for `path` from the loop element whose node lies at `element`.
    /// @param desc The descriptor.
    /// @param element Descriptor offset of the element node.
    /// @param path The encoded be16 path, relative to the element, or empty for the element itself.
    /// @return compiled The test hint and the target node, or the fault.
    function compileTest(
        bytes memory desc,
        uint256 element,
        bytes memory path
    )
        internal
        pure
        returns (Compiled memory compiled)
    {
        Walk memory walk;
        walk.entered = true;
        walk.node = element;
        compiled = _walkSteps(desc, path, 0, walk);
        if (compiled.fault == FAULT_NONE) _finishTest(desc, walk, compiled);
    }

    /// @notice Compiles a loop's hint for the array at `arrayPath` from the arguments.
    /// @param desc The descriptor.
    /// @param arrayPath The encoded be16 path of the array, its first step a parameter index.
    /// @return compiled The frame hint and the element node, or the fault.
    function compileLoop(bytes memory desc, bytes memory arrayPath) internal pure returns (Compiled memory compiled) {
        Walk memory walk;
        compiled = _walkArguments(desc, arrayPath, walk);
        if (compiled.fault != FAULT_NONE) return compiled;

        (uint8 code, bool isDynamic,,) = Descriptor.inspect(desc, walk.node);
        uint256 count = 0;
        if (code == TypeCode.STATIC_ARRAY) {
            _enter(walk, isDynamic && !walk.entered);
            count = Descriptor.staticArrayLength(desc, walk.node);
        } else if (code == TypeCode.DYNAMIC_ARRAY) {
            _enter(walk, !walk.entered);
        } else {
            compiled.fault = FAULT_NOT_ARRAY;
            compiled.stepIndex = Path.depth(arrayPath);
            compiled.bound = code;
            return compiled;
        }

        // forge-lint: disable-next-line(unsafe-typecast) bounded by the `DescriptorFormat` limits.
        bytes memory frame = abi.encodePacked(uint32(walk.delta), uint16(count), _arrayMeta(desc, walk.node, code));
        compiled.hint = bytes.concat(_header(walk), walk.hops, frame);
        compiled.node = walk.node + DF.ARRAY_HEADER_SIZE;
    }

    /// @notice Reverts with the error that names `compiled`'s fault, if any.
    /// @param compiled The compilation result.
    /// @param path The path the steps of `compiled` index into.
    /// @param stepOffset The index in `path` of the first step `compiled` walked.
    function requireCompiled(Compiled memory compiled, bytes memory path, uint256 stepOffset) internal pure {
        uint8 fault = compiled.fault;
        if (fault == FAULT_NONE) return;

        uint256 stepIndex = stepOffset + compiled.stepIndex;
        if (fault == FAULT_NOT_ARRAY) revert QuantifierOnNonArray(path, stepIndex);
        // forge-lint: disable-next-line(unsafe-typecast) wire-field slice: the type code `bound` holds.
        if (fault == FAULT_NOT_COMPOSITE) revert Descriptor.NotComposite(uint8(compiled.bound));

        uint16 step = Path.atUnchecked(path, stepIndex);
        if (fault == FAULT_PARAM_INDEX) revert Descriptor.ParamIndexOutOfBounds(step, compiled.bound);
        if (fault == FAULT_TUPLE_FIELD) revert Descriptor.TupleFieldOutOfBounds(step, compiled.bound);
        revert Descriptor.StaticArrayIndexOutOfBounds(step, compiled.bound);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Walks `path` from the arguments, whose encoding starts at the base. The first step selects a parameter,
    /// whose head lies past the heads of the parameters before it.
    function _walkArguments(
        bytes memory desc,
        bytes memory path,
        Walk memory walk
    )
        private
        pure
        returns (Compiled memory compiled)
    {
        uint16 argIndex = Path.atUnchecked(path, 0);
        uint8 paramCount = Descriptor.paramCount(desc);
        if (argIndex >= paramCount) {
            compiled.fault = FAULT_PARAM_INDEX;
            compiled.bound = paramCount;
            return compiled;
        }
        (walk.delta, walk.node) = _headSpan(desc, DF.HEADER_SIZE, argIndex);
        return _walkSteps(desc, path, 1, walk);
    }

    /// @dev Walks the steps of `path` from `firstStep` on, each into the field or element of the current node.
    function _walkSteps(
        bytes memory desc,
        bytes memory path,
        uint256 firstStep,
        Walk memory walk
    )
        private
        pure
        returns (Compiled memory compiled)
    {
        uint256 depth = Path.depth(path);
        for (uint256 stepIndex = firstStep; stepIndex < depth; ++stepIndex) {
            uint16 step = Path.atUnchecked(path, stepIndex);
            (uint8 code, bool isDynamic,,) = Descriptor.inspect(desc, walk.node);

            if (code == TypeCode.TUPLE) {
                uint16 fieldCount = Descriptor.tupleFieldCount(desc, walk.node);
                if (step >= fieldCount) return _fault(FAULT_TUPLE_FIELD, stepIndex, fieldCount);
                _enter(walk, isDynamic && !walk.entered);
                (uint256 fieldSpan, uint256 fieldNode) = _headSpan(desc, walk.node + DF.TUPLE_HEADER_SIZE, step);
                walk.delta += fieldSpan;
                walk.entered = false;
                walk.node = fieldNode;
            } else if (code == TypeCode.STATIC_ARRAY || code == TypeCode.DYNAMIC_ARRAY) {
                if (code == TypeCode.STATIC_ARRAY) {
                    uint16 arrayLength = Descriptor.staticArrayLength(desc, walk.node);
                    if (step >= arrayLength) return _fault(FAULT_ARRAY_INDEX, stepIndex, arrayLength);
                }
                uint256 element = walk.node + DF.ARRAY_HEADER_SIZE;
                (, bool elemIsDynamic, uint32 elemStaticSize,) = Descriptor.inspect(desc, element);

                if (isDynamic) {
                    // An indirected array holds its elements behind an offset word.
                    _enter(walk, !walk.entered);
                    walk.hops = abi.encodePacked(walk.hops, uint32(0), step, _arrayMeta(desc, walk.node, code));
                    walk.delta = 0;
                    walk.entered = elemIsDynamic;
                } else {
                    // A static array of static elements is inline, so the index folds into the delta.
                    walk.delta += uint256(step) * elemStaticSize;
                    walk.entered = false;
                }
                walk.node = element;
            } else {
                return _fault(FAULT_NOT_COMPOSITE, stepIndex, code);
            }
        }
    }

    /// @dev Completes a test's hint at the walk's node: a dynamic target is entered, so the hint ends where its
    /// encoding starts.
    function _finishTest(bytes memory desc, Walk memory walk, Compiled memory compiled) private pure {
        (uint8 code, bool isDynamic,,) = Descriptor.inspect(desc, walk.node);
        _enter(walk, isDynamic && !walk.entered);

        uint16 targetMeta = code == TypeCode.DYNAMIC_ARRAY ? _arrayMeta(desc, walk.node, code) : 0;
        // forge-lint: disable-next-line(unsafe-typecast) bounded by `MAX_PARAMS` and `MAX_STATIC_WORDS`.
        bytes memory target = abi.encodePacked(uint32(walk.delta), targetMeta, code);
        compiled.hint = bytes.concat(_header(walk), walk.hops, target);
        compiled.node = walk.node;
    }

    /// @dev Returns a result carrying the fault.
    function _fault(uint8 fault, uint256 stepIndex, uint256 bound) private pure returns (Compiled memory compiled) {
        compiled.fault = fault;
        compiled.stepIndex = stepIndex;
        compiled.bound = bound;
    }

    /// @dev Appends the hop entering an indirected node's payload when `needed`, and rebases the delta.
    function _enter(Walk memory walk, bool needed) private pure {
        if (!needed) return;
        // forge-lint: disable-next-line(unsafe-typecast) bounded by `MAX_PARAMS` and `MAX_STATIC_WORDS`.
        walk.hops = abi.encodePacked(walk.hops, uint32(walk.delta), PF.HINT_NO_INDEX, uint16(0));
        walk.delta = 0;
    }

    /// @dev Returns the hint header byte: the hop count, the reserved bits zero.
    function _header(Walk memory walk) private pure returns (bytes1) {
        // forge-lint: disable-next-line(unsafe-typecast) bounded by `MAX_PATH_DEPTH`.
        return bytes1(uint8(walk.hops.length / PF.HINT_HOP_SIZE));
    }

    /// @dev Returns the combined head span of the `count` nodes at `offset`, and the offset of the node past them.
    function _headSpan(
        bytes memory desc,
        uint256 offset,
        uint256 count
    )
        private
        pure
        returns (uint256 span, uint256 nodeOffset)
    {
        nodeOffset = offset;
        for (uint256 i = 0; i < count; ++i) {
            (, bool isDynamic, uint32 staticSize, uint256 next) = Descriptor.inspect(desc, nodeOffset);
            // An indirected node occupies a single offset word.
            span += isDynamic ? 32 : staticSize;
            nodeOffset = next;
        }
    }

    /// @dev Returns the meta word describing the array node at `arrayOffset`.
    function _arrayMeta(bytes memory desc, uint256 arrayOffset, uint8 code) private pure returns (uint16 meta) {
        (, bool elemIsDynamic, uint32 elemStaticSize,) = Descriptor.inspect(desc, arrayOffset + DF.ARRAY_HEADER_SIZE);
        // A dynamic element occupies one offset word within the element region.
        // forge-lint: disable-next-line(unsafe-typecast) bounded by `MAX_STATIC_WORDS`.
        meta = elemIsDynamic ? 1 : uint16(elemStaticSize >> 5);
        if (elemIsDynamic) meta |= PF.HINT_META_ELEM_DYNAMIC;
        if (code == TypeCode.DYNAMIC_ARRAY) meta |= PF.HINT_META_DYNAMIC_ARRAY;
    }
}

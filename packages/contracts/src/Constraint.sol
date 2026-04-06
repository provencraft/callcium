// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { LibSort } from "solady/utils/LibSort.sol";

import { OpCode } from "./OpCode.sol";
import { Path } from "./Path.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";

/// @notice Accumulates path and operator encodings for a single logical constraint.
struct Constraint {
    /// SCOPE_CONTEXT or SCOPE_CALLDATA.
    uint8 scope;
    /// BE16-encoded path to the target value.
    bytes path;
    /// Encoded operators. Each item = opCode(1) || data.
    bytes[] operators;
}

using Operator for Constraint global;

/*/////////////////////////////////////////////////////////////////////////
                                FUNCTIONS
/////////////////////////////////////////////////////////////////////////*/

/// @notice Creates a constraint targeting `msg.sender`.
/// @return A context-scoped constraint for msg.sender.
function msgSender() pure returns (Constraint memory) {
    return Constraint({ scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_MSG_SENDER), operators: new bytes[](0) });
}

/// @notice Creates a constraint targeting `msg.value`.
/// @return A context-scoped constraint for msg.value.
function msgValue() pure returns (Constraint memory) {
    return Constraint({ scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_MSG_VALUE), operators: new bytes[](0) });
}

/// @notice Creates a constraint targeting `block.timestamp`.
/// @return A context-scoped constraint for block.timestamp.
function blockTimestamp() pure returns (Constraint memory) {
    return Constraint({ scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_BLOCK_TIMESTAMP), operators: new bytes[](0) });
}

/// @notice Creates a constraint targeting `block.number`.
/// @return A context-scoped constraint for block.number.
function blockNumber() pure returns (Constraint memory) {
    return Constraint({ scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_BLOCK_NUMBER), operators: new bytes[](0) });
}

/// @notice Creates a constraint targeting `block.chainid`.
/// @return A context-scoped constraint for block.chainid.
function chainId() pure returns (Constraint memory) {
    return Constraint({ scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_CHAIN_ID), operators: new bytes[](0) });
}

/// @notice Creates a constraint targeting `tx.origin`.
/// @return A context-scoped constraint for tx.origin.
function txOrigin() pure returns (Constraint memory) {
    return Constraint({ scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_TX_ORIGIN), operators: new bytes[](0) });
}

/// @notice Creates a constraint targeting a top-level argument.
/// @param p0 The argument index.
/// @return A calldata-scoped constraint at the given path.
function arg(uint16 p0) pure returns (Constraint memory) {
    return Constraint({ scope: PF.SCOPE_CALLDATA, path: Path.encode(p0), operators: new bytes[](0) });
}

/// @notice Creates a constraint targeting a nested path of depth 2.
/// @param p0 The argument index.
/// @param p1 The second path step.
/// @return A calldata-scoped constraint at the given path.
function arg(uint16 p0, uint16 p1) pure returns (Constraint memory) {
    return Constraint({ scope: PF.SCOPE_CALLDATA, path: Path.encode(p0, p1), operators: new bytes[](0) });
}

/// @notice Creates a constraint targeting a nested path of depth 3.
/// @param p0 The argument index.
/// @param p1 The second path step.
/// @param p2 The third path step.
/// @return A calldata-scoped constraint at the given path.
function arg(uint16 p0, uint16 p1, uint16 p2) pure returns (Constraint memory) {
    return Constraint({ scope: PF.SCOPE_CALLDATA, path: Path.encode(p0, p1, p2), operators: new bytes[](0) });
}

/// @notice Creates a constraint targeting a nested path of depth 4.
/// @param p0 The argument index.
/// @param p1 The second path step.
/// @param p2 The third path step.
/// @param p3 The fourth path step.
/// @return A calldata-scoped constraint at the given path.
function arg(uint16 p0, uint16 p1, uint16 p2, uint16 p3) pure returns (Constraint memory) {
    return Constraint({ scope: PF.SCOPE_CALLDATA, path: Path.encode(p0, p1, p2, p3), operators: new bytes[](0) });
}

/// @notice Creates a constraint from a pre-encoded BE16 path.
/// @param path The pre-encoded BE16 path bytes.
/// @return A calldata-scoped constraint at the given path.
function arg(bytes memory path) pure returns (Constraint memory) {
    Path.validate(path);
    return Constraint({ scope: PF.SCOPE_CALLDATA, path: path, operators: new bytes[](0) });
}

/// @title Operator
/// @notice Fluent API operators for building Constraints.
library Operator {
    /*/////////////////////////////////////////////////////////////////////////
                                     ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the range minimum exceeds the maximum.
    error InvalidRange();

    /// @notice Thrown when an empty set is passed to a set membership operator.
    error EmptySet();

    /// @notice Thrown when a set exceeds the maximum element count (2047).
    error SetTooLarge();

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Requires the value to equal `value`.
    /// @param c The constraint to extend.
    /// @param value The expected value.
    /// @return The updated constraint.
    function eq(Constraint memory c, uint256 value) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.EQ, _u256(value));
    }

    /// @notice Requires the value to not equal `value`.
    /// @param c The constraint to extend.
    /// @param value The excluded value.
    /// @return The updated constraint.
    function neq(Constraint memory c, uint256 value) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.EQ | OpCode.NOT, _u256(value));
    }

    /// @notice Requires the value to be strictly greater than `bound`.
    /// @param c The constraint to extend.
    /// @param bound The lower bound (exclusive).
    /// @return The updated constraint.
    function gt(Constraint memory c, uint256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.GT, _u256(bound));
    }

    /// @notice Requires the value to be strictly less than `bound`.
    /// @param c The constraint to extend.
    /// @param bound The upper bound (exclusive).
    /// @return The updated constraint.
    function lt(Constraint memory c, uint256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.LT, _u256(bound));
    }

    /// @notice Requires the value to be greater than or equal to `bound`.
    /// @param c The constraint to extend.
    /// @param bound The lower bound (inclusive).
    /// @return The updated constraint.
    function gte(Constraint memory c, uint256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.GTE, _u256(bound));
    }

    /// @notice Requires the value to be less than or equal to `bound`.
    /// @param c The constraint to extend.
    /// @param bound The upper bound (inclusive).
    /// @return The updated constraint.
    function lte(Constraint memory c, uint256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.LTE, _u256(bound));
    }

    /// @notice Requires the value to be within [min, max] inclusive.
    /// @param c The constraint to extend.
    /// @param min The lower bound (inclusive).
    /// @param max The upper bound (inclusive).
    /// @return The updated constraint.
    function between(Constraint memory c, uint256 min, uint256 max) internal pure returns (Constraint memory) {
        require(min <= max, InvalidRange());
        return _pushOp(c, OpCode.BETWEEN, abi.encodePacked(_u256(min), _u256(max)));
    }

    /// @notice Requires the signed value to equal `value`.
    /// @param c The constraint to extend.
    /// @param value The expected value.
    /// @return The updated constraint.
    function eq(Constraint memory c, int256 value) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.EQ, _i256(value));
    }

    /// @notice Requires the signed value to not equal `value`.
    /// @param c The constraint to extend.
    /// @param value The excluded value.
    /// @return The updated constraint.
    function neq(Constraint memory c, int256 value) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.EQ | OpCode.NOT, _i256(value));
    }

    /// @notice Requires the signed value to be strictly greater than `bound`.
    /// @param c The constraint to extend.
    /// @param bound The lower bound (exclusive).
    /// @return The updated constraint.
    function gt(Constraint memory c, int256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.GT, _i256(bound));
    }

    /// @notice Requires the signed value to be strictly less than `bound`.
    /// @param c The constraint to extend.
    /// @param bound The upper bound (exclusive).
    /// @return The updated constraint.
    function lt(Constraint memory c, int256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.LT, _i256(bound));
    }

    /// @notice Requires the signed value to be greater than or equal to `bound`.
    /// @param c The constraint to extend.
    /// @param bound The lower bound (inclusive).
    /// @return The updated constraint.
    function gte(Constraint memory c, int256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.GTE, _i256(bound));
    }

    /// @notice Requires the signed value to be less than or equal to `bound`.
    /// @param c The constraint to extend.
    /// @param bound The upper bound (inclusive).
    /// @return The updated constraint.
    function lte(Constraint memory c, int256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.LTE, _i256(bound));
    }

    /// @notice Requires the signed value to be within [min, max] inclusive.
    /// @param c The constraint to extend.
    /// @param min The lower bound (inclusive).
    /// @param max The upper bound (inclusive).
    /// @return The updated constraint.
    function between(Constraint memory c, int256 min, int256 max) internal pure returns (Constraint memory) {
        require(min <= max, InvalidRange());
        return _pushOp(c, OpCode.BETWEEN, abi.encodePacked(_i256(min), _i256(max)));
    }

    /// @notice Requires the value to equal `value` (address).
    /// @param c The constraint to extend.
    /// @param value The expected address.
    /// @return The updated constraint.
    function eq(Constraint memory c, address value) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.EQ, _addr(value));
    }

    /// @notice Requires the value to not equal `value` (address).
    /// @param c The constraint to extend.
    /// @param value The excluded address.
    /// @return The updated constraint.
    function neq(Constraint memory c, address value) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.EQ | OpCode.NOT, _addr(value));
    }

    /// @notice Requires the value to equal `value` (bytes32).
    /// @param c The constraint to extend.
    /// @param value The expected bytes32 value.
    /// @return The updated constraint.
    function eq(Constraint memory c, bytes32 value) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.EQ, value);
    }

    /// @notice Requires the value to not equal `value` (bytes32).
    /// @param c The constraint to extend.
    /// @param value The excluded bytes32 value.
    /// @return The updated constraint.
    function neq(Constraint memory c, bytes32 value) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.EQ | OpCode.NOT, value);
    }

    /// @notice Requires the value to equal `value` (bool).
    /// @param c The constraint to extend.
    /// @param value The expected boolean.
    /// @return The updated constraint.
    function eq(Constraint memory c, bool value) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.EQ, _bool(value));
    }

    /// @notice Requires the value to not equal `value` (bool).
    /// @param c The constraint to extend.
    /// @param value The excluded boolean.
    /// @return The updated constraint.
    function neq(Constraint memory c, bool value) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.EQ | OpCode.NOT, _bool(value));
    }

    /// @notice Requires the value to be in the given address set.
    /// @param c The constraint to extend.
    /// @param values The allowed addresses.
    /// @return The updated constraint.
    function isIn(Constraint memory c, address[] memory values) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.IN, _packSet(values));
    }

    /// @notice Requires the value to not be in the given address set.
    /// @param c The constraint to extend.
    /// @param values The excluded addresses.
    /// @return The updated constraint.
    function notIn(Constraint memory c, address[] memory values) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.IN | OpCode.NOT, _packSet(values));
    }

    /// @notice Requires the value to be in the given bytes32 set.
    /// @param c The constraint to extend.
    /// @param values The allowed values.
    /// @return The updated constraint.
    function isIn(Constraint memory c, bytes32[] memory values) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.IN, _packSet(values));
    }

    /// @notice Requires the value to not be in the given bytes32 set.
    /// @param c The constraint to extend.
    /// @param values The excluded values.
    /// @return The updated constraint.
    function notIn(Constraint memory c, bytes32[] memory values) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.IN | OpCode.NOT, _packSet(values));
    }

    /// @notice Requires the value to be in the given uint256 set.
    /// @param c The constraint to extend.
    /// @param values The allowed values.
    /// @return The updated constraint.
    function isIn(Constraint memory c, uint256[] memory values) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.IN, _packSet(values));
    }

    /// @notice Requires the value to not be in the given uint256 set.
    /// @param c The constraint to extend.
    /// @param values The excluded values.
    /// @return The updated constraint.
    function notIn(Constraint memory c, uint256[] memory values) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.IN | OpCode.NOT, _packSet(values));
    }

    /// @notice Requires the value to be in the given int256 set.
    /// @param c The constraint to extend.
    /// @param values The allowed values.
    /// @return The updated constraint.
    function isIn(Constraint memory c, int256[] memory values) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.IN, _packSet(values));
    }

    /// @notice Requires the value to not be in the given int256 set.
    /// @param c The constraint to extend.
    /// @param values The excluded values.
    /// @return The updated constraint.
    function notIn(Constraint memory c, int256[] memory values) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.IN | OpCode.NOT, _packSet(values));
    }

    /// @notice Requires the dynamic type length to equal `length`.
    /// @param c The constraint to extend.
    /// @param length The expected length.
    /// @return The updated constraint.
    function lengthEq(Constraint memory c, uint256 length) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.LENGTH_EQ, _u256(length));
    }

    /// @notice Requires the dynamic type length to be strictly greater than `bound`.
    /// @param c The constraint to extend.
    /// @param bound The lower bound (exclusive).
    /// @return The updated constraint.
    function lengthGt(Constraint memory c, uint256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.LENGTH_GT, _u256(bound));
    }

    /// @notice Requires the dynamic type length to be strictly less than `bound`.
    /// @param c The constraint to extend.
    /// @param bound The upper bound (exclusive).
    /// @return The updated constraint.
    function lengthLt(Constraint memory c, uint256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.LENGTH_LT, _u256(bound));
    }

    /// @notice Requires the dynamic type length to be greater than or equal to `bound`.
    /// @param c The constraint to extend.
    /// @param bound The lower bound (inclusive).
    /// @return The updated constraint.
    function lengthGte(Constraint memory c, uint256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.LENGTH_GTE, _u256(bound));
    }

    /// @notice Requires the dynamic type length to be less than or equal to `bound`.
    /// @param c The constraint to extend.
    /// @param bound The upper bound (inclusive).
    /// @return The updated constraint.
    function lengthLte(Constraint memory c, uint256 bound) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.LENGTH_LTE, _u256(bound));
    }

    /// @notice Requires the dynamic type length to be within [min, max] inclusive.
    /// @param c The constraint to extend.
    /// @param min The lower bound (inclusive).
    /// @param max The upper bound (inclusive).
    /// @return The updated constraint.
    function lengthBetween(Constraint memory c, uint256 min, uint256 max) internal pure returns (Constraint memory) {
        require(min <= max, InvalidRange());
        return _pushOp(c, OpCode.LENGTH_BETWEEN, abi.encodePacked(_u256(min), _u256(max)));
    }

    /// @notice Requires all bits in `mask` to be set.
    /// @param c The constraint to extend.
    /// @param mask The bitmask to check.
    /// @return The updated constraint.
    function bitmaskAll(Constraint memory c, uint256 mask) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.BITMASK_ALL, _u256(mask));
    }

    /// @notice Requires at least one bit in `mask` to be set.
    /// @param c The constraint to extend.
    /// @param mask The bitmask to check.
    /// @return The updated constraint.
    function bitmaskAny(Constraint memory c, uint256 mask) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.BITMASK_ANY, _u256(mask));
    }

    /// @notice Requires no bits in `mask` to be set.
    /// @param c The constraint to extend.
    /// @param mask The bitmask to check.
    /// @return The updated constraint.
    function bitmaskNone(Constraint memory c, uint256 mask) internal pure returns (Constraint memory) {
        return _pushOp(c, OpCode.BITMASK_NONE, _u256(mask));
    }

    /// @notice Appends a raw operator with its data payload.
    /// @param c The constraint to extend.
    /// @param op The operator code byte.
    /// @param data The operator data payload.
    /// @return The updated constraint.
    function addOp(Constraint memory c, uint8 op, bytes memory data) internal pure returns (Constraint memory) {
        return _append(c, abi.encodePacked(op, data));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Appends an operator with 32-byte `data` to `c`.
    function _pushOp(Constraint memory c, uint8 op, bytes32 data) private pure returns (Constraint memory) {
        return _append(c, abi.encodePacked(op, data));
    }

    /// @dev Appends an operator with variable-length `data` to `c`.
    function _pushOp(Constraint memory c, uint8 op, bytes memory data) private pure returns (Constraint memory) {
        return _append(c, abi.encodePacked(op, data));
    }

    /// @dev Appends an encoded operator to `c`'s operator list.
    function _append(Constraint memory c, bytes memory opWithData) private pure returns (Constraint memory) {
        uint256 length = c.operators.length;
        bytes[] memory next = new bytes[](length + 1);
        for (uint256 i; i < length; ++i) {
            next[i] = c.operators[i];
        }
        next[length] = opWithData;
        c.operators = next;
        return c;
    }

    /// @dev Converts an unsigned integer to a 32-byte word.
    function _u256(uint256 value) private pure returns (bytes32) {
        return bytes32(value);
    }

    /// @dev Converts an address to a left-padded 32-byte word.
    function _addr(address value) private pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }

    /// @dev Converts a boolean to a 32-byte word (0x01 for true, 0x00 for false).
    function _bool(bool flag) private pure returns (bytes32) {
        return flag ? bytes32(uint256(1)) : bytes32(0);
    }

    /// @dev Converts a signed integer to a 32-byte word.
    function _i256(int256 value) private pure returns (bytes32) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes32(uint256(value));
    }

    /// @dev Packs an address array into sorted, deduplicated 32-byte words.
    function _packSet(address[] memory values) private pure returns (bytes memory out) {
        require(values.length != 0, EmptySet());
        LibSort.sort(values);
        LibSort.uniquifySorted(values);
        uint256 length = values.length;
        require(length <= 2047, SetTooLarge());
        out = new bytes(length * 32);
        for (uint256 i; i < length; ++i) {
            bytes32 word = _addr(values[i]);
            assembly ("memory-safe") {
                mstore(add(add(out, 32), mul(i, 32)), word)
            }
        }
    }

    /// @dev Packs a bytes32 array into sorted, deduplicated 32-byte words.
    function _packSet(bytes32[] memory values) private pure returns (bytes memory out) {
        require(values.length != 0, EmptySet());
        LibSort.sort(values);
        LibSort.uniquifySorted(values);
        uint256 length = values.length;
        require(length <= 2047, SetTooLarge());
        out = new bytes(length * 32);
        for (uint256 i; i < length; ++i) {
            bytes32 word = values[i];
            assembly ("memory-safe") {
                mstore(add(add(out, 32), mul(i, 32)), word)
            }
        }
    }

    /// @dev Packs a uint256 array into sorted, deduplicated 32-byte words.
    function _packSet(uint256[] memory values) private pure returns (bytes memory out) {
        require(values.length != 0, EmptySet());
        LibSort.sort(values);
        LibSort.uniquifySorted(values);
        uint256 length = values.length;
        require(length <= 2047, SetTooLarge());
        out = new bytes(length * 32);
        for (uint256 i; i < length; ++i) {
            bytes32 word = bytes32(values[i]);
            assembly ("memory-safe") {
                mstore(add(add(out, 32), mul(i, 32)), word)
            }
        }
    }

    /// @dev Packs an int256 array into sorted, deduplicated 32-byte words.
    /// Sorts by unsigned byte representation (lexicographic), not signed value.
    function _packSet(int256[] memory values) private pure returns (bytes memory out) {
        require(values.length != 0, EmptySet());
        uint256[] memory unsigned;
        assembly ("memory-safe") {
            unsigned := values
        }
        LibSort.sort(unsigned);
        LibSort.uniquifySorted(unsigned);
        uint256 length = unsigned.length;
        require(length <= 2047, SetTooLarge());
        out = new bytes(length * 32);
        for (uint256 i; i < length; ++i) {
            bytes32 word = bytes32(unsigned[i]);
            assembly ("memory-safe") {
                mstore(add(add(out, 32), mul(i, 32)), word)
            }
        }
    }
}


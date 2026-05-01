// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { LibBytes } from "solady/utils/LibBytes.sol";

import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for Constraint unit tests.
abstract contract ConstraintTest is BaseTest {
    /// @dev Extracts the packed set as a bytes32 array from a constraint operator.
    /// The operator format is: opCode (1 byte) || packedSet (n * 32 bytes).
    function _extractPackedSet(bytes memory operator) internal pure returns (bytes32[] memory) {
        require(operator.length > 1, "Operator too short");

        // Enforce exact 32-byte word packing (prevents silently ignoring trailing bytes).
        uint256 dataLength = operator.length - 1;
        require(dataLength % 32 == 0, "Packed set length not multiple of 32");

        uint256 setLength = dataLength / 32;
        bytes32[] memory elements = new bytes32[](setLength);
        for (uint256 i; i < setLength; ++i) {
            elements[i] = LibBytes.load(operator, 1 + (i * 32));
        }
        return elements;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                HELPERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Asserts canonical set properties: strictly increasing + bidirectional membership.
    function assertCanonicalSet(bytes32[] memory set, bytes32[] memory input) internal pure {
        // 1. Output is strictly increasing (implies sorted + unique)
        for (uint256 i = 1; i < set.length; ++i) {
            assertLt(uint256(set[i - 1]), uint256(set[i]), "not sorted or has duplicates");
        }
        // 2. Bidirectional membership (no fabrication, no loss)
        for (uint256 i = 0; i < set.length; ++i) {
            _assertIn(set[i], input, "output element not in input");
        }
        for (uint256 i = 0; i < input.length; ++i) {
            _assertIn(input[i], set, "input element not in output");
        }
    }

    function _assertIn(bytes32 val, bytes32[] memory arr, string memory message) private pure {
        bool found;
        for (uint256 i = 0; i < arr.length; ++i) {
            if (val == arr[i]) {
                found = true;
                break;
            }
        }
        assertTrue(found, message);
    }

    /// @dev Asserts two arrays are element-wise equal.
    function assertArrayEq(bytes32[] memory expected, bytes32[] memory actual) internal pure {
        assertEq(expected.length, actual.length, "array length mismatch");
        for (uint256 i; i < expected.length; ++i) {
            assertEq(expected[i], actual[i]);
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                              TYPE CONVERSIONS
    /////////////////////////////////////////////////////////////////////////*/

    function _toBytes32Array(uint256[] memory arr) internal pure returns (bytes32[] memory out) {
        assembly ("memory-safe") {
            out := arr
        }
    }

    function _toBytes32Array(int256[] memory arr) internal pure returns (bytes32[] memory out) {
        assembly ("memory-safe") {
            out := arr
        }
    }

    function _toBytes32Array(address[] memory arr) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](arr.length);
        for (uint256 i; i < arr.length; ++i) {
            out[i] = bytes32(uint256(uint160(arr[i])));
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                              LENGTH HELPERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Constrains a fuzzed array's length into `[min, max]`. Filters via `vm.assume`
    /// when shorter than `min`; truncates in-place when longer than `max`.
    function _boundLength(uint256[] memory arr, uint256 min, uint256 max) internal pure {
        vm.assume(arr.length >= min);
        assembly ("memory-safe") {
            if gt(mload(arr), max) { mstore(arr, max) }
        }
    }

    function _boundLength(int256[] memory arr, uint256 min, uint256 max) internal pure {
        uint256[] memory u;
        assembly ("memory-safe") {
            u := arr
        }
        _boundLength(u, min, max);
    }

    function _boundLength(address[] memory arr, uint256 min, uint256 max) internal pure {
        uint256[] memory u;
        assembly ("memory-safe") {
            u := arr
        }
        _boundLength(u, min, max);
    }

    function _boundLength(bytes32[] memory arr, uint256 min, uint256 max) internal pure {
        uint256[] memory u;
        assembly ("memory-safe") {
            u := arr
        }
        _boundLength(u, min, max);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SHUFFLE HELPERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Fisher-Yates shuffle (in-place, deterministic via seed).
    function _shuffle(uint256[] memory arr, uint256 seed) internal pure {
        for (uint256 i = arr.length - 1; i > 0; --i) {
            uint256 j = uint256(keccak256(abi.encode(seed, i))) % (i + 1);
            (arr[i], arr[j]) = (arr[j], arr[i]);
        }
    }

    function _shuffle(int256[] memory arr, uint256 seed) internal pure {
        uint256[] memory u;
        assembly ("memory-safe") {
            u := arr
        }
        _shuffle(u, seed);
    }

    function _shuffle(address[] memory arr, uint256 seed) internal pure {
        uint256[] memory u;
        assembly ("memory-safe") {
            u := arr
        }
        _shuffle(u, seed);
    }

    function _shuffle(bytes32[] memory arr, uint256 seed) internal pure {
        uint256[] memory u;
        assembly ("memory-safe") {
            u := arr
        }
        _shuffle(u, seed);
    }
}

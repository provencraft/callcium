// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Be16 } from "./Be16.sol";

/// @title Path
/// @notice Encodes and inspects descriptor paths as big-endian uint16 sequences.
/// @dev Paths represent navigation through ABI-encoded calldata:
/// - path[0] is the top-level argument index
/// - path[1..n] are indices into nested composites (tuples, arrays)
library Path {
    /// @dev Universal quantifier for array paths (∀). Rule must pass for ALL elements.
    /// @dev Only valid immediately after an array node. Empty arrays yield true (vacuous truth).
    uint16 internal constant ALL_OR_EMPTY = 0xFFFF;

    /// @dev Universal quantifier for array paths (∀). Rule must pass for ALL elements and the array MUST NOT be empty.
    /// @dev Only valid immediately after an array node. Empty arrays yield false.
    uint16 internal constant ALL = 0xFFFE;

    /// @dev Existential quantifier for array paths (∃). Rule must pass for AT LEAST ONE element.
    /// @dev Only valid immediately after an array node. Empty arrays yield false.
    uint16 internal constant ANY = 0xFFFD;

    /*/////////////////////////////////////////////////////////////////////////
                                     ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the path is empty.
    error EmptyPath();

    /// @notice Thrown when accessing a step position beyond the path depth.
    /// @param stepIndex The 0-based step index.
    /// @param depth The path depth.
    error IndexOutOfBounds(uint256 stepIndex, uint256 depth);

    /// @notice Thrown when the be16-encoded path is malformed (empty or odd length).
    error MalformedPath();

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Encodes a single-step path.
    /// @param p0 The first path step.
    /// @return out The encoded path bytes.
    function encode(uint16 p0) internal pure returns (bytes memory out) {
        out = new bytes(2);
        Be16.write(out, 0, p0);
    }

    /// @notice Encodes a two-step path.
    /// @param p0 The first path step.
    /// @param p1 The second path step.
    /// @return out The encoded path bytes.
    function encode(uint16 p0, uint16 p1) internal pure returns (bytes memory out) {
        out = new bytes(4);
        Be16.write(out, 0, p0);
        Be16.write(out, 2, p1);
    }

    /// @notice Encodes a three-step path.
    /// @param p0 The first path step.
    /// @param p1 The second path step.
    /// @param p2 The third path step.
    /// @return out The encoded path bytes.
    function encode(uint16 p0, uint16 p1, uint16 p2) internal pure returns (bytes memory out) {
        out = new bytes(6);
        Be16.write(out, 0, p0);
        Be16.write(out, 2, p1);
        Be16.write(out, 4, p2);
    }

    /// @notice Encodes a four-step path.
    /// @param p0 The first path step.
    /// @param p1 The second path step.
    /// @param p2 The third path step.
    /// @param p3 The fourth path step.
    /// @return out The encoded path bytes.
    function encode(uint16 p0, uint16 p1, uint16 p2, uint16 p3) internal pure returns (bytes memory out) {
        out = new bytes(8);
        Be16.write(out, 0, p0);
        Be16.write(out, 2, p1);
        Be16.write(out, 4, p2);
        Be16.write(out, 6, p3);
    }

    /// @notice Encodes a path from a uint16 array.
    /// @param path The path indices as an array.
    /// @return out The encoded path bytes.
    function encode(uint16[] memory path) internal pure returns (bytes memory out) {
        uint256 pathLength = path.length;
        require(pathLength != 0, EmptyPath());
        out = new bytes(pathLength * 2);
        for (uint256 i; i < pathLength; ++i) {
            Be16.write(out, i * 2, path[i]);
        }
    }

    /// @notice Decodes a be16-encoded path into a uint16 array.
    /// @param self The encoded path bytes.
    /// @return out The decoded path steps.
    function decode(bytes memory self) internal pure returns (uint16[] memory out) {
        uint256 pathDepth = self.length / 2;
        require(pathDepth != 0, EmptyPath());
        out = new uint16[](pathDepth);
        for (uint256 i; i < pathDepth; ++i) {
            out[i] = Be16.readUnchecked(self, i * 2);
        }
    }

    /// @notice Returns the depth (number of steps) in a path.
    /// @param self The encoded path bytes.
    /// @return The number of steps in the path.
    function depth(bytes memory self) internal pure returns (uint256) {
        return self.length / 2;
    }

    /// @notice Validates strict be16 payload: non-empty and even length. Returns depth.
    /// @param self The encoded path bytes.
    /// @return The number of steps in the path.
    function validate(bytes memory self) internal pure returns (uint256) {
        uint256 length = self.length;
        require(length != 0 && length % 2 == 0, MalformedPath());
        return length / 2;
    }

    /// @notice Returns the step at a given step index in the path.
    /// @param self The encoded path bytes.
    /// @param stepIndex The 0-based step index.
    /// @return The uint16 step value at the given index.
    function at(bytes memory self, uint256 stepIndex) internal pure returns (uint16) {
        uint256 pathDepth = self.length / 2;
        require(stepIndex < pathDepth, IndexOutOfBounds(stepIndex, pathDepth));
        return Be16.readUnchecked(self, stepIndex * 2);
    }

    /// @notice Returns the step at a given step index without bounds checks. Caller must ensure `stepIndex < depth`.
    /// @param self The encoded path bytes.
    /// @param stepIndex The 0-based step index.
    /// @return The uint16 step value at the given index.
    function atUnchecked(bytes memory self, uint256 stepIndex) internal pure returns (uint16) {
        return Be16.readUnchecked(self, stepIndex * 2);
    }
}

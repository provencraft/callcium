// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { Path } from "src/Path.sol";

abstract contract BaseTest is Test {
    struct TwoUints {
        uint256 a;
        uint256 b;
    }

    /// @dev Encodes a single-step path.
    function _path(uint16 p0) internal pure returns (bytes memory) {
        return Path.encode(p0);
    }

    /// @dev Encodes a two-step path.
    function _path(uint16 p0, uint16 p1) internal pure returns (bytes memory) {
        return Path.encode(p0, p1);
    }

    /// @dev Encodes a three-step path.
    function _path(uint16 p0, uint16 p1, uint16 p2) internal pure returns (bytes memory) {
        return Path.encode(p0, p1, p2);
    }

    /// @dev Encodes a four-step path.
    function _path(uint16 p0, uint16 p1, uint16 p2, uint16 p3) internal pure returns (bytes memory) {
        return Path.encode(p0, p1, p2, p3);
    }

    /// @dev Encodes a path from an array of steps.
    function _path(uint16[] memory path) internal pure returns (bytes memory) {
        return Path.encode(path);
    }
}

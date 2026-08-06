// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Be16 } from "src/Be16.sol";
import { Path } from "src/Path.sol";
import { Policy } from "src/Policy.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

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

    /// @dev Returns the offset of the first group header within a policy blob.
    function _firstGroupOffset(bytes memory blob) internal pure returns (uint256) {
        uint16 descLen = Be16.readUnchecked(blob, PF.POLICY_DESC_LENGTH_OFFSET);
        return PF.POLICY_HEADER_PREFIX + descLen + PF.POLICY_GROUP_COUNT_SIZE;
    }

    /// @dev Returns the offset of the first rule within the first group.
    function _firstRuleOffset(bytes memory blob) internal pure returns (uint256) {
        return _firstGroupOffset(blob) + PF.GROUP_HEADER_SIZE;
    }

    /// @dev Returns the offset of the operator code within the rule at `ruleOffset`.
    function _opCodeOffset(bytes memory blob, uint256 ruleOffset) internal pure returns (uint256) {
        (uint256 hintOffset, uint256 hintSize) = Policy.hintView(blob, ruleOffset);
        return hintOffset + hintSize;
    }

    /// @dev Writes a big-endian uint32 into `blob` at `offset`.
    function _writeU32(bytes memory blob, uint256 offset, uint32 value) internal pure {
        // forge-lint: disable-next-line(unsafe-typecast) casting to 'uint8' is safe because value is uint32 and the shift discards upper bits
        blob[offset] = bytes1(uint8(value >> 24));
        // forge-lint: disable-next-line(unsafe-typecast)
        blob[offset + 1] = bytes1(uint8(value >> 16));
        // forge-lint: disable-next-line(unsafe-typecast)
        blob[offset + 2] = bytes1(uint8(value >> 8));
        // forge-lint: disable-next-line(unsafe-typecast)
        blob[offset + 3] = bytes1(uint8(value));
    }
}

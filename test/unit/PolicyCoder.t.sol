// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { LibBytes } from "solady/utils/LibBytes.sol";

import { Be16 } from "src/Be16.sol";
import { PolicyCoder } from "src/PolicyCoder.sol";
import { PolicyFormat } from "src/PolicyFormat.sol";

import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for PolicyCoder unit tests.
abstract contract PolicyCoderTest is BaseTest {
    /// @dev Computes the offset to the first rule in a policy blob with the given descriptor length.
    function _firstRuleOffset(uint256 descLength) internal pure returns (uint256) {
        // forgefmt: disable-next-item
        return PolicyFormat.POLICY_HEADER_PREFIX
            + descLength
            + PolicyFormat.POLICY_GROUP_COUNT_SIZE
            + PolicyFormat.GROUP_HEADER_SIZE;
    }

    /// @dev Reads a big-endian uint16 from `blob` at `offset`.
    function _readU16(bytes memory blob, uint256 offset) internal pure returns (uint16) {
        return Be16.readUnchecked(blob, offset);
    }

    /// @dev Reads a big-endian uint32 from `blob` at `offset`.
    function _readU32(bytes memory blob, uint256 offset) internal pure returns (uint32) {
        return uint32(Be16.readUnchecked(blob, offset)) << 16 | Be16.readUnchecked(blob, offset + 2);
    }

    /// @dev Reads a bytes32 from `blob` at `offset`.
    function _readBytes32(bytes memory blob, uint256 offset) internal pure returns (bytes32) {
        return LibBytes.load(blob, offset);
    }

    /// @dev Creates a policy with one group containing one rule.
    function _singleRule(
        uint8 scope,
        bytes memory path,
        bytes memory op
    )
        internal
        pure
        returns (PolicyCoder.Group[] memory groups)
    {
        groups = new PolicyCoder.Group[](1);
        groups[0].rules = new PolicyCoder.Rule[](1);
        groups[0].rules[0] = PolicyCoder.Rule(scope, path, op);
    }

    /// @dev Creates a policy with one group containing two rules.
    function _twoRules(
        PolicyCoder.Rule memory ruleA,
        PolicyCoder.Rule memory ruleB
    )
        internal
        pure
        returns (PolicyCoder.Group[] memory groups)
    {
        groups = new PolicyCoder.Group[](1);
        groups[0].rules = new PolicyCoder.Rule[](2);
        groups[0].rules[0] = ruleA;
        groups[0].rules[1] = ruleB;
    }

    /// @dev Encodes an operator with one bytes32 argument.
    function _op1(uint8 code, bytes32 value) internal pure returns (bytes memory) {
        return abi.encodePacked(code, value);
    }

    /// @dev Encodes an operator with two bytes32 arguments.
    function _op2(uint8 code, bytes32 first, bytes32 second) internal pure returns (bytes memory) {
        return abi.encodePacked(code, first, second);
    }

    /// @dev Encodes an operator with three bytes32 arguments.
    function _op3(uint8 code, bytes32 first, bytes32 second, bytes32 third) internal pure returns (bytes memory) {
        return abi.encodePacked(code, first, second, third);
    }
}

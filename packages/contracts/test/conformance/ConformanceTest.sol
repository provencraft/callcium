// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// forge-lint: disable-start(unsafe-typecast)

import { Test } from "forge-std/Test.sol";

import { Constraint } from "src/Constraint.sol";
import { PolicyData } from "src/PolicyCoder.sol";

/// @notice Shared parsing for vector files that carry a structured policy under a `policy` key.
abstract contract ConformanceTest is Test {
    /// @dev Counts the entries of the JSON array indexed as `prefix` + index + `]`.
    function _count(string memory json, string memory prefix) internal view returns (uint256 count) {
        while (vm.keyExistsJson(json, string.concat(prefix, vm.toString(count), "]"))) ++count;
    }

    /// @dev Counts the entries of the top-level array in `json`.
    function _vectorCount(string memory json) internal view returns (uint256) {
        return _count(json, ".[");
    }

    /// @dev Builds a PolicyData from the `policy` object of the vector at `indexString`.
    function _policyData(string memory json, string memory indexString) internal view returns (PolicyData memory data) {
        string memory policyPath = string.concat(".[", indexString, "].policy");

        data.isSelectorless = vm.parseJsonBool(json, string.concat(policyPath, ".isSelectorless"));
        data.selector = bytes4(vm.parseJsonBytes(json, string.concat(policyPath, ".selector")));
        data.descriptor = vm.parseJsonBytes(json, string.concat(policyPath, ".descriptor"));

        uint256 groupCount = _count(json, string.concat(policyPath, ".groups["));

        data.groups = new Constraint[][](groupCount);
        for (uint256 groupIndex = 0; groupIndex < groupCount; ++groupIndex) {
            string memory groupPath = string.concat(policyPath, ".groups[", vm.toString(groupIndex), "].constraints");
            uint256 constraintCount = _count(json, string.concat(groupPath, "["));
            data.groups[groupIndex] = new Constraint[](constraintCount);
            for (uint256 constraintIndex = 0; constraintIndex < constraintCount; ++constraintIndex) {
                string memory constraintPath = string.concat(groupPath, "[", vm.toString(constraintIndex), "]");
                uint256 operatorCount = _count(json, string.concat(constraintPath, ".operators["));
                bytes[] memory operators = new bytes[](operatorCount);
                for (uint256 operatorIndex = 0; operatorIndex < operatorCount; ++operatorIndex) {
                    operators[operatorIndex] = vm.parseJsonBytes(
                        json, string.concat(constraintPath, ".operators[", vm.toString(operatorIndex), "]")
                    );
                }
                string memory hintPath = string.concat(constraintPath, ".hint");
                bytes memory hint;
                if (vm.keyExistsJson(json, hintPath)) hint = vm.parseJsonBytes(json, hintPath);
                data.groups[groupIndex][constraintIndex] = Constraint({
                    scope: uint8(vm.parseJsonUint(json, string.concat(constraintPath, ".scope"))),
                    path: vm.parseJsonBytes(json, string.concat(constraintPath, ".path")),
                    operators: operators,
                    hint: hint
                });
            }
        }
    }
}

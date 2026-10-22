// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";

import { Policy } from "src/Policy.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";
import { LibBytes } from "src/vendor/solady/utils/LibBytes.sol";

import { CalldataMutation } from "script/CalldataMutation.sol";

/// @notice Writes mutations of the Lean enforcement corpus's calldata, one line per mutation: `id blob calldata context`.
/// @dev Each corpus line yields `MUTANTS` lines that mutate the arguments past the selector, drawn from Foundry's
/// random cheatcodes.
contract LeanEnforcementMutation is Script, CalldataMutation {
    string internal constant CORPUS = "../../spec/lean/corpus/enforcement.txt";
    string internal constant OUT = "../../spec/lean/corpus/enforcement-mutants.txt";

    uint256 internal constant MUTANTS = 3;

    /// @dev Writes the mutations of every corpus line.
    function run() public {
        if (vm.exists(OUT)) vm.removeFile(OUT);

        for (string memory line = vm.readLine(CORPUS); bytes(line).length != 0; line = vm.readLine(CORPUS)) {
            _mutate(vm.split(line, " "));
        }
        vm.closeFile(CORPUS);
    }

    /// @dev Writes the mutations of one corpus line.
    function _mutate(string[] memory fields) private {
        bytes memory blob = vm.parseBytes(fields[1]);
        bytes memory callData = vm.parseBytes(fields[2]);
        // The arguments start past the selector unless the policy is selectorless.
        uint256 argumentsStart = Policy.isSelectorless(blob) ? 0 : PF.POLICY_SELECTOR_SIZE;
        bytes memory selector = LibBytes.slice(callData, 0, argumentsStart);
        bytes memory arguments = LibBytes.slice(callData, argumentsStart);
        for (uint256 i = 0; i < MUTANTS; ++i) {
            bytes memory mutated = bytes.concat(selector, mutate(arguments));
            vm.writeLine(OUT, string.concat(fields[0], " ", fields[1], " ", vm.toString(mutated), " ", fields[3]));
        }
    }
}

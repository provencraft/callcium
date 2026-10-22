// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyValidator } from "src/PolicyValidator.sol";

import { ConformanceTest } from "test/conformance/ConformanceTest.sol";

/// @notice Replays the Lean validation corpus through the validator for `lake exe check-validation`.
/// @dev Asserts each line's issues against the model's, in any order. Skipped without a generated corpus.
contract PolicyValidatorDifferentialTest is ConformanceTest {
    string internal constant CORPUS = "../../spec/lean/corpus/validation.txt";
    string internal constant OUT = "out/validation.txt";

    function test_ReplaysValidationCorpus() public {
        vm.skip(!vm.exists(CORPUS));
        if (vm.exists(OUT)) vm.removeFile(OUT);

        uint256 freeMemory;
        assembly ("memory-safe") {
            freeMemory := mload(0x40)
        }
        for (string memory line = vm.readLine(CORPUS); bytes(line).length != 0; line = vm.readLine(CORPUS)) {
            // Each line gets the whole gas limit: the corpus outruns one limit, and a looping line still runs out.
            vm.resetGasMetering();
            string[] memory fields = vm.split(line, " ");
            assertEq(fields.length, 3, line);
            string[] memory keys = _issueKeys(PolicyValidator.validate(vm.parseBytes(fields[1])));
            // Issues are comma separated, `-` for none.
            string memory written = "-";
            for (uint256 i = 0; i < keys.length; ++i) {
                written = i == 0 ? keys[i] : string.concat(written, ",", keys[i]);
            }
            string[] memory expected =
                keccak256(bytes(fields[2])) == keccak256("-") ? new string[](0) : vm.split(fields[2], ",");
            _assertSameIssues(keys, expected, fields[0]);
            vm.writeLine(OUT, string.concat(fields[0], " ", fields[1], " ", written));
            // The next line reuses this line's memory.
            assembly ("memory-safe") {
                mstore(0x40, freeMemory)
            }
        }
    }
}

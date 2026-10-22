// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { PolicyHarness } from "test/harnesses/PolicyHarness.sol";

/// @notice Replays the Lean storage corpus through storage validation for `lake exe check-storage`.
/// @dev Asserts each verdict against the model's. Skipped without a generated corpus.
contract PolicyDifferentialTest is Test {
    string internal constant CORPUS = "../../spec/lean/corpus/storage.txt";
    string internal constant OUT = "out/storage.txt";

    bytes4 internal constant PANIC_SELECTOR = bytes4(keccak256("Panic(uint256)"));

    PolicyHarness internal harness;

    function setUp() public {
        harness = new PolicyHarness();
    }

    /// @dev Returns the storage verdict on `blob` as the corpus spells it.
    function _verdict(bytes memory blob) private view returns (string memory) {
        try harness.validate(blob) {
            return "accept";
        } catch (bytes memory reason) {
            // A storage rejection is a custom error; a panic or a revert without data is a crash in the reader.
            assertTrue(reason.length >= 4 && bytes4(reason) != PANIC_SELECTOR, "storage validation crashed");
            return "reject";
        }
    }

    function test_ReplaysStorageCorpus() public {
        vm.skip(!vm.exists(CORPUS));
        if (vm.exists(OUT)) vm.removeFile(OUT);

        uint256 freeMemory;
        assembly ("memory-safe") {
            freeMemory := mload(0x40)
        }
        for (string memory line = vm.readLine(CORPUS); bytes(line).length != 0; line = vm.readLine(CORPUS)) {
            string[] memory fields = vm.split(line, " ");
            assertEq(fields.length, 3, line);
            string memory verdict = _verdict(vm.parseBytes(fields[1]));
            assertEq(verdict, fields[2], fields[0]);
            vm.writeLine(OUT, string.concat(fields[0], " ", fields[1], " ", verdict));
            // The next line reuses this line's memory.
            assembly ("memory-safe") {
                mstore(0x40, freeMemory)
            }
        }
    }
}

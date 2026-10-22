// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ConformanceTest } from "test/conformance/ConformanceTest.sol";
import { PolicyCoderHarness } from "test/harnesses/PolicyCoderHarness.sol";

/// @notice Replays the Lean encoding corpus through the decoder and unchecked encoder for `lake exe check-encoding`.
/// @dev Asserts each encoded blob against the model's. Skipped without a generated corpus.
contract PolicyCoderDifferentialTest is ConformanceTest {
    string internal constant CORPUS = "../../spec/lean/corpus/encoding.txt";
    string internal constant OUT = "out/encoding.txt";

    PolicyCoderHarness internal coder;

    function setUp() public {
        coder = new PolicyCoderHarness();
    }

    function test_ReplaysEncodingCorpus() public {
        vm.skip(!vm.exists(CORPUS));
        if (vm.exists(OUT)) vm.removeFile(OUT);

        uint256 freeMemory;
        assembly ("memory-safe") {
            freeMemory := mload(0x40)
        }
        for (string memory line = vm.readLine(CORPUS); bytes(line).length != 0; line = vm.readLine(CORPUS)) {
            string[] memory fields = vm.split(line, " ");
            assertEq(fields.length, 3, line);
            // An encoder refusal is spelled `0x`, the empty blob.
            string memory encoded = vm.toString(_reencode(coder, vm.parseBytes(fields[1])));
            assertEq(encoded, fields[2], fields[0]);
            vm.writeLine(OUT, string.concat(fields[0], " ", fields[1], " ", encoded));
            // The next line reuses this line's memory.
            assembly ("memory-safe") {
                mstore(0x40, freeMemory)
            }
        }
    }
}

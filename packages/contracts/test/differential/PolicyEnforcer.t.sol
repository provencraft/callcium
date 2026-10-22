// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyFormat as PF } from "src/PolicyFormat.sol";

import { ConformanceTest } from "test/conformance/ConformanceTest.sol";
import { PolicyEnforcerContextHarness } from "test/harnesses/PolicyEnforcerContextHarness.sol";

/// @notice Replays the Lean enforcement corpus and its mutated-calldata lines through the enforcer for
/// `lake exe check-enforcement`.
/// @dev Each line runs under the context it carries and is written with its outcome. A corpus line has its outcome
/// asserted against the model's. Skipped without a generated corpus and its mutations.
contract PolicyEnforcerDifferentialTest is ConformanceTest {
    string internal constant CORPUS = "../../spec/lean/corpus/enforcement.txt";
    string internal constant MUTANTS = "../../spec/lean/corpus/enforcement-mutants.txt";
    string internal constant OUT = "out/enforcement.txt";

    uint256 internal constant CORPUS_FIELDS = 5;
    uint256 internal constant MUTANT_FIELDS = 4;

    PolicyEnforcerContextHarness internal harness;

    function setUp() public {
        harness = new PolicyEnforcerContextHarness();
    }

    /// @dev Returns the words of a corpus context field.
    function _context(string memory field) private pure returns (bytes32[] memory context) {
        string[] memory entries = vm.split(field, ",");
        context = new bytes32[](PF.CTX_MAX + 1);
        assertEq(entries.length, context.length, field);
        for (uint256 id = 0; id < context.length; ++id) {
            context[id] = vm.parseBytes32(entries[id]);
        }
    }

    /// @dev Returns the outcome of `callData` against `blob` under `context`, as the corpus spells it.
    function _outcome(
        bytes memory blob,
        bytes memory callData,
        bytes32[] memory context
    )
        private
        returns (string memory)
    {
        address sender = address(uint160(uint256(context[PF.CTX_MSG_SENDER])));
        uint256 value = uint256(context[PF.CTX_MSG_VALUE]);
        vm.warp(uint256(context[PF.CTX_BLOCK_TIMESTAMP]));
        vm.roll(uint256(context[PF.CTX_BLOCK_NUMBER]));
        vm.chainId(uint256(context[PF.CTX_CHAIN_ID]));
        vm.fee(uint256(context[PF.CTX_BASE_FEE]));
        vm.txGasPrice(uint256(context[PF.CTX_GAS_PRICE]));
        // The harness keeps every value sent to it, so it starts each call empty.
        vm.deal(address(harness), 0);
        vm.deal(sender, value);
        vm.prank(sender, address(uint160(uint256(context[PF.CTX_TX_ORIGIN]))));
        try harness.checkWithContext{ value: value }(blob, callData) returns (bool ok, bytes32[] memory observed) {
            for (uint256 id = 0; id < context.length; ++id) {
                assertEq(observed[id], context[id], "observed context");
            }
            return ok ? "pass" : "fail";
        } catch (bytes memory reason) {
            return _abortCode(reason);
        }
    }

    /// @dev Replays every line of `path` and writes it with its outcome, asserting the outcome of a corpus line.
    function _replayFile(string memory path, bool corpus) private {
        uint256 freeMemory;
        assembly ("memory-safe") {
            freeMemory := mload(0x40)
        }
        for (string memory line = vm.readLine(path); bytes(line).length != 0; line = vm.readLine(path)) {
            string[] memory fields = vm.split(line, " ");
            assertEq(fields.length, corpus ? CORPUS_FIELDS : MUTANT_FIELDS, line);
            string memory outcome = _outcome(vm.parseBytes(fields[1]), vm.parseBytes(fields[2]), _context(fields[3]));
            if (corpus) assertEq(outcome, fields[4], fields[0]);
            vm.writeLine(OUT, string.concat(fields[0], " ", fields[1], " ", fields[2], " ", fields[3], " ", outcome));
            // The next line reuses this line's memory.
            assembly ("memory-safe") {
                mstore(0x40, freeMemory)
            }
        }
        vm.closeFile(path);
    }

    function test_ReplaysEnforcementCorpus() public {
        vm.skip(!vm.exists(CORPUS) || !vm.exists(MUTANTS));
        if (vm.exists(OUT)) vm.removeFile(OUT);

        _replayFile(CORPUS, true);
        _replayFile(MUTANTS, false);
    }
}

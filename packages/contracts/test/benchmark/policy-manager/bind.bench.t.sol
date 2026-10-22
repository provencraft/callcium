// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyManagerBench } from "../PolicyManager.bench.t.sol";

/// @notice Benchmarks for PolicyManager.bind().
contract BindBench is PolicyManagerBench {
    function test_Target() public {
        harness.bind(target, policyHash);
        vm.snapshotGasLastFrame("PolicyManager.bind", "target");
        assertEq(harness.hashFor(target, SELECTOR), policyHash);
    }

    function test_Rebind() public {
        // Binds over another policy bound under the same pair, so the call reports the previous binding's hash.
        (bytes32 otherHash,) = harness.store(OTHER_BLOB);
        harness.bind(target, otherHash);

        harness.bind(target, policyHash);
        vm.snapshotGasLastFrame("PolicyManager.bind", "rebind");
        assertEq(harness.hashFor(target, SELECTOR), policyHash);
    }
}

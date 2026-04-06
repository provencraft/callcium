// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyBuilderBench } from "../PolicyBuilder.bench.t.sol";

/// @dev Benchmarks for PolicyBuilder.buildUnsafe (no validation).
contract BuildUncheckedBench is PolicyBuilderBench {
    function _safe() internal pure override returns (bool) {
        return false;
    }

    function _label() internal pure override returns (string memory) {
        return "PolicyBuilder.buildUnsafe";
    }
}

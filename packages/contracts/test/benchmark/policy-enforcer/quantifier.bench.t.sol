// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg } from "src/Constraint.sol";
import { Path } from "src/Path.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyEnforcerTest } from "test/unit/PolicyEnforcer.t.sol";

/// @dev Pins gas linearity of quantified evaluation: the suffix descent allocates per element,
///      so a broken free-memory-pointer rewind shows up as superlinear growth across these sizes.
contract QuantifierBench is PolicyEnforcerTest {
    bytes internal policy;
    bytes internal callData8;
    bytes internal callData64;
    bytes internal callData256;

    function setUp() public override {
        super.setUp();
        policy = PolicyBuilder.create("foo((uint256,address)[])").add(arg(0, Path.ALL, 1).eq(address(1))).build();
        callData8 = _quantifiedCallData(8);
        callData64 = _quantifiedCallData(64);
        callData256 = _quantifiedCallData(256);
    }

    /// @dev ALL over every element with a tuple-field suffix: worst case, no short-circuit.
    function _quantifiedCallData(uint256 count) private pure returns (bytes memory) {
        bytes memory elems;
        for (uint256 i; i < count; ++i) {
            elems = abi.encodePacked(elems, uint256(i), uint256(uint160(address(1))));
        }
        return abi.encodePacked(bytes4(keccak256("foo((uint256,address)[])")), uint256(0x20), count, elems);
    }

    function test_Suffix8() public {
        harness.enforce(policy, callData8);
        vm.snapshotGasLastCall("PolicyEnforcer.quantifier", "suffix8");
    }

    function test_Suffix64() public {
        harness.enforce(policy, callData64);
        vm.snapshotGasLastCall("PolicyEnforcer.quantifier", "suffix64");
    }

    function test_Suffix256() public {
        harness.enforce(policy, callData256);
        vm.snapshotGasLastCall("PolicyEnforcer.quantifier", "suffix256");
    }
}

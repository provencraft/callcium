// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyEnforcerTest } from "test/unit/PolicyEnforcer.t.sol";

contract LengthBench is PolicyEnforcerTest {
    bytes internal policyArray;
    bytes internal callDataArray;
    bytes internal policyBytes;
    bytes internal callDataBytes;

    function setUp() public override {
        super.setUp();

        policyArray = PolicyBuilder.create("foo(uint256[])").add(arg(0).lengthGte(1)).buildUnsafe();
        callDataArray = abi.encodeWithSignature("foo(uint256[])", _uintArray(3));

        policyBytes = PolicyBuilder.create("foo(bytes)").add(arg(0).lengthGte(1)).buildUnsafe();
        callDataBytes = abi.encodeWithSignature("foo(bytes)", hex"01");
    }

    function test_LengthArray() public {
        harness.enforce(policyArray, callDataArray);
        vm.snapshotGasLastCall("PolicyEnforcer.length", "array");
    }

    function test_LengthBytes() public {
        harness.enforce(policyBytes, callDataBytes);
        vm.snapshotGasLastCall("PolicyEnforcer.length", "bytes");
    }
}

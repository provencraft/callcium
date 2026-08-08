// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyEnforcerBench } from "../PolicyEnforcer.bench.t.sol";

/// @dev Length-operator cost through the reverting entry point, over both targets that carry a
///      declared length: a dynamic array and a `bytes` payload.
contract LengthBench is PolicyEnforcerBench {
    Fixture internal lengthArray;
    Fixture internal lengthBytes;

    function setUp() public override {
        super.setUp();

        // forgefmt: disable-next-item
        lengthArray = _buildFixture(
            PolicyBuilder.create("foo(uint256[])")
                .add(arg(0).lengthGte(1)),
            abi.encodeWithSignature("foo(uint256[])", _uintArray(3))
        );

        // forgefmt: disable-next-item
        lengthBytes = _buildFixture(
            PolicyBuilder.create("foo(bytes)")
                .add(arg(0).lengthGte(1)),
            abi.encodeWithSignature("foo(bytes)", hex"01")
        );
    }

    function test_LengthArray() public {
        _benchEnforce(lengthArray, "length_array");
    }

    function test_LengthBytes() public {
        _benchEnforce(lengthBytes, "length_bytes");
    }
}

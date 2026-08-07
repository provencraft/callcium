// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg } from "src/Constraint.sol";
import { Path } from "src/Path.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyEnforcerTest } from "test/unit/PolicyEnforcer.t.sol";

/// @dev Pins gas linearity of quantified evaluation: the suffix descent allocates per element,
///      so a broken free-memory-pointer rewind shows up as superlinear growth across these sizes.
///      Both element shapes are covered — a static element addressed by stride alone, and a dynamic
///      element the frame reaches through its own offset word.
contract QuantifierBench is PolicyEnforcerTest {
    bytes internal policy;
    bytes internal callData8;
    bytes internal callData64;
    bytes internal callData256;

    bytes internal dynElemPolicy;
    bytes internal dynElemCallData8;
    bytes internal dynElemCallData64;
    bytes internal dynElemCallData256;

    bytes internal staticArrayPolicy;
    bytes internal staticArrayCallData;

    bytes internal dynTargetPolicy;
    bytes internal dynTargetCallData;

    function setUp() public override {
        super.setUp();
        policy = PolicyBuilder.create("foo((uint256,address)[])").add(arg(0, Path.ALL, 1).eq(address(1))).build();
        callData8 = _quantifiedCallData(8);
        callData64 = _quantifiedCallData(64);
        callData256 = _quantifiedCallData(256);

        // Dynamic elements: each element is reached through its own offset word.
        dynElemPolicy = PolicyBuilder.create("foo((uint256,bytes)[])").add(arg(0, Path.ALL, 0).eq(uint256(1))).build();
        dynElemCallData8 = _dynElemCallData(8);
        dynElemCallData64 = _dynElemCallData(64);
        dynElemCallData256 = _dynElemCallData(256);

        // Static array: the element count comes from the frame rather than from calldata.
        staticArrayPolicy = PolicyBuilder.create("foo(uint256[4])").add(arg(0, Path.ALL).eq(uint256(1))).build();
        uint256[4] memory elems = [uint256(1), 1, 1, 1];
        staticArrayCallData = abi.encodeWithSignature("foo(uint256[4])", elems);

        // Dynamic target: every element pays the payload-extent check before the operator.
        dynTargetPolicy = PolicyBuilder.create("foo(bytes[])").add(arg(0, Path.ALL).lengthEq(2)).build();
        dynTargetCallData = _dynTargetCallData(64);

        Policy.validate(policy);
        Policy.validate(dynElemPolicy);
        Policy.validate(staticArrayPolicy);
        Policy.validate(dynTargetPolicy);
    }

    /// @dev ALL over a dynamic array whose elements each carry their own declared length.
    function _dynTargetCallData(uint256 count) private pure returns (bytes memory) {
        bytes[] memory elems = new bytes[](count);
        for (uint256 i; i < count; ++i) {
            elems[i] = hex"0102";
        }
        return abi.encodeWithSignature("foo(bytes[])", elems);
    }

    /// @dev ALL over a dynamic array whose elements are themselves dynamic.
    function _dynElemCallData(uint256 count) private pure returns (bytes memory) {
        UintWithBytes[] memory elems = new UintWithBytes[](count);
        for (uint256 i; i < count; ++i) {
            elems[i] = UintWithBytes({ value: 1, payload: hex"0102" });
        }
        return abi.encodeWithSignature("foo((uint256,bytes)[])", elems);
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

    function test_DynElem8() public {
        harness.enforce(dynElemPolicy, dynElemCallData8);
        vm.snapshotGasLastCall("PolicyEnforcer.quantifier", "dyn_elem_8");
    }

    function test_DynElem64() public {
        harness.enforce(dynElemPolicy, dynElemCallData64);
        vm.snapshotGasLastCall("PolicyEnforcer.quantifier", "dyn_elem_64");
    }

    function test_DynElem256() public {
        harness.enforce(dynElemPolicy, dynElemCallData256);
        vm.snapshotGasLastCall("PolicyEnforcer.quantifier", "dyn_elem_256");
    }

    function test_StaticArrayQuantifier() public {
        harness.enforce(staticArrayPolicy, staticArrayCallData);
        vm.snapshotGasLastCall("PolicyEnforcer.quantifier", "static_array_quantifier");
    }

    function test_DynTarget64() public {
        harness.enforce(dynTargetPolicy, dynTargetCallData);
        vm.snapshotGasLastCall("PolicyEnforcer.quantifier", "dyn_target_64");
    }
}

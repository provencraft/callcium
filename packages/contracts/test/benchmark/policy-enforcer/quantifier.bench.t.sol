// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg } from "src/Constraint.sol";
import { Path } from "src/Path.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyEnforcerBench } from "../PolicyEnforcer.bench.t.sol";

/// @dev Pins gas linearity of quantified evaluation: the suffix descent allocates per element,
///      so a broken free-memory-pointer rewind shows up as superlinear growth across these sizes.
///      Both element shapes are covered — a static element addressed by stride alone, and a dynamic
///      element the frame reaches through its own offset word.
contract QuantifierBench is PolicyEnforcerBench {
    Fixture internal suffix8;
    Fixture internal suffix64;
    Fixture internal suffix256;

    Fixture internal dynElem8;
    Fixture internal dynElem64;
    Fixture internal dynElem256;

    Fixture internal staticArray;
    Fixture internal dynTarget64;

    function setUp() public override {
        super.setUp();

        // forgefmt: disable-next-item
        bytes memory suffixPolicy = PolicyBuilder.create("foo((uint256,address)[])")
            .add(arg(0, Path.ALL, 1).eq(address(1)))
            .build();
        suffix8 = _fixture(suffixPolicy, _quantifiedCallData(8));
        suffix64 = _fixture(suffixPolicy, _quantifiedCallData(64));
        suffix256 = _fixture(suffixPolicy, _quantifiedCallData(256));

        // Dynamic elements: each element is reached through its own offset word.
        // forgefmt: disable-next-item
        bytes memory dynElemPolicy = PolicyBuilder.create("foo((uint256,bytes)[])")
            .add(arg(0, Path.ALL, 0).eq(uint256(1)))
            .build();
        dynElem8 = _fixture(dynElemPolicy, _dynElemCallData(8));
        dynElem64 = _fixture(dynElemPolicy, _dynElemCallData(64));
        dynElem256 = _fixture(dynElemPolicy, _dynElemCallData(256));

        // Static array: the element count comes from the frame rather than from calldata.
        uint256[4] memory elems = [uint256(1), 1, 1, 1];
        // forgefmt: disable-next-item
        staticArray = _buildFixture(
            PolicyBuilder.create("foo(uint256[4])")
                .add(arg(0, Path.ALL).eq(uint256(1))),
            abi.encodeWithSignature("foo(uint256[4])", elems)
        );

        // Dynamic target: every element pays the payload-extent check before the operator.
        // forgefmt: disable-next-item
        dynTarget64 = _buildFixture(
            PolicyBuilder.create("foo(bytes[])")
                .add(arg(0, Path.ALL).lengthEq(2)),
            _dynTargetCallData(64)
        );
    }

    /// @dev ALL over a dynamic array whose elements each carry their own declared length.
    function _dynTargetCallData(uint256 count) private pure returns (bytes memory) {
        bytes[] memory elems = new bytes[](count);
        for (uint256 i = 0; i < count; ++i) {
            elems[i] = hex"0102";
        }
        return abi.encodeWithSignature("foo(bytes[])", elems);
    }

    /// @dev ALL over a dynamic array whose elements are themselves dynamic.
    function _dynElemCallData(uint256 count) private pure returns (bytes memory) {
        UintWithBytes[] memory elems = new UintWithBytes[](count);
        for (uint256 i = 0; i < count; ++i) {
            elems[i] = UintWithBytes({ value: 1, payload: hex"0102" });
        }
        return abi.encodeWithSignature("foo((uint256,bytes)[])", elems);
    }

    /// @dev ALL over every element with a tuple-field suffix: worst case, no short-circuit.
    function _quantifiedCallData(uint256 count) private pure returns (bytes memory) {
        bytes memory elems;
        for (uint256 i = 0; i < count; ++i) {
            elems = abi.encodePacked(elems, uint256(i), uint256(uint160(address(1))));
        }
        return abi.encodePacked(bytes4(keccak256("foo((uint256,address)[])")), uint256(0x20), count, elems);
    }

    function test_Suffix8() public {
        _benchEnforce(suffix8, "quantifier_suffix_8");
    }

    function test_Suffix64() public {
        _benchEnforce(suffix64, "quantifier_suffix_64");
    }

    function test_Suffix256() public {
        _benchEnforce(suffix256, "quantifier_suffix_256");
    }

    function test_DynElem8() public {
        _benchEnforce(dynElem8, "quantifier_dyn_elem_8");
    }

    function test_DynElem64() public {
        _benchEnforce(dynElem64, "quantifier_dyn_elem_64");
    }

    function test_DynElem256() public {
        _benchEnforce(dynElem256, "quantifier_dyn_elem_256");
    }

    function test_StaticArray() public {
        _benchEnforce(staticArray, "quantifier_static_array");
    }

    function test_DynTarget64() public {
        _benchEnforce(dynTarget64, "quantifier_dyn_target_64");
    }
}

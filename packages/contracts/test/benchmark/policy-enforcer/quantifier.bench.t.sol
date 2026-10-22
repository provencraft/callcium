// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg } from "src/Constraint.sol";
import { Path } from "src/Path.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

import { PolicyEnforcerBench } from "../PolicyEnforcer.bench.t.sol";

/// @notice Pins gas linearity of quantified evaluation across array sizes. Both element shapes are covered — a static
/// element addressed by stride alone, and a dynamic element the frame reaches through its own offset word.
contract QuantifierBench is PolicyEnforcerBench {
    string private constant EIGHT_FIELDS = "foo((uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256)[])";

    Fixture internal suffix8;
    Fixture internal suffix64;
    Fixture internal suffix256;

    Fixture internal dynElem8;
    Fixture internal dynElem64;
    Fixture internal dynElem256;

    Fixture internal staticArray;
    Fixture internal dynTarget64;

    Fixture internal twoTests8;
    Fixture internal twoTests64;
    Fixture internal twoTests256;

    Fixture internal fourTests8;
    Fixture internal fourTests64;
    Fixture internal fourTests256;

    Fixture internal eightTests8;
    Fixture internal eightTests64;
    Fixture internal eightTests256;

    Fixture internal deepPath8;
    Fixture internal deepPath64;

    function setUp() public override {
        super.setUp();

        // forgefmt: disable-next-item
        bytes memory suffixPolicy = PolicyBuilder.create("foo((uint256,address)[])")
            .add(arg(0, Path.ALL, 1).eq(address(1)))
            .build();
        suffix8 = _fixture(suffixPolicy, _quantifiedCallData(8));
        suffix64 = _fixture(suffixPolicy, _quantifiedCallData(64));
        suffix256 = _fixture(suffixPolicy, _quantifiedCallData(256));

        // Two tests per element: loops over one array join into one body.
        // forgefmt: disable-next-item
        bytes memory twoTestsPolicy = PolicyBuilder.create("foo((uint256,address)[])")
            .add(arg(0, Path.ALL, 1).eq(address(1)))
            .add(arg(0, Path.ALL, 0).lt(uint256(1000)))
            .build();
        twoTests8 = _fixture(twoTestsPolicy, _quantifiedCallData(8));
        twoTests64 = _fixture(twoTestsPolicy, _quantifiedCallData(64));
        twoTests256 = _fixture(twoTestsPolicy, _quantifiedCallData(256));

        bytes memory fourTestsPolicy = _fieldTestsPolicy(4);
        fourTests8 = _fixture(fourTestsPolicy, _eightFieldCallData(8));
        fourTests64 = _fixture(fourTestsPolicy, _eightFieldCallData(64));
        fourTests256 = _fixture(fourTestsPolicy, _eightFieldCallData(256));

        bytes memory eightTestsPolicy = _fieldTestsPolicy(8);
        eightTests8 = _fixture(eightTestsPolicy, _eightFieldCallData(8));
        eightTests64 = _fixture(eightTestsPolicy, _eightFieldCallData(64));
        eightTests256 = _fixture(eightTestsPolicy, _eightFieldCallData(256));

        // The deepest body path: the array path takes two steps, every further level is a dynamic tuple, one hop each.
        uint256 levels = PF.MAX_PATH_DEPTH - 2;
        (bytes memory deepPathPolicy, string memory deepPathSig) = _deepPathPolicy(levels);
        deepPath8 = _fixture(deepPathPolicy, _deepPathCallData(deepPathSig, levels, 8));
        deepPath64 = _fixture(deepPathPolicy, _deepPathCallData(deepPathSig, levels, 64));

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

    /// @dev ALL over an eight-field tuple array, one bound on each of the first `testCount` fields; the loops join into
    /// one body of `testCount` tests.
    function _fieldTestsPolicy(uint256 testCount) private pure returns (bytes memory) {
        PolicyDraft memory draft = PolicyBuilder.create(EIGHT_FIELDS);
        for (uint256 i = 0; i < testCount; ++i) {
            draft = draft.add(arg(0, Path.ALL, uint16(i)).lt(uint256(1000)));
        }
        return draft.build();
    }

    /// @dev An eight-field tuple array of `count` elements, every field of an element holding its index.
    function _eightFieldCallData(uint256 count) private pure returns (bytes memory callData) {
        callData = abi.encodePacked(bytes4(keccak256(bytes(EIGHT_FIELDS))), new bytes(32 * (2 + 8 * count)));
        _setWord(callData, 0, 0x20);
        _setWord(callData, 1, count);
        for (uint256 i = 0; i < count; ++i) {
            for (uint256 field = 0; field < 8; ++field) {
                _setWord(callData, 2 + 8 * i + field, i);
            }
        }
    }

    /// @dev ALL over an array of tuples nested `levels` deep, each level dynamic through an innermost bytes member,
    /// with one body test on the innermost uint256.
    function _deepPathPolicy(uint256 levels) private pure returns (bytes memory policy, string memory sig) {
        bytes memory types = bytes("bytes,uint256");
        for (uint256 i = 1; i < levels; ++i) {
            types = abi.encodePacked("(", types, "),uint256");
        }
        sig = string(abi.encodePacked("foo((", types, ")[])"));

        uint16[] memory steps = new uint16[](levels + 2);
        steps[1] = Path.ALL;
        steps[levels + 1] = 1;
        policy = PolicyBuilder.create(sig).add(arg(Path.encode(steps)).eq(uint256(42))).build();
    }

    /// @dev `count` elements of the `levels`-deep tuple: every level holds its successor one head behind it, the
    /// innermost uint256 is 42 and the innermost bytes is empty.
    function _deepPathCallData(
        string memory sig,
        uint256 levels,
        uint256 count
    )
        private
        pure
        returns (bytes memory callData)
    {
        uint256 elemWords = 2 * levels + 1;
        callData = abi.encodePacked(bytes4(keccak256(bytes(sig))), new bytes(32 * (2 + count + count * elemWords)));
        _setWord(callData, 0, 0x20);
        _setWord(callData, 1, count);
        for (uint256 i = 0; i < count; ++i) {
            _setWord(callData, 2 + i, 32 * (count + i * elemWords));
            uint256 elem = 2 + count + i * elemWords;
            for (uint256 level = 0; level < levels; ++level) {
                _setWord(callData, elem + 2 * level, 0x40);
                _setWord(callData, elem + 2 * level + 1, level + 1 == levels ? 42 : level);
            }
        }
    }

    /// @dev Writes `value` as the word at `wordIndex` after the selector of `callData`.
    function _setWord(bytes memory callData, uint256 wordIndex, uint256 value) private pure {
        assembly ("memory-safe") {
            mstore(add(add(callData, 36), mul(wordIndex, 32)), value)
        }
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

    function test_TwoTests8() public {
        _benchEnforce(twoTests8, "quantifier_two_tests_8");
    }

    function test_TwoTests64() public {
        _benchEnforce(twoTests64, "quantifier_two_tests_64");
    }

    function test_TwoTests256() public {
        _benchEnforce(twoTests256, "quantifier_two_tests_256");
    }

    function test_FourTests8() public {
        _benchEnforce(fourTests8, "quantifier_four_tests_8");
    }

    function test_FourTests64() public {
        _benchEnforce(fourTests64, "quantifier_four_tests_64");
    }

    function test_FourTests256() public {
        _benchEnforce(fourTests256, "quantifier_four_tests_256");
    }

    function test_EightTests8() public {
        _benchEnforce(eightTests8, "quantifier_eight_tests_8");
    }

    function test_EightTests64() public {
        _benchEnforce(eightTests64, "quantifier_eight_tests_64");
    }

    function test_EightTests256() public {
        _benchEnforce(eightTests256, "quantifier_eight_tests_256");
    }

    function test_DeepPath8() public {
        _benchEnforce(deepPath8, "quantifier_deep_path_8");
    }

    function test_DeepPath64() public {
        _benchEnforce(deepPath64, "quantifier_deep_path_64");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { arg, msgSender, msgValue } from "src/Constraint.sol";
import { Path } from "src/Path.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";
import { PolicyEnforcerHarness } from "test/harnesses/PolicyEnforcerHarness.sol";

/// @dev Generates enforcement conformance vectors for the TypeScript SDK.
///      Run: forge script script/EnforcementVectorGenerator.s.sol -v
// forgefmt: disable-next-item
contract EnforcementVectorGenerator is Script {
    using PolicyBuilder for PolicyDraft;

    string private constant OBJ = "vectors";

    PolicyEnforcerHarness private harness;

    /// @dev Running counter used to create unique sub-object keys.
    uint256 private vectorCount;

    /// @dev Stores the last serialized top-level JSON for finalization.
    string private lastJson;

    function run() external {
        harness = new PolicyEnforcerHarness();

        // Elementary scalar types: uint256, address, bool — EQ operator.
        _vectorEqUint256Pass();
        _vectorEqUint256Fail();
        _vectorEqAddressPass();
        _vectorEqAddressFail();
        _vectorEqBoolPass();
        _vectorEqBoolFail();

        // Comparison operators: GT, LT, GTE, LTE on uint256.
        _vectorGtPass();
        _vectorGtFail();
        _vectorLtPass();
        _vectorLtFail();
        _vectorGtePass();
        _vectorGteFail();
        _vectorLtePass();
        _vectorLteFail();

        // Signed comparison: int256 with a negative value.
        _vectorSignedGtPass();
        _vectorSignedGtFail();

        // BETWEEN: value in range, value out of range.
        _vectorBetweenPass();
        _vectorBetweenFail();

        // IN: value in set, value not in set.
        _vectorInPass();
        _vectorInFail();

        // BITMASK_ALL/ANY/NONE: various bit patterns.
        _vectorBitmaskAllPass();
        _vectorBitmaskAllFail();
        _vectorBitmaskAnyPass();
        _vectorBitmaskAnyFail();
        _vectorBitmaskNonePass();
        _vectorBitmaskNoneFail();

        // NOT flag: negated EQ.
        _vectorNotEqPass();
        _vectorNotEqFail();

        // LENGTH_EQ: on bytes argument.
        _vectorLengthEqPass();
        _vectorLengthEqFail();

        // Selectorless policy: no selector check.
        _vectorSelectorlessPass();
        _vectorSelectorlessFail();

        // Multi-group OR: passes via second group, fails all groups.
        _vectorMultiGroupOrPassSecond();
        _vectorMultiGroupOrFailAll();

        // Multi-rule AND: passes all rules, fails one rule.
        _vectorMultiRuleAndPass();
        _vectorMultiRuleAndFail();

        // Context rules: msg.sender check, msg.value check.
        _vectorContextSenderPass();
        _vectorContextSenderFail();
        _vectorContextValuePass();
        _vectorContextValueFail();

        // Quantifier ALL: array where all elements pass, one fails.
        _vectorQuantifierAllPass();
        _vectorQuantifierAllFail();

        // Quantifier ANY: array where one passes, none pass.
        _vectorQuantifierAnyPass();
        _vectorQuantifierAnyFail();

        // Quantifier ALL_OR_EMPTY: empty array (vacuous truth).
        _vectorQuantifierAllOrEmptyPass();

        // Nested paths: tuple field access, nested tuples.
        _vectorTupleFieldPass();
        _vectorTupleFieldFail();
        _vectorNestedTuplePass();
        _vectorNestedTupleFail();

        // Quantifier + suffix: quantifier followed by tuple field index.
        _vectorQuantifierSuffixPass();
        _vectorQuantifierSuffixFail();

        // Signed arithmetic: LT and BETWEEN on int256.
        _vectorSignedLtPass();
        _vectorSignedLtFail();
        _vectorSignedBetweenPass();
        _vectorSignedBetweenFail();

        // Static array: indexed access into fixed-size arrays.
        _vectorStaticArrayPass();
        _vectorStaticArrayFail();

        // Larger IN set: set with 8+ elements.
        _vectorInLargeSetPass();
        _vectorInLargeSetFail();

        // Finalize: write the top-level object to disk.
        vm.writeJson(lastJson, "test/vectors/enforcement.json");
        console2.log("Generated %d enforcement vectors", vectorCount);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          VECTOR GENERATORS
    /////////////////////////////////////////////////////////////////////////*/

    /*/////////////////////////////////////////////////////////////////////////
                          Elementary scalar types
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorEqUint256Pass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("eq-uint256-pass", "EQ uint256: value matches", policy, callData, true);
    }

    function _vectorEqUint256Fail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(99));
        _addVector("eq-uint256-fail", "EQ uint256: value does not match", policy, callData, false);
    }

    function _vectorEqAddressPass() private {
        bytes memory policy = PolicyBuilder.create("foo(address)").add(arg(0).eq(address(1))).build();
        bytes memory callData = abi.encodeWithSignature("foo(address)", address(1));
        _addVector("eq-address-pass", "EQ address: value matches", policy, callData, true);
    }

    function _vectorEqAddressFail() private {
        bytes memory policy = PolicyBuilder.create("foo(address)").add(arg(0).eq(address(1))).build();
        bytes memory callData = abi.encodeWithSignature("foo(address)", address(2));
        _addVector("eq-address-fail", "EQ address: value does not match", policy, callData, false);
    }

    function _vectorEqBoolPass() private {
        bytes memory policy = PolicyBuilder.create("foo(bool)").add(arg(0).eq(true)).build();
        bytes memory callData = abi.encodeWithSignature("foo(bool)", true);
        _addVector("eq-bool-pass", "EQ bool: value matches", policy, callData, true);
    }

    function _vectorEqBoolFail() private {
        bytes memory policy = PolicyBuilder.create("foo(bool)").add(arg(0).eq(true)).build();
        bytes memory callData = abi.encodeWithSignature("foo(bool)", false);
        _addVector("eq-bool-fail", "EQ bool: value does not match", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Comparison operators
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorGtPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).gt(uint256(40))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("gt-uint256-pass", "GT uint256: 42 > 40", policy, callData, true);
    }

    function _vectorGtFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).gt(uint256(42))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("gt-uint256-fail", "GT uint256: 42 is not > 42", policy, callData, false);
    }

    function _vectorLtPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).lt(uint256(50))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("lt-uint256-pass", "LT uint256: 42 < 50", policy, callData, true);
    }

    function _vectorLtFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).lt(uint256(42))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("lt-uint256-fail", "LT uint256: 42 is not < 42", policy, callData, false);
    }

    function _vectorGtePass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).gte(uint256(42))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("gte-uint256-pass", "GTE uint256: 42 >= 42", policy, callData, true);
    }

    function _vectorGteFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).gte(uint256(43))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("gte-uint256-fail", "GTE uint256: 42 is not >= 43", policy, callData, false);
    }

    function _vectorLtePass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).lte(uint256(42))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("lte-uint256-pass", "LTE uint256: 42 <= 42", policy, callData, true);
    }

    function _vectorLteFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).lte(uint256(41))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("lte-uint256-fail", "LTE uint256: 42 is not <= 41", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Signed comparison
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorSignedGtPass() private {
        bytes memory policy = PolicyBuilder.create("foo(int256)").add(arg(0).gt(int256(-1))).build();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(1));
        _addVector("signed-gt-pass", "Signed GT int256: 1 > -1", policy, callData, true);
    }

    function _vectorSignedGtFail() private {
        bytes memory policy = PolicyBuilder.create("foo(int256)").add(arg(0).gt(int256(0))).build();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(-1));
        _addVector("signed-gt-fail", "Signed GT int256: -1 is not > 0", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 BETWEEN
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorBetweenPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).between(uint256(10), uint256(100))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(50));
        _addVector("between-pass", "BETWEEN uint256: 50 in [10, 100]", policy, callData, true);
    }

    function _vectorBetweenFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).between(uint256(10), uint256(100))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(101));
        _addVector("between-fail", "BETWEEN uint256: 101 not in [10, 100]", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    IN
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorInPass() private {
        uint256[] memory set = new uint256[](3);
        set[0] = 10;
        set[1] = 20;
        set[2] = 30;
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).isIn(set)).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(20));
        _addVector("in-pass", "IN uint256: 20 in {10, 20, 30}", policy, callData, true);
    }

    function _vectorInFail() private {
        uint256[] memory set = new uint256[](3);
        set[0] = 10;
        set[1] = 20;
        set[2] = 30;
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).isIn(set)).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(15));
        _addVector("in-fail", "IN uint256: 15 not in {10, 20, 30}", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          BITMASK_ALL/ANY/NONE
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorBitmaskAllPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).bitmaskAll(uint256(0x03))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x07));
        _addVector("bitmask-all-pass", "BITMASK_ALL: 0x07 has all bits of 0x03", policy, callData, true);
    }

    function _vectorBitmaskAllFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).bitmaskAll(uint256(0x03))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x01));
        _addVector("bitmask-all-fail", "BITMASK_ALL: 0x01 does not have all bits of 0x03", policy, callData, false);
    }

    function _vectorBitmaskAnyPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).bitmaskAny(uint256(0x06))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x02));
        _addVector("bitmask-any-pass", "BITMASK_ANY: 0x02 has at least one bit of 0x06", policy, callData, true);
    }

    function _vectorBitmaskAnyFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).bitmaskAny(uint256(0x06))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x01));
        _addVector("bitmask-any-fail", "BITMASK_ANY: 0x01 has no bits of 0x06", policy, callData, false);
    }

    function _vectorBitmaskNonePass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).bitmaskNone(uint256(0x06))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x01));
        _addVector("bitmask-none-pass", "BITMASK_NONE: 0x01 has no bits of 0x06", policy, callData, true);
    }

    function _vectorBitmaskNoneFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).bitmaskNone(uint256(0x06))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(0x02));
        _addVector("bitmask-none-fail", "BITMASK_NONE: 0x02 has some bits of 0x06", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          NOT flag
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorNotEqPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).neq(uint256(42))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(99));
        _addVector("not-eq-pass", "NOT EQ uint256: 99 != 42", policy, callData, true);
    }

    function _vectorNotEqFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).neq(uint256(42))).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("not-eq-fail", "NOT EQ uint256: 42 == 42 negated fails", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          LENGTH_EQ
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorLengthEqPass() private {
        bytes memory policy = PolicyBuilder.create("foo(bytes)").add(arg(0).lengthEq(uint256(5))).build();
        bytes memory callData = abi.encodeWithSignature("foo(bytes)", bytes("hello"));
        _addVector("length-eq-pass", "LENGTH_EQ bytes: length 5 == 5", policy, callData, true);
    }

    function _vectorLengthEqFail() private {
        bytes memory policy = PolicyBuilder.create("foo(bytes)").add(arg(0).lengthEq(uint256(5))).build();
        bytes memory callData = abi.encodeWithSignature("foo(bytes)", bytes("hi"));
        _addVector("length-eq-fail", "LENGTH_EQ bytes: length 2 != 5", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Selectorless policy
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorSelectorlessPass() private {
        bytes memory policy = PolicyBuilder.createRaw("uint256").add(arg(0).eq(uint256(42))).build();
        bytes memory callData = abi.encode(uint256(42));
        _addVector("selectorless-pass", "Selectorless EQ uint256: value matches", policy, callData, true);
    }

    function _vectorSelectorlessFail() private {
        bytes memory policy = PolicyBuilder.createRaw("uint256").add(arg(0).eq(uint256(42))).build();
        bytes memory callData = abi.encode(uint256(99));
        _addVector("selectorless-fail", "Selectorless EQ uint256: value does not match", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Multi-group OR
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorMultiGroupOrPassSecond() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(1)))
            .or()
            .add(arg(0).eq(uint256(2)))
            .build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(2));
        _addVector("multi-group-or-pass-second", "Multi-group OR: passes via second group", policy, callData, true);
    }

    function _vectorMultiGroupOrFailAll() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(1)))
            .or()
            .add(arg(0).eq(uint256(2)))
            .build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(99));
        _addVector("multi-group-or-fail-all", "Multi-group OR: fails all groups", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Multi-rule AND
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorMultiRuleAndPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gt(uint256(0)).lte(uint256(100)))
            .build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(50));
        _addVector("multi-rule-and-pass", "Multi-rule AND: 50 > 0 and 50 <= 100", policy, callData, true);
    }

    function _vectorMultiRuleAndFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gt(uint256(0)).lte(uint256(100)))
            .build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(101));
        _addVector("multi-rule-and-fail", "Multi-rule AND: 101 > 0 but 101 is not <= 100", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Context rules
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorContextSenderPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgSender().eq(address(1)))
            .build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addContextVector(
            "context-sender-pass",
            "Context msg.sender: matches address(1)",
            policy,
            callData,
            address(1),
            0,
            true
        );
    }

    function _vectorContextSenderFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgSender().eq(address(1)))
            .build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addContextVector(
            "context-sender-fail",
            "Context msg.sender: does not match address(2)",
            policy,
            callData,
            address(2),
            0,
            false
        );
    }

    function _vectorContextValuePass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgValue().eq(uint256(1 ether)))
            .build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addContextVector(
            "context-value-pass",
            "Context msg.value: matches 1 ether",
            policy,
            callData,
            address(0),
            1 ether,
            true
        );
    }

    function _vectorContextValueFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgValue().eq(uint256(1 ether)))
            .build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addContextVector(
            "context-value-fail",
            "Context msg.value: does not match 2 ether",
            policy,
            callData,
            address(0),
            2 ether,
            false
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Quantifier ALL
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorQuantifierAllPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).gte(uint256(10)))
            .build();
        uint256[] memory arr = new uint256[](3);
        arr[0] = 10;
        arr[1] = 20;
        arr[2] = 30;
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        _addVector("quantifier-all-pass", "Quantifier ALL: all elements >= 10", policy, callData, true);
    }

    function _vectorQuantifierAllFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL).gte(uint256(10)))
            .build();
        uint256[] memory arr = new uint256[](3);
        arr[0] = 10;
        arr[1] = 5;
        arr[2] = 30;
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        _addVector("quantifier-all-fail", "Quantifier ALL: one element < 10", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Quantifier ANY
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorQuantifierAnyPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ANY).eq(uint256(42)))
            .build();
        uint256[] memory arr = new uint256[](3);
        arr[0] = 1;
        arr[1] = 42;
        arr[2] = 100;
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        _addVector("quantifier-any-pass", "Quantifier ANY: one element == 42", policy, callData, true);
    }

    function _vectorQuantifierAnyFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ANY).eq(uint256(42)))
            .build();
        uint256[] memory arr = new uint256[](3);
        arr[0] = 1;
        arr[1] = 2;
        arr[2] = 3;
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        _addVector("quantifier-any-fail", "Quantifier ANY: no element == 42", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Quantifier ALL_OR_EMPTY
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorQuantifierAllOrEmptyPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256[])")
            .add(arg(0, Path.ALL_OR_EMPTY).gte(uint256(10)))
            .build();
        uint256[] memory arr = new uint256[](0);
        bytes memory callData = abi.encodeWithSignature("foo(uint256[])", arr);
        _addVector("quantifier-all-or-empty-pass", "Quantifier ALL_OR_EMPTY: empty array is vacuous truth", policy, callData, true);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Nested paths
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorTupleFieldPass() private {
        bytes memory policy = PolicyBuilder.create("foo((uint256,address))").add(arg(0, 1).eq(address(1))).build();
        bytes memory callData = abi.encodeWithSignature("foo((uint256,address))", uint256(42), address(1));
        _addVector("tuple-field-pass", "Tuple field: address field matches", policy, callData, true);
    }

    function _vectorTupleFieldFail() private {
        bytes memory policy = PolicyBuilder.create("foo((uint256,address))").add(arg(0, 1).eq(address(1))).build();
        bytes memory callData = abi.encodeWithSignature("foo((uint256,address))", uint256(42), address(2));
        _addVector("tuple-field-fail", "Tuple field: address field does not match", policy, callData, false);
    }

    function _vectorNestedTuplePass() private {
        bytes memory policy =
            PolicyBuilder.create("foo(((uint256,address),uint256))").add(arg(0, 0, 1).eq(address(1))).build();
        bytes memory callData =
            abi.encodeWithSignature("foo(((uint256,address),uint256))", uint256(42), address(1), uint256(7));
        _addVector("nested-tuple-pass", "Nested tuple field: inner address matches", policy, callData, true);
    }

    function _vectorNestedTupleFail() private {
        bytes memory policy =
            PolicyBuilder.create("foo(((uint256,address),uint256))").add(arg(0, 0, 1).eq(address(1))).build();
        bytes memory callData =
            abi.encodeWithSignature("foo(((uint256,address),uint256))", uint256(42), address(2), uint256(7));
        _addVector("nested-tuple-fail", "Nested tuple field: inner address does not match", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Quantifier + suffix
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorQuantifierSuffixPass() private {
        bytes memory policy =
            PolicyBuilder.create("foo((uint256,address)[])").add(arg(0, Path.ALL, 1).eq(address(1))).build();
        bytes4 selector = bytes4(keccak256("foo((uint256,address)[])"));
        bytes memory callData = abi.encodePacked(
            selector,
            abi.encode(
                uint256(0x20), // offset to array
                uint256(2), // array length
                // tuple 0
                uint256(10),
                address(1),
                // tuple 1
                uint256(20),
                address(1)
            )
        );
        _addVector(
            "quantifier-suffix-pass",
            "Quantifier ALL + suffix: all elements field 1 match",
            policy,
            callData,
            true
        );
    }

    function _vectorQuantifierSuffixFail() private {
        bytes memory policy =
            PolicyBuilder.create("foo((uint256,address)[])").add(arg(0, Path.ALL, 1).eq(address(1))).build();
        bytes4 selector = bytes4(keccak256("foo((uint256,address)[])"));
        bytes memory callData = abi.encodePacked(
            selector,
            abi.encode(
                uint256(0x20), // offset to array
                uint256(2), // array length
                // tuple 0
                uint256(10),
                address(1),
                // tuple 1: field 1 is address(2), should fail.
                uint256(20),
                address(2)
            )
        );
        _addVector(
            "quantifier-suffix-fail",
            "Quantifier ALL + suffix: one element field 1 does not match",
            policy,
            callData,
            false
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Signed arithmetic
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorSignedLtPass() private {
        bytes memory policy = PolicyBuilder.create("foo(int256)").add(arg(0).lt(int256(0))).build();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(-5));
        _addVector("signed-lt-pass", "Signed LT int256: -5 < 0", policy, callData, true);
    }

    function _vectorSignedLtFail() private {
        bytes memory policy = PolicyBuilder.create("foo(int256)").add(arg(0).lt(int256(0))).build();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(5));
        _addVector("signed-lt-fail", "Signed LT int256: 5 is not < 0", policy, callData, false);
    }

    function _vectorSignedBetweenPass() private {
        bytes memory policy =
            PolicyBuilder.create("foo(int256)").add(arg(0).between(int256(-100), int256(100))).build();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(-10));
        _addVector("signed-between-pass", "Signed BETWEEN int256: -10 in [-100, 100]", policy, callData, true);
    }

    function _vectorSignedBetweenFail() private {
        bytes memory policy =
            PolicyBuilder.create("foo(int256)").add(arg(0).between(int256(-100), int256(100))).build();
        bytes memory callData = abi.encodeWithSignature("foo(int256)", int256(-200));
        _addVector("signed-between-fail", "Signed BETWEEN int256: -200 not in [-100, 100]", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Static array
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorStaticArrayPass() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256[4])").add(arg(0, 2).eq(uint256(42))).build();
        bytes memory callData =
            abi.encodeWithSignature("foo(uint256[4])", uint256(0), uint256(0), uint256(42), uint256(0));
        _addVector("static-array-pass", "Static array: element 2 matches", policy, callData, true);
    }

    function _vectorStaticArrayFail() private {
        bytes memory policy = PolicyBuilder.create("foo(uint256[4])").add(arg(0, 2).eq(uint256(42))).build();
        bytes memory callData =
            abi.encodeWithSignature("foo(uint256[4])", uint256(0), uint256(0), uint256(99), uint256(0));
        _addVector("static-array-fail", "Static array: element 2 does not match", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                          Larger IN set
    /////////////////////////////////////////////////////////////////////////*/

    function _vectorInLargeSetPass() private {
        uint256[] memory set = new uint256[](10);
        set[0] = 1;
        set[1] = 5;
        set[2] = 10;
        set[3] = 25;
        set[4] = 50;
        set[5] = 100;
        set[6] = 200;
        set[7] = 500;
        set[8] = 1000;
        set[9] = 5000;
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).isIn(set)).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(200));
        _addVector("in-large-set-pass", "IN uint256: 200 in 10-element set", policy, callData, true);
    }

    function _vectorInLargeSetFail() private {
        uint256[] memory set = new uint256[](10);
        set[0] = 1;
        set[1] = 5;
        set[2] = 10;
        set[3] = 25;
        set[4] = 50;
        set[5] = 100;
        set[6] = 200;
        set[7] = 500;
        set[8] = 1000;
        set[9] = 5000;
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).isIn(set)).build();
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));
        _addVector("in-large-set-fail", "IN uint256: 42 not in 10-element set", policy, callData, false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                               HELPERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Adds a vector without context. Verifies against on-chain enforcer.
    function _addVector(
        string memory id,
        string memory description,
        bytes memory policy,
        bytes memory callData,
        bool expected
    ) private {
        // Verify expected result matches on-chain enforcer.
        bool actual = harness.check(policy, callData);
        require(actual == expected, string.concat("Vector mismatch: ", id));

        string memory key = _nextKey();
        vm.serializeString(key, "id", id);
        vm.serializeString(key, "description", description);
        vm.serializeBytes(key, "policy", policy);
        vm.serializeBytes(key, "callData", callData);
        string memory vectorJson = vm.serializeBool(key, "expected", expected);
        lastJson = vm.serializeString(OBJ, id, vectorJson);

        vectorCount++;
    }

    /// @dev Adds a vector with context. Context rules cannot be verified on-chain from a script
    ///      because msg.sender/msg.value are script-specific.
    function _addContextVector(
        string memory id,
        string memory description,
        bytes memory policy,
        bytes memory callData,
        address sender,
        uint256 value,
        bool expected
    ) private {
        string memory key = _nextKey();
        string memory ctxKey = string.concat("ctx_", key);

        // Build context sub-object.
        vm.serializeString(ctxKey, "msgSender", vm.toString(sender));
        string memory ctxJson = vm.serializeString(ctxKey, "msgValue", vm.toString(bytes32(value)));

        // Build vector object.
        vm.serializeString(key, "id", id);
        vm.serializeString(key, "description", description);
        vm.serializeBytes(key, "policy", policy);
        vm.serializeBytes(key, "callData", callData);
        vm.serializeString(key, "context", ctxJson);
        string memory vectorJson = vm.serializeBool(key, "expected", expected);
        lastJson = vm.serializeString(OBJ, id, vectorJson);

        vectorCount++;
    }

    /// @dev Returns a unique key for each vector sub-object.
    function _nextKey() private view returns (string memory) {
        return string.concat("v_", vm.toString(vectorCount));
    }
}

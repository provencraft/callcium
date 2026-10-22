// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Policy } from "src/Policy.sol";

import { PolicyHarness } from "test/harnesses/PolicyHarness.sol";

abstract contract PolicyTest is Test {
    /// @dev Storage vector `calldata-eq-uint256`: `foo(uint256)` with arg(0) EQ 42.
    bytes internal constant SELECTOR_BLOB =
        hex"602fbebd380003020120010001000000310031010100000000000000000020010020000000000000000000000000000000000000000000000000000000000000002a";

    /// @dev Storage vector `selectorless`: the same rule, the selectorless flag set and the selector slot zero.
    bytes internal constant SELECTORLESS_BLOB =
        hex"61000000000003020120010001000000310031010100000000000000000020010020000000000000000000000000000000000000000000000000000000000000002a";

    PolicyHarness internal harness;

    function setUp() public virtual {
        harness = new PolicyHarness();
    }
}

contract PolicySelectorTest is PolicyTest {
    function test_ReturnsSelector() public view {
        assertEq(harness.selector(SELECTOR_BLOB), bytes4(keccak256("foo(uint256)")));
    }

    function test_RevertWhen_Selectorless() public {
        vm.expectRevert(Policy.OmittedSelector.selector);
        harness.selector(SELECTORLESS_BLOB);
    }

    function test_RevertWhen_HeaderTruncated() public {
        vm.expectRevert(Policy.MalformedHeader.selector);
        harness.selector(hex"602fbebd3800");
    }
}

/// @notice Error arguments, which the storage vectors leave unpinned. Each offset is a position in the blobs below.
contract PolicyValidateTest is PolicyTest {
    uint256 internal constant GROUP_OFFSET = 11;

    uint256 internal constant RULE_OFFSET = 17;

    uint256 internal constant BODY_RULE_OFFSET = 47;

    /// @dev Storage vector `rule-count-over`: ruleCount 2 with one rule filling groupSize.
    bytes internal constant RULE_COUNT_OVER =
        hex"602fbebd380003020120010002000000310031010100000000000000000020010020000000000000000000000000000000000000000000000000000000000000002a";

    /// @dev Storage vector `hint-target-tuple`: a hint target type code of a tuple.
    bytes internal constant HINT_TARGET_TUPLE =
        hex"602fbebd380003020120010001000000310031010100000000000000000090010020000000000000000000000000000000000000000000000000000000000000002a";

    /// @dev Storage vector `length-on-word`: LENGTH_EQ on a uint256 target.
    bytes internal constant LENGTH_ON_WORD =
        hex"602fbebd38000302012001000100000015001501010000000000000000002018000400000001";

    /// @dev Storage vector `loop-path-too-deep`: an array path of 1 step and a body path of 63.
    bytes internal constant LOOP_PATH_TOO_DEEP =
        hex"608b44cef1000702018100000520010001000000c700c702010100000100000000ffff00000000000000004001000100ad013f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200200200000000000000000000000000000000000000000000000000000000000000000";

    function test_RevertWhen_RulesOverrunGroup() public {
        vm.expectRevert(abi.encodeWithSelector(Policy.GroupSizeMismatch.selector, GROUP_OFFSET));
        harness.validate(RULE_COUNT_OVER);
    }

    function test_RevertWhen_HintTargetAddressesNoValue() public {
        vm.expectRevert(abi.encodeWithSelector(Policy.MalformedHint.selector, RULE_OFFSET));
        harness.validate(HINT_TARGET_TUPLE);
    }

    function test_RevertWhen_OperatorFamilyMismatchesTarget() public {
        vm.expectRevert(abi.encodeWithSelector(Policy.OperatorTargetMismatch.selector, RULE_OFFSET));
        harness.validate(LENGTH_ON_WORD);
    }

    function test_RevertWhen_BodyPathTooDeep() public {
        vm.expectRevert(abi.encodeWithSelector(Policy.PathTooDeep.selector, BODY_RULE_OFFSET, 64));
        harness.validate(LOOP_PATH_TOO_DEEP);
    }
}

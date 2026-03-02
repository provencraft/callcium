// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyTest } from "../Policy.t.sol";

import { arg } from "src/Constraint.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

contract SelectorTest is PolicyTest {
    function test_ReturnsProperlyAlignedSelector() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();

        bytes4 extractedSelector = Policy.selector(policy);
        bytes4 expectedSelector = bytes4(keccak256("foo(uint256)"));

        assertEq(extractedSelector, expectedSelector);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SELECTORLESS POLICIES
    /////////////////////////////////////////////////////////////////////////*/

    function test_IsSelectorless_FalseForNormalPolicy() public view {
        bytes memory blob = _validBlob();
        assertFalse(harness.isSelectorless(blob));
    }

    function test_IsSelectorless_TrueWhenFlagSet() public view {
        bytes memory blob = _validBlob();
        // Set FLAG_NO_SELECTOR bit and zero the selector slot.
        blob[PF.POLICY_HEADER_OFFSET] = bytes1(PF.POLICY_VERSION | PF.FLAG_NO_SELECTOR);
        _zeroSelector(blob);
        assertTrue(harness.isSelectorless(blob));
    }

    function test_RevertWhen_SelectorCalledOnSelectorlessPolicy() public {
        bytes memory blob = _validBlob();
        blob[PF.POLICY_HEADER_OFFSET] = bytes1(PF.POLICY_VERSION | PF.FLAG_NO_SELECTOR);
        _zeroSelector(blob);
        vm.expectRevert(Policy.OmittedSelector.selector);
        harness.selector(blob);
    }
}

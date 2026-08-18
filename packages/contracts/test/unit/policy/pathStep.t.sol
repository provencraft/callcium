// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyTest } from "../Policy.t.sol";

import { arg } from "src/Constraint.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

contract PathStepTest is PolicyTest {
    function test_ReturnsStepAtIndex() public pure {
        bytes memory policy =
            PolicyBuilder.create("foo((address,uint256))").add(arg(0, 1).eq(uint256(42))).buildUnsafe();
        uint256 ruleOffset = Policy.ruleAt(policy, Policy.groupAt(policy, 0), 0);

        assertEq(Policy.pathStep(policy, ruleOffset, 0), 0);
        assertEq(Policy.pathStep(policy, ruleOffset, 1), 1);
    }

    function test_RevertWhen_StepIndexBeyondDepth() public {
        bytes memory policy = _validBlob();
        uint256 ruleOffset = Policy.ruleAt(policy, Policy.groupAt(policy, 0), 0);

        vm.expectRevert(abi.encodeWithSelector(Policy.PathStepOutOfBounds.selector, ruleOffset, 1, 1));
        Policy.pathStep(policy, ruleOffset, 1);
    }
}

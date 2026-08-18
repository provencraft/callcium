// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyTest } from "../Policy.t.sol";

import { arg } from "src/Constraint.sol";
import { OpCode } from "src/OpCode.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

contract OpCodeTest is PolicyTest {
    function test_ReturnsOperatorCode() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256)").add(arg(0).gt(uint256(10))).buildUnsafe();
        uint256 ruleOffset = Policy.ruleAt(policy, Policy.groupAt(policy, 0), 0);

        assertEq(Policy.opCode(policy, ruleOffset), OpCode.GT);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { TypeRuleTest } from "../TypeRule.t.sol";
import { TypeRule } from "src/TypeRule.sol";

contract IsValidTest is TypeRuleTest {
    function testFuzz_EquivalentToPredicates(uint8 code) public pure {
        bool p = TypeRule.isElementary(code);
        bool c = TypeRule.isComposite(code);
        // Disjointness: elementary and composite types are mutually exclusive.
        assertFalse(p && c);
        // Equivalence: validity iff elementary or composite.
        assertEq(TypeRule.isValid(code), p || c);
    }
}

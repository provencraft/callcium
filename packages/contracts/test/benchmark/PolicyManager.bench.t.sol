// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyManagerTest } from "../unit/PolicyManager.t.sol";

/// @dev Base contract for PolicyRegistry benchmarks with pre-built fixtures.
// forgefmt: disable-next-item
abstract contract PolicyManagerBench is PolicyManagerTest {
    bytes internal policy;
    bytes32 internal policyHash;

    address internal target;
    address[] internal targets1;
    address[] internal targets10;

    // Descriptor-complexity fixtures.
    bytes internal policyTuple;
    bytes internal policyNestedTuple;
    bytes internal policyArray;
    bytes internal policyComplex;
    bytes internal policyLargeIn;

    function setUp() public virtual override {
        super.setUp();
        _buildPolicyFixtures();
        _buildTargetFixtures();
        _buildDescriptorComplexityFixtures();
        _buildLargeSetFixtures();
    }

    function _buildPolicyFixtures() internal {
        policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();
        (policyHash,) = harness.store(policy);
    }

    function _buildTargetFixtures() internal {
        target = address(1);

        targets1 = new address[](1);
        targets1[0] = address(1);

        targets10 = new address[](10);
        for (uint256 i; i < 10; ++i) {
            // forge-lint: disable-next-line(unsafe-typecast) loop bound is 10
            targets10[i] = address(uint160(i + 1));
        }
    }

    function _buildDescriptorComplexityFixtures() internal {
        policyTuple = PolicyBuilder.create("baz((address,uint256,bool))")
            .add(arg(0).eq(uint256(1)))
            .buildUnsafe();
        policyNestedTuple = PolicyBuilder.create("qux((address,(uint256,bool)))")
            .add(arg(0).eq(uint256(1)))
            .buildUnsafe();
        policyArray = PolicyBuilder.create("quux(uint256[])")
            .add(arg(0).eq(uint256(1)))
            .buildUnsafe();
        policyComplex = PolicyBuilder.create("corge(uint256,(address,uint256[],bool),(uint256,uint256))")
            .add(arg(0).eq(uint256(1)))
            .buildUnsafe();
    }

    function _buildLargeSetFixtures() internal {
        uint256[] memory largeSet = new uint256[](256);
        for (uint256 i; i < 256; ++i) {
            largeSet[i] = i + 1;
        }
        policyLargeIn = PolicyBuilder.create("grault(uint256)")
            .add(arg(0).isIn(largeSet))
            .buildUnsafe();
    }
}

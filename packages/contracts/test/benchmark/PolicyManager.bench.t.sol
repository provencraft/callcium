// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyManagerTest } from "test/unit/PolicyManager.t.sol";

abstract contract PolicyManagerBench is PolicyManagerTest {
    address internal constant UNBOUND_TARGET = address(0xffff);

    bytes4 internal constant UNBOUND_SELECTOR = bytes4(0x12345678);

    bytes internal policy;
    bytes32 internal policyHash;

    bytes internal unstoredPolicy;

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

    /// @dev Stores `policy` and leaves `unstoredPolicy` unstored, so a benchmark that stores it pays for validation and
    /// the SSTORE2 deploy instead of hitting the hash-keyed short circuit.
    function _buildPolicyFixtures() internal {
        // forgefmt: disable-next-item
        policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();
        (policyHash,) = harness.store(policy);

        // forgefmt: disable-next-item
        unstoredPolicy = PolicyBuilder.create("bar(uint256)")
            .add(arg(0).eq(uint256(1337)))
            .buildUnsafe();
    }

    /// @dev Builds the target lists of one and ten addresses.
    function _buildTargetFixtures() internal {
        target = address(1);

        targets1 = new address[](1);
        targets1[0] = address(1);

        targets10 = new address[](10);
        for (uint256 i = 0; i < 10; ++i) {
            targets10[i] = address(uint160(i + 1));
        }
    }

    /// @dev The series varies descriptor complexity, so each rule targets an elementary member or uses a length
    /// operator on a dynamic array; value operators cannot read a composite.
    function _buildDescriptorComplexityFixtures() internal {
        // forgefmt: disable-next-item
        policyTuple = PolicyBuilder.create("baz((address,uint256,bool))")
            .add(arg(0, 1).eq(uint256(1)))
            .buildUnsafe();

        // forgefmt: disable-next-item
        policyNestedTuple = PolicyBuilder.create("qux((address,(uint256,bool)))")
            .add(arg(0, 1, 0).eq(uint256(1)))
            .buildUnsafe();

        // forgefmt: disable-next-item
        policyArray = PolicyBuilder.create("quux(uint256[])")
            .add(arg(0).lengthEq(1))
            .buildUnsafe();

        // forgefmt: disable-next-item
        policyComplex = PolicyBuilder.create("corge(uint256,(address,uint256[],bool),(uint256,uint256))")
            .add(arg(0).eq(uint256(1)))
            .buildUnsafe();
    }

    /// @dev Builds a policy with an `IN` set of 256 members.
    function _buildLargeSetFixtures() internal {
        uint256[] memory largeSet = new uint256[](256);
        for (uint256 i = 0; i < 256; ++i) {
            largeSet[i] = i + 1;
        }

        // forgefmt: disable-next-item
        policyLargeIn = PolicyBuilder.create("grault(uint256)")
            .add(arg(0).isIn(largeSet))
            .buildUnsafe();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { arg, msgSender } from "src/Constraint.sol";
import { Path } from "src/Path.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

/// @dev Tests for the code examples displayed on the docs homepage (docs/components/home/hero.tsx).
/// Each test corresponds to a tab in the hero code showcase. Keep in sync.
contract UsageExamplesTest is Test {
    address constant OPERATOR = address(1);

    function test_FlatArguments() public pure {
        address[] memory trustedSpenders = new address[](2);
        trustedSpenders[0] = address(0xA);
        trustedSpenders[1] = address(0xB);

        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder
            .create("approve(address,uint256)")
            .add(arg(0).isIn(trustedSpenders))
            .add(arg(1).lte(uint256(1_000_000e6)))
            .build();

        assertGt(policy.length, 0);
    }

    function test_NestedStructs() public pure {
        address[] memory sanctioned = new address[](2);
        sanctioned[0] = address(0x01);
        sanctioned[1] = address(0x02);

        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder
            .create("swap((address,address,uint256))")
            .add(arg(0, 0).notIn(sanctioned))
            .add(arg(0, 1).notIn(sanctioned))
            .add(arg(0, 2).gt(uint256(0)))
            .build();

        assertGt(policy.length, 0);
    }

    function test_ArrayGuards() public pure {
        address[] memory sanctioned = new address[](2);
        sanctioned[0] = address(0x01);
        sanctioned[1] = address(0x02);

        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder
            .create("multiSend((address,uint256)[])")
            .add(arg(0).lengthBetween(1, 50))
            .add(arg(0, Path.ALL, 0).notIn(sanctioned))
            .add(arg(0, Path.ALL, 1).lte(uint256(1e18)))
            .build();

        assertGt(policy.length, 0);
    }

    function test_ContextConstraints() public pure {
        address[] memory operators = new address[](2);
        operators[0] = address(0xA);
        operators[1] = address(0xB);

        address[] memory sanctioned = new address[](2);
        sanctioned[0] = address(0x01);
        sanctioned[1] = address(0x02);

        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder
            .create("transfer(address,uint256)")
            .add(msgSender().isIn(operators))
            .add(arg(0).notIn(sanctioned))
            .add(arg(1).lte(uint256(100e18)))
            .build();

        assertGt(policy.length, 0);
    }

    function test_OrGroups() public pure {
        address[] memory allowedAssets = new address[](2);
        allowedAssets[0] = address(0xA);
        allowedAssets[1] = address(0xB);

        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder
            .create("supply(address,uint256)")
            .add(msgSender().eq(OPERATOR))
            .or()
            .add(arg(0).isIn(allowedAssets))
            .build();

        assertGt(policy.length, 0);
    }
}

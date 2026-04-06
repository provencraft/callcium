// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg, blockTimestamp, msgSender, msgValue } from "src/Constraint.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";

/// @notice Harness contract exposing full PolicyBuilder pipelines for benchmarking.
contract PolicyBuilderHarness {
    /*/////////////////////////////////////////////////////////////////////////
                              SIGNATURE COMPLEXITY
    /////////////////////////////////////////////////////////////////////////*/

    function simpleElementary(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function multipleElementaryTypes(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("bar(address,uint256,bool,bytes32)")
            .add(arg(0).eq(address(1)))
            .add(arg(1).eq(uint256(42)))
            .add(arg(2).eq(true))
            .add(arg(3).eq(bytes32(uint256(100))));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function singleTuple(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("baz((address,uint256))")
            .add(arg(0, 1).eq(uint256(42)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function nestedTuple(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("qux(((address,uint256),bytes))")
            .add(arg(0, 0, 1).eq(uint256(42)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function arrayTypes(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("quux(uint256[],address[5])")
            .add(arg(0, 0).eq(uint256(42)))
            .add(arg(1, 2).eq(address(1)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function complexMixed(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("corge((address,uint256)[],bytes32,(bool,address))")
            .add(arg(0, 0, 0).eq(address(1)))
            .add(arg(1).eq(bytes32(uint256(42))))
            .add(arg(2, 1).eq(address(2)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    /*/////////////////////////////////////////////////////////////////////////
                              CONSTRAINT COUNT
    /////////////////////////////////////////////////////////////////////////*/

    function singleConstraint(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function fourConstraints(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256,address,bool,bytes32)")
            .add(arg(0).eq(uint256(42)))
            .add(arg(1).eq(address(1)))
            .add(arg(2).eq(true))
            .add(arg(3).eq(bytes32(uint256(100))));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function eightConstraints(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256,address,bool,bytes32,uint256,address,bool,bytes32)")
            .add(arg(0).eq(uint256(1)))
            .add(arg(1).eq(address(1)))
            .add(arg(2).eq(true))
            .add(arg(3).eq(bytes32(uint256(1))))
            .add(arg(4).eq(uint256(2)))
            .add(arg(5).eq(address(2)))
            .add(arg(6).eq(false))
            .add(arg(7).eq(bytes32(uint256(2))));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function sixteenConstraints(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create(
            "foo(uint256,address,bool,bytes32,uint256,address,bool,bytes32,uint256,address,bool,bytes32,uint256,address,bool,bytes32)"
        )
            .add(arg(0).eq(uint256(1)))
            .add(arg(1).eq(address(1)))
            .add(arg(2).eq(true))
            .add(arg(3).eq(bytes32(uint256(1))))
            .add(arg(4).eq(uint256(2)))
            .add(arg(5).eq(address(2)))
            .add(arg(6).eq(false))
            .add(arg(7).eq(bytes32(uint256(2))))
            .add(arg(8).eq(uint256(3)))
            .add(arg(9).eq(address(3)))
            .add(arg(10).eq(true))
            .add(arg(11).eq(bytes32(uint256(3))))
            .add(arg(12).eq(uint256(4)))
            .add(arg(13).eq(address(4)))
            .add(arg(14).eq(false))
            .add(arg(15).eq(bytes32(uint256(4))));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    /*/////////////////////////////////////////////////////////////////////////
                              GROUP COUNT
    /////////////////////////////////////////////////////////////////////////*/

    function twoGroups(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(1)))
            .or()
            .add(arg(0).eq(uint256(2)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function fourGroups(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(1)))
            .or()
            .add(arg(0).eq(uint256(2)))
            .or()
            .add(arg(0).eq(uint256(3)))
            .or()
            .add(arg(0).eq(uint256(4)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function eightGroups(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(1)))
            .or()
            .add(arg(0).eq(uint256(2)))
            .or()
            .add(arg(0).eq(uint256(3)))
            .or()
            .add(arg(0).eq(uint256(4)))
            .or()
            .add(arg(0).eq(uint256(5)))
            .or()
            .add(arg(0).eq(uint256(6)))
            .or()
            .add(arg(0).eq(uint256(7)))
            .or()
            .add(arg(0).eq(uint256(8)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    /*/////////////////////////////////////////////////////////////////////////
                              PATH DEPTH
    /////////////////////////////////////////////////////////////////////////*/

    function pathDepth1(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function pathDepth2(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo((address,uint256))")
            .add(arg(0, 1).eq(uint256(42)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function pathDepth3(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(((address,uint256),bool))")
            .add(arg(0, 0, 1).eq(uint256(42)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function pathDepth4(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo((((address,uint256),bool),bytes32))")
            .add(arg(0, 0, 0, 1).eq(uint256(42)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    /*/////////////////////////////////////////////////////////////////////////
                          OPERATOR COMPLEXITY
    /////////////////////////////////////////////////////////////////////////*/

    function singleOperator(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function chainedOperators(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gt(uint256(10)).lt(uint256(100)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function setMembership(bool safe) external pure returns (bytes memory policy) {
        address[] memory allowlist = new address[](4);
        allowlist[0] = address(1);
        allowlist[1] = address(2);
        allowlist[2] = address(3);
        allowlist[3] = address(4);
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(address)")
            .add(arg(0).isIn(allowlist));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SCOPE
    /////////////////////////////////////////////////////////////////////////*/

    function calldataOnly(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256,address)")
            .add(arg(0).eq(uint256(42)))
            .add(arg(1).eq(address(1)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function contextOnly(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo()")
            .add(msgSender().eq(address(1)))
            .add(msgValue().eq(uint256(0)))
            .add(blockTimestamp().gt(uint256(1000)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }

    function mixedScope(bool safe) external pure returns (bytes memory policy) {
        // forgefmt: disable-next-item
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256,address)")
            .add(arg(0).eq(uint256(42)))
            .add(msgSender().eq(address(1)))
            .add(arg(1).eq(address(2)))
            .add(msgValue().eq(uint256(0)));

        policy = safe ? draft.build() : draft.buildUnsafe();
    }
}

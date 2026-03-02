// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyCoderTest } from "../PolicyCoder.t.sol";

import { Constraint, arg, msgSender } from "src/Constraint.sol";
import { OpCode } from "src/OpCode.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";
import { PolicyCoder, PolicyData } from "src/PolicyCoder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

// forgefmt: disable-next-item
contract DecodeTest is PolicyCoderTest {
    function test_DecodesSelector() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.selector, bytes4(keccak256("foo(uint256)")));
    }

    function test_DecodesDescriptor() public pure {
        PolicyDraft memory draft = PolicyBuilder.create("bar(address,uint256)");
        draft = draft.add(arg(0).eq(address(1)));
        bytes memory policy = draft.buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.descriptor.length, draft.data.descriptor.length);
        assertEq(keccak256(data.descriptor), keccak256(draft.data.descriptor));
    }

    function test_DecodesOneGroupOneConstraint() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.groups.length, 1);
        assertEq(data.groups[0].length, 1);
        assertEq(data.groups[0][0].scope, PF.SCOPE_CALLDATA);
        assertEq(data.groups[0][0].operators.length, 1);
    }

    function test_DecodesMultipleOperatorsPerConstraint() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gt(uint256(10)).lt(uint256(100)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.groups.length, 1);
        // Note: Multiple operators on same path get grouped into one constraint
        assertEq(data.groups[0].length, 1);
        assertEq(data.groups[0][0].operators.length, 2);
    }

    function test_DecodesMultipleGroups() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(1)))
            .or()
            .add(arg(0).eq(uint256(2)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.groups.length, 2);
    }

    function test_DecodesContextScope() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgSender().eq(address(1)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.groups.length, 1);
        assertEq(data.groups[0].length, 1);
        assertEq(data.groups[0][0].scope, PF.SCOPE_CONTEXT);
    }

    function test_DecodesMixedScopes() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgSender().eq(address(1)))
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.groups.length, 1);
        assertEq(data.groups[0].length, 2);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SELECTORLESS DECODING
    /////////////////////////////////////////////////////////////////////////*/

    function test_DecodesSelectorlessFlag() public pure {
        PolicyData memory original;
        original.isSelectorless = true;
        original.selector = bytes4(0);
        original.descriptor = hex"";
        original.groups = _makeSelectorlessGroup();

        bytes memory blob = PolicyCoder.encode(original);
        PolicyData memory decoded = PolicyCoder.decode(blob);

        assertTrue(decoded.isSelectorless, "isSelectorless");
        assertEq(decoded.selector, bytes4(0), "selector is zero");
    }

    function test_DecodesNormalPolicyNotSelectorless() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertFalse(data.isSelectorless);
    }

    /// @dev Creates a single-constraint group for selectorless policy tests.
    function _makeSelectorlessGroup() internal pure returns (Constraint[][] memory groups) {
        groups = new Constraint[][](1);
        groups[0] = new Constraint[](1);
        bytes[] memory operators = new bytes[](1);
        operators[0] = abi.encodePacked(OpCode.EQ, bytes32(uint256(42)));
        groups[0][0] = Constraint({ scope: PF.SCOPE_CALLDATA, path: hex"0000", operators: operators });
    }
}

// forgefmt: disable-next-item
contract RoundTripTest is PolicyCoderTest {
    function test_SingleConstraint_RoundTrip() public pure {
        bytes memory policy1 = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(42)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy1);
        bytes memory policy2 = PolicyCoder.encode(data);

        assertEq(keccak256(policy1), keccak256(policy2));
    }

    function test_MultipleOperators_RoundTrip() public pure {
        bytes memory policy1 = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).gt(uint256(10)).lt(uint256(100)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy1);
        bytes memory policy2 = PolicyCoder.encode(data);

        assertEq(keccak256(policy1), keccak256(policy2));
    }

    function test_MultipleConstraints_RoundTrip() public pure {
        bytes memory policy1 = PolicyBuilder.create("foo(uint256,address)")
            .add(arg(0).eq(uint256(42)))
            .add(arg(1).eq(address(1)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy1);
        bytes memory policy2 = PolicyCoder.encode(data);

        assertEq(keccak256(policy1), keccak256(policy2));
    }

    function test_MultipleGroups_RoundTrip() public pure {
        bytes memory policy1 = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).eq(uint256(1)))
            .or()
            .add(arg(0).eq(uint256(2)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy1);
        bytes memory policy2 = PolicyCoder.encode(data);

        assertEq(keccak256(policy1), keccak256(policy2));
    }

    function test_ContextScope_RoundTrip() public pure {
        bytes memory policy1 = PolicyBuilder.create("foo(uint256)")
            .add(msgSender().eq(address(1)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy1);
        bytes memory policy2 = PolicyCoder.encode(data);

        assertEq(keccak256(policy1), keccak256(policy2));
    }

    function test_MixedScopes_RoundTrip() public pure {
        bytes memory policy1 = PolicyBuilder.create("foo(uint256)")
            .add(msgSender().eq(address(1)))
            .add(arg(0).gt(uint256(0)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy1);
        bytes memory policy2 = PolicyCoder.encode(data);

        assertEq(keccak256(policy1), keccak256(policy2));
    }

    function test_InOperator_RoundTrip() public pure {
        uint256[] memory values = new uint256[](3);
        values[0] = 1;
        values[1] = 2;
        values[2] = 3;
        bytes memory policy1 = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).isIn(values))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy1);
        bytes memory policy2 = PolicyCoder.encode(data);

        assertEq(keccak256(policy1), keccak256(policy2));
    }

    function test_BetweenOperator_RoundTrip() public pure {
        bytes memory policy1 = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).between(uint256(10), uint256(100)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy1);
        bytes memory policy2 = PolicyCoder.encode(data);

        assertEq(keccak256(policy1), keccak256(policy2));
    }

    function test_Selectorless_RoundTrip() public pure {
        PolicyData memory original;
        original.isSelectorless = true;
        original.selector = bytes4(0);
        original.descriptor = hex"";
        original.groups = _makeSelectorlessGroupRt();

        bytes memory policy1 = PolicyCoder.encode(original);
        PolicyData memory decoded = PolicyCoder.decode(policy1);
        bytes memory policy2 = PolicyCoder.encode(decoded);

        assertEq(keccak256(policy1), keccak256(policy2), "roundtrip blob identity");
        assertTrue(decoded.isSelectorless, "roundtrip preserves flag");
    }

    /// @dev Creates a single-constraint group for selectorless roundtrip tests.
    function _makeSelectorlessGroupRt() internal pure returns (Constraint[][] memory groups) {
        groups = new Constraint[][](1);
        groups[0] = new Constraint[](1);
        bytes[] memory operators = new bytes[](1);
        operators[0] = abi.encodePacked(OpCode.EQ, bytes32(uint256(42)));
        groups[0][0] = Constraint({ scope: PF.SCOPE_CALLDATA, path: hex"0000", operators: operators });
    }
}

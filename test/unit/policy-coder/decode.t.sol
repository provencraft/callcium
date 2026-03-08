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
        // Multiple operators on the same path are grouped into one constraint.
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
        original.descriptor = hex"01011f";
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

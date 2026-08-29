// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyCoderTest } from "../PolicyCoder.t.sol";

import { Constraint, arg, msgSender } from "src/Constraint.sol";
import { OpCode } from "src/OpCode.sol";
import { Path } from "src/Path.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";
import { PolicyCoder, PolicyData } from "src/PolicyCoder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

// forgefmt: disable-next-item
contract DecodeTest is PolicyCoderTest {
    /// @dev Creates a single-constraint group for selectorless policy tests.
    function _makeSelectorlessGroup() internal pure returns (Constraint[][] memory groups) {
        groups = new Constraint[][](1);
        groups[0] = new Constraint[](1);
        bytes[] memory operators = new bytes[](1);
        operators[0] = abi.encodePacked(OpCode.EQ, bytes32(uint256(42)));
        groups[0][0] = Constraint({ scope: PF.SCOPE_CALLDATA, path: hex"0000", operators: operators, hint: "" });
    }

    function _calldataRule(bytes memory path, bytes memory hint) internal pure returns (bytes memory) {
        uint16 dataLength = uint16(bytes32(0).length);
        return abi.encodePacked(
            uint16(PF.RULE_FIXED_OVERHEAD + path.length + hint.length + dataLength),
            PF.SCOPE_CALLDATA,
            uint8(path.length / PF.PATH_STEP_SIZE),
            path,
            hint,
            OpCode.EQ,
            dataLength,
            bytes32(0)
        );
    }

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
        original.descriptor = hex"020120";
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

    function test_DecodesHintBlock() public pure {
        bytes memory policy = PolicyBuilder.create("foo(address,uint256)")
            .add(arg(1).eq(uint256(42)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.groups[0][0].hint, hex"00_00000020_0000_20");
    }

    function test_DecodesQuantifiedHintBlock() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256[3])")
            .add(arg(0, Path.ALL).eq(uint256(42)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.groups[0][0].hint, hex"40_00000000_0003_0001_00_00000000_0000_20");
    }

    function test_ContextConstraintCarriesNoHint() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(msgSender().eq(address(1)))
            .buildUnsafe();

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.groups[0][0].hint.length, 0);
    }

    function test_DivergentHintsSplitConstraints() public pure {
        bytes memory policy = PolicyBuilder.create("foo(uint256,uint256)")
            .add(arg(0).eq(uint256(1)).eq(uint256(2)))
            .buildUnsafe();
        // Rewrite the second rule's hint so the two rules no longer agree on the target.
        uint256 firstRuleOffset = _firstRuleOffset(PolicyBuilder.create("foo(uint256,uint256)").data.descriptor.length);
        uint256 secondRuleOffset = firstRuleOffset + _readU16(policy, firstRuleOffset);
        (uint256 hintOffset,) = Policy.hintView(policy, secondRuleOffset);
        _writeU32(policy, hintOffset + PF.HINT_HEADER_SIZE, 32);

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.groups[0].length, 2, "divergent hints stay separate");
    }

    function test_EqualPathHintConcatenationsStaySeparate() public pure {
        bytes memory pathA = hex"0000";
        bytes memory hintA = hex"01_0000000000000000_00000000000020";
        bytes memory pathB = hex"00000100000000000000";
        bytes memory hintB = hex"0000000000000020";
        assertEq(bytes.concat(pathA, hintA), bytes.concat(pathB, hintB), "concatenations collide");

        bytes memory ruleA = _calldataRule(pathA, hintA);
        bytes memory ruleB = _calldataRule(pathB, hintB);
        bytes memory desc = PolicyBuilder.create("foo(uint256)").data.descriptor;
        bytes memory policy = abi.encodePacked(
            PF.POLICY_VERSION,
            bytes4(keccak256("foo(uint256)")),
            uint16(desc.length),
            desc,
            uint8(1),
            uint16(2),
            uint32(ruleA.length + ruleB.length),
            ruleA,
            ruleB
        );

        PolicyData memory data = PolicyCoder.decode(policy);

        assertEq(data.groups[0].length, 2, "constraint count");
        assertEq(data.groups[0][0].path, pathA, "first path");
        assertEq(data.groups[0][1].path, pathB, "second path");
    }
}

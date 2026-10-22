// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { OpCode } from "src/OpCode.sol";
import { Path } from "src/Path.sol";
import { Policy } from "src/Policy.sol";
import { BodyRule, PolicyCoder, PolicyData, Rule } from "src/PolicyCoder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";
import { TypeCode } from "src/TypeCode.sol";
import { LibBytes } from "src/vendor/solady/utils/LibBytes.sol";

contract PolicyCoderEncodeTest is Test {
    /// @dev Returns a policy over `foo(uint256)` of one group holding `rules`.
    function _policy(Rule[] memory rules) private pure returns (PolicyData memory data) {
        data.selector = bytes4(keccak256("foo(uint256)"));
        data.descriptor = DescriptorBuilder.fromTypes("uint256");
        data.groups = new Rule[][](1);
        data.groups[0] = rules;
    }

    /// @dev Returns a policy over `foo(uint256)` of one group holding `rule`.
    function _policy(Rule memory rule) private pure returns (PolicyData memory) {
        Rule[] memory rules = new Rule[](1);
        rules[0] = rule;
        return _policy(rules);
    }

    /// @dev Returns a test of `scope` at `path` applying `operator`.
    function _test(uint8 scope, bytes memory path, bytes memory operator) private pure returns (Rule memory rule) {
        rule.scope = scope;
        rule.path = path;
        rule.operator = operator;
    }

    /// @dev Returns an equality on argument 0 against `value`.
    function _eq(uint256 value) private pure returns (Rule memory) {
        return _test(PF.SCOPE_CALLDATA, Path.encode(0), abi.encodePacked(OpCode.EQ, value));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  FIELD SHAPES
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_EmptyPolicy() public {
        PolicyData memory data = _policy(_eq(1));
        data.groups = new Rule[][](0);

        vm.expectRevert(PolicyCoder.EmptyPolicy.selector);
        PolicyCoder.encode(data);
    }

    function test_RevertWhen_EmptyGroup() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.EmptyGroup.selector, 0));
        PolicyCoder.encode(_policy(new Rule[](0)));
    }

    function test_RevertWhen_EmptyPath() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.EmptyPath.selector, 0, 0));
        PolicyCoder.encode(_policy(_test(PF.SCOPE_CALLDATA, "", abi.encodePacked(OpCode.EQ, uint256(1)))));
    }

    function test_RevertWhen_MalformedPath() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.MalformedPath.selector, 0, 0));
        PolicyCoder.encode(_policy(_test(PF.SCOPE_CALLDATA, hex"000000", abi.encodePacked(OpCode.EQ, uint256(1)))));
    }

    function test_RevertWhen_InvalidContextPath() public {
        Rule memory rule =
            _test(PF.SCOPE_CONTEXT, Path.encode(PF.CTX_MSG_VALUE, 0), abi.encodePacked(OpCode.EQ, uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.InvalidContextPath.selector, 0, 0));
        PolicyCoder.encode(_policy(rule));
    }

    function test_RevertWhen_PathTooDeepAcrossTheLoop() public {
        PolicyData memory data = _policy(_eq(1));
        data.descriptor = DescriptorBuilder.fromTypes("uint256[]");
        BodyRule[] memory body = new BodyRule[](1);
        body[0] = BodyRule(
            PF.SCOPE_CALLDATA,
            new bytes(PF.MAX_PATH_DEPTH * PF.PATH_STEP_SIZE),
            "",
            abi.encodePacked(OpCode.EQ, uint256(1))
        );
        data.groups[0][0] = Rule(PF.SCOPE_LOOP, PF.QUANTIFIER_ALL, Path.encode(0), "", "", body);

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.PathTooDeep.selector, 0, 0, PF.MAX_PATH_DEPTH + 1));
        PolicyCoder.encode(data);
    }

    function test_RevertWhen_UnknownScope() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.UnknownScope.selector, PF.SCOPE_LOOP + 1));
        PolicyCoder.encode(_policy(_test(PF.SCOPE_LOOP + 1, Path.encode(0), abi.encodePacked(OpCode.EQ, uint256(1)))));
    }

    function test_RevertWhen_UnknownQuantifier() public {
        Rule memory rule = Rule(PF.SCOPE_LOOP, PF.QUANTIFIER_ANY + 1, Path.encode(0), "", "", new BodyRule[](0));

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.UnknownQuantifier.selector, PF.QUANTIFIER_ANY + 1));
        PolicyCoder.encode(_policy(rule));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_InvalidOperatorBytes() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.InvalidOperatorBytes.selector, 0, 0));
        PolicyCoder.encode(_policy(_test(PF.SCOPE_CALLDATA, Path.encode(0), abi.encodePacked(OpCode.EQ))));
    }

    function test_RevertWhen_ContextOperandOverflowsItsField() public {
        uint8 contextEq = OpCode.EQ | (OpCode.SOURCE_CONTEXT << OpCode.SOURCE_SHIFT);

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.InvalidOperatorBytes.selector, 0, 0));
        PolicyCoder.encode(
            _policy(
                _test(PF.SCOPE_CALLDATA, Path.encode(0), abi.encodePacked(contextEq, uint256(type(uint16).max) + 1))
            )
        );
    }

    function test_RevertWhen_ComparisonDoesNotApplyToTheTarget() public {
        Rule memory rule = _test(PF.SCOPE_CALLDATA, Path.encode(0), abi.encodePacked(OpCode.LENGTH_EQ, uint256(1)));

        vm.expectRevert(
            abi.encodeWithSelector(PolicyCoder.OperatorTargetMismatch.selector, OpCode.LENGTH_EQ, TypeCode.UINT256)
        );
        PolicyCoder.encode(_policy(rule));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 FIELD WIDTHS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_DescLengthOverflow() public {
        PolicyData memory data = _policy(_eq(1));
        data.descriptor = new bytes(uint256(type(uint16).max) + 1);

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.DescLengthOverflow.selector, uint256(type(uint16).max) + 1));
        PolicyCoder.encode(data);
    }

    function test_RevertWhen_GroupCountOverflow() public {
        PolicyData memory data = _policy(_eq(0));
        uint256 groupCount = uint256(type(uint8).max) + 1;
        data.groups = new Rule[][](groupCount);
        for (uint256 i = 0; i < groupCount; ++i) {
            data.groups[i] = new Rule[](1);
            data.groups[i][0] = _eq(i);
        }

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.GroupCountOverflow.selector, groupCount));
        PolicyCoder.encode(data);
    }

    function test_RevertWhen_RuleSizeOverflow() public {
        // A set whose data alone overflows the rule's size field.
        uint256 memberCount = uint256(type(uint16).max) / 32 + 1;
        bytes memory operator = new bytes(1 + memberCount * 32);
        operator[0] = bytes1(OpCode.IN);
        for (uint256 i = 0; i < memberCount; ++i) {
            assembly ("memory-safe") {
                mstore(add(add(operator, 33), mul(i, 32)), i)
            }
        }

        vm.expectPartialRevert(PolicyCoder.RuleSizeOverflow.selector);
        PolicyCoder.encode(_policy(_test(PF.SCOPE_CALLDATA, Path.encode(0), operator)));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  SELECTORLESS
    /////////////////////////////////////////////////////////////////////////*/

    function test_SelectorlessZeroesNonZeroSelector() public pure {
        PolicyData memory data = _policy(_eq(1));
        data.isSelectorless = true;

        bytes memory policy = PolicyCoder.encode(data);
        assertTrue(Policy.isSelectorless(policy));
        assertEq(bytes4(LibBytes.load(policy, PF.POLICY_SELECTOR_OFFSET)), bytes4(0));
    }
}

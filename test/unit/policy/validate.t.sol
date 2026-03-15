// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyTest } from "../Policy.t.sol";

import { Be16 } from "src/Be16.sol";
import { OpCode } from "src/OpCode.sol";
import { Policy } from "src/Policy.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

contract ValidateTest is PolicyTest {
    /*/////////////////////////////////////////////////////////////////////////
                                  VALID POLICY
    /////////////////////////////////////////////////////////////////////////*/

    function test_ValidPolicy() public view {
        bytes memory blob = _validBlob();
        harness.validate(blob);
    }

    function test_ValidTwoGroupPolicy() public view {
        bytes memory blob = _twoGroupBlob();
        harness.validate(blob);
    }

    function test_ValidContextPolicy() public view {
        bytes memory blob = _contextBlob();
        harness.validate(blob);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              EDGE-CASE ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_DescriptorLengthZero() public {
        bytes memory blob = _validBlob();
        Be16.write(blob, PF.POLICY_DESC_LENGTH_OFFSET, 0);
        vm.expectRevert(Policy.MalformedHeader.selector);
        harness.validate(blob);
    }

    function test_RevertWhen_UnsupportedVersion() public {
        bytes memory blob = _validBlob();
        blob[PF.POLICY_HEADER_OFFSET] = 0x0F;
        vm.expectRevert(abi.encodeWithSelector(Policy.UnsupportedVersion.selector, uint8(0x0F)));
        harness.validate(blob);
    }

    function test_RevertWhen_VersionZero() public {
        bytes memory blob = _validBlob();
        blob[PF.POLICY_HEADER_OFFSET] = 0x00;
        vm.expectRevert(abi.encodeWithSelector(Policy.UnsupportedVersion.selector, uint8(0)));
        harness.validate(blob);
    }

    function test_RevertWhen_AllReservedBitsSet() public {
        bytes memory blob = _validBlob();
        blob[PF.POLICY_HEADER_OFFSET] = bytes1(PF.POLICY_VERSION | 0xE0);
        vm.expectRevert(Policy.MalformedHeader.selector);
        harness.validate(blob);
    }

    function test_RevertWhen_InvalidScopeMax() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        blob[ruleOffset + PF.RULE_SCOPE_OFFSET] = 0xFF;
        vm.expectRevert(abi.encodeWithSelector(Policy.InvalidScope.selector, ruleOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_UnknownOperator() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint8 depth = uint8(blob[ruleOffset + PF.RULE_DEPTH_OFFSET]);
        uint256 opCodeOffset = ruleOffset + PF.RULE_PATH_OFFSET + uint256(depth) * PF.PATH_STEP_SIZE;
        blob[opCodeOffset] = 0x50;
        vm.expectRevert(abi.encodeWithSelector(Policy.UnknownOperator.selector, ruleOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_NegatedUnknownOperator() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint8 depth = uint8(blob[ruleOffset + PF.RULE_DEPTH_OFFSET]);
        uint256 opCodeOffset = ruleOffset + PF.RULE_PATH_OFFSET + uint256(depth) * PF.PATH_STEP_SIZE;
        blob[opCodeOffset] = bytes1(OpCode.NOT | 0x50);
        vm.expectRevert(abi.encodeWithSelector(Policy.UnknownOperator.selector, ruleOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_TrailingBytesAfterAllGroups() public {
        bytes memory blob = _validBlob();
        bytes memory extended = new bytes(blob.length + 1);
        for (uint256 i; i < blob.length; ++i) {
            extended[i] = blob[i];
        }
        vm.expectRevert(Policy.UnexpectedEnd.selector);
        harness.validate(extended);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              NEGATED VALID OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_NegatedEqAccepted() public view {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint8 depth = uint8(blob[ruleOffset + PF.RULE_DEPTH_OFFSET]);
        uint256 opCodeOffset = ruleOffset + PF.RULE_PATH_OFFSET + uint256(depth) * PF.PATH_STEP_SIZE;
        // EQ with NOT flag should still be valid.
        blob[opCodeOffset] = bytes1(OpCode.NOT | OpCode.EQ);
        harness.validate(blob);
    }
}

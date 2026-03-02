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
                                 HEADER ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_BlobTooShort() public {
        bytes memory blob = new bytes(PF.POLICY_HEADER_PREFIX - 1);
        vm.expectRevert(Policy.MalformedHeader.selector);
        harness.validate(blob);
    }

    function test_RevertWhen_DescriptorLengthZero() public {
        // Build minimal blob: valid version + selector + descLength=0 + groupCount=1.
        bytes memory blob = _validBlob();
        // Set descLength to 0.
        Be16.write(blob, PF.POLICY_DESC_LENGTH_OFFSET, 0);
        vm.expectRevert(Policy.MalformedHeader.selector);
        harness.validate(blob);
    }

    function test_RevertWhen_DescriptorLengthOne() public {
        // Build minimal blob: valid version + selector + descLength=1 + 1 byte desc + groupCount.
        bytes memory blob = _validBlob();
        // Set descLength to 1.
        Be16.write(blob, PF.POLICY_DESC_LENGTH_OFFSET, 1);
        vm.expectRevert(Policy.MalformedHeader.selector);
        harness.validate(blob);
    }

    function test_RevertWhen_UnsupportedVersion() public {
        bytes memory blob = _validBlob();
        // 0xFF has version nibble 0x0F (not 0x01) and reserved bits set.
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

    function test_RevertWhen_ReservedBitsSet() public {
        bytes memory blob = _validBlob();
        // Version nibble is correct (0x01) but bit 5 is set.
        blob[PF.POLICY_HEADER_OFFSET] = bytes1(PF.POLICY_VERSION | 0x20);
        vm.expectRevert(Policy.MalformedHeader.selector);
        harness.validate(blob);
    }

    function test_RevertWhen_AllReservedBitsSet() public {
        bytes memory blob = _validBlob();
        // Version nibble correct but all reserved bits (5-7) set.
        blob[PF.POLICY_HEADER_OFFSET] = bytes1(PF.POLICY_VERSION | 0xE0);
        vm.expectRevert(Policy.MalformedHeader.selector);
        harness.validate(blob);
    }

    function test_ValidSelectorlessPolicy() public view {
        bytes memory blob = _validBlob();
        blob[PF.POLICY_HEADER_OFFSET] = bytes1(PF.POLICY_VERSION | PF.FLAG_NO_SELECTOR);
        _zeroSelector(blob);
        harness.validate(blob);
    }

    function test_RevertWhen_SelectorlessWithNonZeroSelector() public {
        bytes memory blob = _validBlob();
        blob[PF.POLICY_HEADER_OFFSET] = bytes1(PF.POLICY_VERSION | PF.FLAG_NO_SELECTOR);
        // Selector slot is non-zero (the original selector remains).
        vm.expectRevert(Policy.MalformedHeader.selector);
        harness.validate(blob);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 EMPTY POLICY
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_ZeroGroups() public {
        bytes memory blob = _validBlob();
        // groupCount is the byte right after the descriptor.
        uint16 descLen = Be16.readUnchecked(blob, PF.POLICY_DESC_LENGTH_OFFSET);
        uint256 groupCountOffset = PF.POLICY_HEADER_PREFIX + descLen;
        blob[groupCountOffset] = 0x00;
        vm.expectRevert(Policy.EmptyPolicy.selector);
        harness.validate(blob);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 GROUP ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_GroupOverflow() public {
        bytes memory blob = _validBlob();
        uint256 groupOffset = _firstGroupOffset(blob);
        // Set groupSize larger than remaining blob.
        _writeU32(blob, groupOffset + PF.GROUP_SIZE_OFFSET, uint32(blob.length));
        vm.expectRevert(abi.encodeWithSelector(Policy.GroupOverflow.selector, groupOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_EmptyGroup() public {
        bytes memory blob = _validBlob();
        uint256 groupOffset = _firstGroupOffset(blob);
        // Set ruleCount to zero.
        Be16.write(blob, groupOffset + PF.GROUP_RULECOUNT_OFFSET, 0);
        vm.expectRevert(abi.encodeWithSelector(Policy.EmptyGroup.selector, groupOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_GroupTooSmall() public {
        bytes memory blob = _validBlob();
        uint256 groupOffset = _firstGroupOffset(blob);
        // Set ruleCount to a large number so ruleCount * RULE_MIN_SIZE exceeds groupSize.
        Be16.write(blob, groupOffset + PF.GROUP_RULECOUNT_OFFSET, 1000);
        vm.expectRevert(abi.encodeWithSelector(Policy.GroupTooSmall.selector, groupOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_GroupSizeMismatch() public {
        bytes memory blob = _validBlob();
        uint256 groupOffset = _firstGroupOffset(blob);
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint16 ruleTotalSize = Be16.readUnchecked(blob, ruleOffset);

        // Set groupSize to ruleTotalSize + 1 (trailing byte).
        _writeU32(blob, groupOffset + PF.GROUP_SIZE_OFFSET, uint32(ruleTotalSize) + 1);

        // Extend blob to accommodate the extra byte.
        bytes memory extended = new bytes(blob.length + 1);
        for (uint256 i; i < blob.length; ++i) {
            extended[i] = blob[i];
        }
        vm.expectRevert(abi.encodeWithSelector(Policy.GroupSizeMismatch.selector, groupOffset));
        harness.validate(extended);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  RULE ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_RuleTooSmall() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        // Set ruleSize below minimum.
        Be16.write(blob, ruleOffset, uint16(PF.RULE_MIN_SIZE - 1));
        vm.expectRevert(abi.encodeWithSelector(Policy.RuleTooSmall.selector, ruleOffset, uint256(PF.RULE_MIN_SIZE - 1)));
        harness.validate(blob);
    }

    function test_RevertWhen_RuleOverflow() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint16 currentSize = Be16.readUnchecked(blob, ruleOffset);

        // Set ruleSize larger than group allows.
        Be16.write(blob, ruleOffset, currentSize + 10);
        vm.expectRevert(abi.encodeWithSelector(Policy.RuleOverflow.selector, ruleOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_InvalidScope() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        // Set scope to an invalid value (neither CONTEXT=0 nor CALLDATA=1).
        blob[ruleOffset + PF.RULE_SCOPE_OFFSET] = 0x02;
        vm.expectRevert(abi.encodeWithSelector(Policy.InvalidScope.selector, ruleOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_InvalidScopeMax() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        blob[ruleOffset + PF.RULE_SCOPE_OFFSET] = 0xFF;
        vm.expectRevert(abi.encodeWithSelector(Policy.InvalidScope.selector, ruleOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_RuleSizeMismatch() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint256 groupOffset = _firstGroupOffset(blob);

        // Get the actual rule size then inflate ruleSize by 1 (mismatches field layout).
        uint16 currentSize = Be16.readUnchecked(blob, ruleOffset);
        Be16.write(blob, ruleOffset, currentSize + 1);
        // Also inflate groupSize to accommodate.
        _writeU32(blob, groupOffset + PF.GROUP_SIZE_OFFSET, uint32(currentSize) + 1);

        // Extend blob to avoid out-of-bounds.
        bytes memory extended = new bytes(blob.length + 1);
        for (uint256 i; i < blob.length; ++i) {
            extended[i] = blob[i];
        }
        vm.expectRevert(abi.encodeWithSelector(Policy.RuleSizeMismatch.selector, ruleOffset));
        harness.validate(extended);
    }

    function test_RevertWhen_EmptyPath() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint256 groupOffset = _firstGroupOffset(blob);

        // Read current values.
        uint16 currentSize = Be16.readUnchecked(blob, ruleOffset);
        uint8 currentDepth = uint8(blob[ruleOffset + PF.RULE_DEPTH_OFFSET]);

        // Set depth to 0. New size = currentSize - currentDepth * PATH_STEP_SIZE.
        uint16 newSize = currentSize - uint16(currentDepth) * uint16(PF.PATH_STEP_SIZE);
        blob[ruleOffset + PF.RULE_DEPTH_OFFSET] = 0x00;
        Be16.write(blob, ruleOffset, newSize);
        _writeU32(blob, groupOffset + PF.GROUP_SIZE_OFFSET, uint32(newSize));

        // Rebuild blob: remove path steps from the rule.
        uint256 pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
        uint256 pathBytes = uint256(currentDepth) * PF.PATH_STEP_SIZE;
        uint256 afterPath = pathStart + pathBytes;
        uint256 trailing = blob.length - afterPath;

        bytes memory fixed_ = new bytes(blob.length - pathBytes);
        for (uint256 i; i < pathStart; ++i) {
            fixed_[i] = blob[i];
        }
        for (uint256 i; i < trailing; ++i) {
            fixed_[pathStart + i] = blob[afterPath + i];
        }
        vm.expectRevert(abi.encodeWithSelector(Policy.EmptyPath.selector, ruleOffset));
        harness.validate(fixed_);
    }

    function test_RevertWhen_InvalidContextPath() public {
        bytes memory blob = _contextBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint256 groupOffset = _firstGroupOffset(blob);

        // Context rules must have depth == 1. Set depth to 2.
        uint16 currentSize = Be16.readUnchecked(blob, ruleOffset);
        uint16 newSize = currentSize + uint16(PF.PATH_STEP_SIZE);

        blob[ruleOffset + PF.RULE_DEPTH_OFFSET] = 0x02;
        Be16.write(blob, ruleOffset, newSize);
        _writeU32(blob, groupOffset + PF.GROUP_SIZE_OFFSET, uint32(newSize));

        // Insert extra path step.
        uint256 insertAt = ruleOffset + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE;
        uint256 trailing = blob.length - insertAt;
        bytes memory expanded = new bytes(blob.length + PF.PATH_STEP_SIZE);
        for (uint256 i; i < insertAt; ++i) {
            expanded[i] = blob[i];
        }
        expanded[insertAt] = 0x00;
        expanded[insertAt + 1] = 0x00;
        for (uint256 i; i < trailing; ++i) {
            expanded[insertAt + PF.PATH_STEP_SIZE + i] = blob[insertAt + i];
        }
        vm.expectRevert(abi.encodeWithSelector(Policy.InvalidContextPath.selector, ruleOffset));
        harness.validate(expanded);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                OPERATOR ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_UnknownOperator() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint8 depth = uint8(blob[ruleOffset + PF.RULE_DEPTH_OFFSET]);
        uint256 opCodeOffset = ruleOffset + PF.RULE_PATH_OFFSET + uint256(depth) * PF.PATH_STEP_SIZE;
        // Set to an undefined operator code.
        blob[opCodeOffset] = 0x50;
        vm.expectRevert(abi.encodeWithSelector(Policy.UnknownOperator.selector, ruleOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_OperatorPayloadSizeMismatch() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint8 depth = uint8(blob[ruleOffset + PF.RULE_DEPTH_OFFSET]);
        uint256 opCodeOffset = ruleOffset + PF.RULE_PATH_OFFSET + uint256(depth) * PF.PATH_STEP_SIZE;

        // Change EQ (expects 32 bytes) to BETWEEN (expects 64 bytes) without changing dataLength.
        blob[opCodeOffset] = bytes1(OpCode.BETWEEN);
        vm.expectRevert(abi.encodeWithSelector(Policy.UnknownOperator.selector, ruleOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_NegatedUnknownOperator() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint8 depth = uint8(blob[ruleOffset + PF.RULE_DEPTH_OFFSET]);
        uint256 opCodeOffset = ruleOffset + PF.RULE_PATH_OFFSET + uint256(depth) * PF.PATH_STEP_SIZE;
        // NOT flag with invalid base: 0x80 | 0x50 = 0xD0.
        blob[opCodeOffset] = bytes1(OpCode.NOT | 0x50);
        vm.expectRevert(abi.encodeWithSelector(Policy.UnknownOperator.selector, ruleOffset));
        harness.validate(blob);
    }

    /*/////////////////////////////////////////////////////////////////////////
                               TRAILING BYTES
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_TrailingBytesAfterAllGroups() public {
        bytes memory blob = _validBlob();
        // Append an extra byte.
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyTest } from "../Policy.t.sol";

import { Be16 } from "src/Be16.sol";
import { arg } from "src/Constraint.sol";
import { OpCode } from "src/OpCode.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

contract ValidateTest is PolicyTest {
    /// @dev Builds a single-rule calldata-scope blob with a zero path of the given depth.
    function _pathDepthBlob(uint256 depth) private pure returns (bytes memory) {
        // forge-lint: disable-next-item(unsafe-typecast)
        bytes memory rule = bytes.concat(
            bytes2(uint16(PF.RULE_FIXED_OVERHEAD + depth * PF.PATH_STEP_SIZE + 32)),
            bytes1(PF.SCOPE_CALLDATA),
            bytes1(uint8(depth)),
            new bytes(depth * PF.PATH_STEP_SIZE),
            bytes1(OpCode.EQ),
            bytes2(uint16(32)),
            new bytes(32)
        );
        // forge-lint: disable-next-item(unsafe-typecast)
        return bytes.concat(hex"012fbebd38000301011f01", bytes2(uint16(1)), bytes4(uint32(rule.length)), rule);
    }

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

    function test_RevertWhen_InSetNotSorted() public {
        uint256[] memory set = new uint256[](2);
        set[0] = 10;
        set[1] = 20;
        bytes memory blob = PolicyBuilder.create("foo(uint256)").add(arg(0).isIn(set)).buildUnsafe();

        uint256 ruleOffset = _firstRuleOffset(blob);
        uint8 depth = uint8(blob[ruleOffset + PF.RULE_DEPTH_OFFSET]);
        uint256 payloadStart = ruleOffset + PF.RULE_PATH_OFFSET + uint256(depth) * PF.PATH_STEP_SIZE
            + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;

        // Swap the two sorted operand words so the set is descending.
        for (uint256 i; i < 32; ++i) {
            bytes1 tmp = blob[payloadStart + i];
            blob[payloadStart + i] = blob[payloadStart + 32 + i];
            blob[payloadStart + 32 + i] = tmp;
        }

        vm.expectRevert(abi.encodeWithSelector(Policy.UnsortedInSet.selector, ruleOffset));
        harness.validate(blob);
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

    /*/////////////////////////////////////////////////////////////////////////
                        PATH DEPTH AND CONTEXT PROPERTIES
    /////////////////////////////////////////////////////////////////////////*/

    function test_PathDepthAtMax() public view {
        harness.validate(_pathDepthBlob(PF.MAX_PATH_DEPTH));
    }

    function test_RevertWhen_PathTooDeep() public {
        bytes memory blob = _pathDepthBlob(uint256(PF.MAX_PATH_DEPTH) + 1);
        uint256 ruleOffset = _firstRuleOffset(blob);
        vm.expectRevert(abi.encodeWithSelector(Policy.PathTooDeep.selector, ruleOffset, uint256(PF.MAX_PATH_DEPTH) + 1));
        harness.validate(blob);
    }

    function test_ContextPropertyAtMax() public view {
        bytes memory blob = _contextBlob(PF.CTX_MAX);
        harness.validate(blob);
    }

    function test_RevertWhen_UnknownContextProperty() public {
        bytes memory blob = _contextBlob(PF.CTX_MAX + 1);
        uint256 ruleOffset = _firstRuleOffset(blob);
        vm.expectRevert(abi.encodeWithSelector(Policy.UnknownContextProperty.selector, ruleOffset));
        harness.validate(blob);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyTest } from "../Policy.t.sol";

import { Be16 } from "src/Be16.sol";
import { arg, msgSender } from "src/Constraint.sol";
import { OpCode } from "src/OpCode.sol";
import { Path } from "src/Path.sol";
import { Policy } from "src/Policy.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

contract ValidateTest is PolicyTest {
    /// @dev Asserts that validating a single-rule blob carrying `hint` reports a malformed hint.
    function _expectMalformedHint(bytes memory path, bytes memory hint) private {
        bytes memory blob = _calldataRuleBlob(path, hint);
        vm.expectRevert(abi.encodeWithSelector(Policy.MalformedHint.selector, _firstRuleOffset(blob)));
        harness.validate(blob);
    }

    /// @dev Builds a single-rule calldata-scope blob with a zero path of the given depth.
    function _pathDepthBlob(uint256 depth) private pure returns (bytes memory) {
        return _calldataRuleBlob(new bytes(depth * PF.PATH_STEP_SIZE), STATIC_HINT);
    }

    /// @dev Builds a single-rule calldata-scope blob whose path quantifies over the argument.
    function _quantifiedRuleBlob(bytes memory hint) private pure returns (bytes memory) {
        return _calldataRuleBlob(hex"0000ffff", hint);
    }

    /// @dev Wraps a single calldata rule with the given path and hint block into a policy blob
    /// for `foo(uint256)`.
    function _calldataRuleBlob(bytes memory path, bytes memory hint) private pure returns (bytes memory) {
        return _calldataRuleBlob(path, hint, OpCode.EQ);
    }

    function _calldataRuleBlob(bytes memory path, bytes memory hint, uint8 opCode) private pure returns (bytes memory) {
        bytes memory rule = bytes.concat(
            bytes2(uint16(PF.RULE_FIXED_OVERHEAD + path.length + hint.length + 32)),
            bytes1(PF.SCOPE_CALLDATA),
            bytes1(uint8(path.length / PF.PATH_STEP_SIZE)),
            path,
            hint,
            bytes1(opCode),
            bytes2(uint16(32)),
            new bytes(32)
        );
        return bytes.concat(hex"022fbebd38000302012001", bytes2(uint16(1)), bytes4(uint32(rule.length)), rule);
    }

    /// @dev Builds a single-rule EQ_CTX blob whose operand word holds `ctxId`.
    function _eqCtxBlob(uint16 ctxId) private pure returns (bytes memory) {
        bytes memory blob = _calldataRuleBlob(hex"0000", STATIC_HINT, OpCode.EQ_CTX);
        Be16.write(blob, _eqCtxOperandOffset(blob) + 30, ctxId);
        return blob;
    }

    /// @dev Returns the offset of the first rule's operand word.
    function _eqCtxOperandOffset(bytes memory blob) private pure returns (uint256) {
        uint256 ruleOffset = _firstRuleOffset(blob);
        return _opCodeOffset(blob, ruleOffset) + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;
    }

    /// @dev Asserts that a single-rule blob pairing `hint` with `opCode` reports a mismatched pair.
    function _expectOperatorTargetMismatch(bytes memory hint, uint8 opCode) private {
        bytes memory blob = _calldataRuleBlob(hex"0000", hint, opCode);
        vm.expectRevert(abi.encodeWithSelector(Policy.OperatorTargetMismatch.selector, _firstRuleOffset(blob)));
        harness.validate(blob);
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
        uint256 opCodeOffset = _opCodeOffset(blob, ruleOffset);
        blob[opCodeOffset] = 0x50;
        vm.expectRevert(abi.encodeWithSelector(Policy.UnknownOperator.selector, ruleOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_NegatedUnknownOperator() public {
        bytes memory blob = _validBlob();
        uint256 ruleOffset = _firstRuleOffset(blob);
        uint256 opCodeOffset = _opCodeOffset(blob, ruleOffset);
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
        vm.expectRevert(Policy.TrailingBytes.selector);
        harness.validate(extended);
    }

    function test_RevertWhen_InSetNotSorted() public {
        uint256[] memory set = new uint256[](2);
        set[0] = 10;
        set[1] = 20;
        bytes memory blob = PolicyBuilder.create("foo(uint256)").add(arg(0).isIn(set)).buildUnsafe();

        uint256 ruleOffset = _firstRuleOffset(blob);
        uint256 payloadStart = _opCodeOffset(blob, ruleOffset) + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;

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
        uint256 opCodeOffset = _opCodeOffset(blob, ruleOffset);
        // EQ with NOT flag should still be valid.
        blob[opCodeOffset] = bytes1(OpCode.NOT | OpCode.EQ);
        harness.validate(blob);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  HINT BLOCK
    /////////////////////////////////////////////////////////////////////////*/

    function test_HopFreeHintAccepted() public view {
        harness.validate(_calldataRuleBlob(hex"0000", STATIC_HINT));
    }

    function test_HopChainAccepted() public view {
        harness.validate(_calldataRuleBlob(hex"0000", hex"0100000000ffff000000000000000070", OpCode.LENGTH_EQ));
    }

    function test_HeaderSizesTheBlock() public view {
        bytes memory hint = hex"0100000000ffff000000000000000070";
        bytes memory blob = _calldataRuleBlob(hex"0000", hint, OpCode.LENGTH_EQ);
        (, uint256 hintSize) = harness.hintView(blob, _firstRuleOffset(blob));
        assertEq(hintSize, hint.length, "hop chain hint size");
    }

    function test_SuffixHeaderSizesTheQuantifiedBlock() public view {
        bytes memory hint = hex"4000000000000300010100000000ffff000000000000000020";
        bytes memory blob = _quantifiedRuleBlob(hint);
        (, uint256 hintSize) = harness.hintView(blob, _firstRuleOffset(blob));
        assertEq(hintSize, hint.length, "quantified hint size");
        harness.validate(blob);
    }

    function test_RevertWhen_HeaderKindReserved() public {
        _expectMalformedHint(hex"0000", hex"c000000000000020");
    }

    function test_RevertWhen_SuffixHeaderReservedBitsSet() public {
        _expectMalformedHint(hex"0000ffff", hex"4000000000000300014000000000000020");
    }

    function test_RevertWhen_HopIndexReserved() public {
        _expectMalformedHint(hex"0000", hex"0100000000fffe000100000000000020");
    }

    function test_RevertWhen_PlainHopCarriesMeta() public {
        _expectMalformedHint(hex"0000", hex"0100000000ffff400100000000000020");
    }

    function test_RevertWhen_ElementHopCarriesDelta() public {
        _expectMalformedHint(hex"0000", hex"01000000200001400100000000000020");
    }

    function test_RevertWhen_HopMetaReservedBitsSet() public {
        _expectMalformedHint(hex"0000", hex"01000000000001100100000000000020");
    }

    function test_RevertWhen_FrameMetaReservedBitsSet() public {
        _expectMalformedHint(hex"0000ffff", hex"4000000000000310010000000000000020");
    }

    function test_RevertWhen_SuffixHopIndexReserved() public {
        _expectMalformedHint(hex"0000ffff", hex"4000000000000300010100000000fffe000100000000000020");
    }

    function test_RevertWhen_TargetMetaOnNonArrayType() public {
        _expectMalformedHint(hex"0000", hex"0000000000400120");
    }

    function test_RevertWhen_TargetMetaReservedBitsSet() public {
        _expectMalformedHint(hex"0000", hex"0000000000500181");
    }

    /*/////////////////////////////////////////////////////////////////////////
                             HINT TARGET ADDRESSABILITY
    /////////////////////////////////////////////////////////////////////////*/

    function test_LengthOperatorOnBytesTargetAccepted() public view {
        harness.validate(_calldataRuleBlob(hex"0000", hex"0000000000000070", OpCode.LENGTH_EQ));
    }

    function test_LengthOperatorOnDynamicArrayTargetAccepted() public view {
        harness.validate(_calldataRuleBlob(hex"0000", hex"0000000000010081", OpCode.LENGTH_GTE));
    }

    function test_NegatedLengthOperatorOnBytesTargetAccepted() public view {
        harness.validate(_calldataRuleBlob(hex"0000", hex"0000000000000070", OpCode.LENGTH_EQ | OpCode.NOT));
    }

    function test_RevertWhen_TargetTypeCodeUndefined() public {
        _expectMalformedHint(hex"0000", hex"0000000000000000");
    }

    function test_RevertWhen_TargetTypeCodeIsTuple() public {
        _expectMalformedHint(hex"0000", hex"0000000000000090");
    }

    function test_RevertWhen_TargetTypeCodeIsStaticArray() public {
        _expectMalformedHint(hex"0000", hex"0000000000000080");
    }

    function test_RevertWhen_ValueOperatorOnBytesTarget() public {
        _expectOperatorTargetMismatch(hex"0000000000000070", OpCode.EQ);
    }

    function test_RevertWhen_SetOperatorOnDynamicArrayTarget() public {
        _expectOperatorTargetMismatch(hex"0000000000010081", OpCode.IN);
    }

    function test_RevertWhen_LengthOperatorOnElementaryTarget() public {
        _expectOperatorTargetMismatch(STATIC_HINT, OpCode.LENGTH_EQ);
    }

    function test_RevertWhen_NegatedValueOperatorOnBytesTarget() public {
        _expectOperatorTargetMismatch(hex"0000000000000070", OpCode.EQ | OpCode.NOT);
    }

    /// @dev Asserts that a compiled policy pairs an operator its target cannot carry.
    function _expectBuiltMismatch(bytes memory policy) private {
        vm.expectRevert(abi.encodeWithSelector(Policy.OperatorTargetMismatch.selector, _firstRuleOffset(policy)));
        harness.validate(policy);
    }

    function test_RevertWhen_ValueOpCompilesOntoDynamicTarget() public {
        _expectBuiltMismatch(PolicyBuilder.create("foo(bytes)").add(arg(0).eq(uint256(0))).buildUnsafe());
    }

    function test_RevertWhen_ValueOpCompilesOntoDynamicElement() public {
        // forgefmt: disable-next-item
        _expectBuiltMismatch(
            PolicyBuilder.create("foo(bytes[])").add(arg(0, Path.ALL).eq(uint256(0))).buildUnsafe()
        );
    }

    function test_RevertWhen_ValueOpCompilesOntoDynamicSuffixTarget() public {
        // forgefmt: disable-next-item
        _expectBuiltMismatch(
            PolicyBuilder.create("foo(bytes[][])").add(arg(0, Path.ALL, 0).eq(uint256(0))).buildUnsafe()
        );
    }

    function test_RevertWhen_RuleSizeDisagreesWithHeader() public {
        // The header sizes the block, so a rule declaring one byte more than that fails to add up.
        bytes memory blob = _calldataRuleBlob(hex"0000", hex"000000000000002000");
        vm.expectRevert(abi.encodeWithSelector(Policy.RuleSizeMismatch.selector, _firstRuleOffset(blob)));
        harness.validate(blob);
    }

    function test_RevertWhen_HeaderClaimsAbsentHops() public {
        // The claimed hop overlaps the target block, which then reads as a malformed entry.
        _expectMalformedHint(hex"0000", hex"0100000000000020");
    }

    function test_RevertWhen_QuantifiedBlockOmitsItsFrame() public {
        _expectMalformedHint(hex"0000ffff", hex"400000000000030001");
    }

    function test_RevertWhen_EmptyPath() public {
        // A depth-zero calldata rule still resolves a hint block, so the empty path is what fails.
        bytes memory blob = _calldataRuleBlob(hex"", STATIC_HINT);
        uint256 ruleOffset = _firstRuleOffset(blob);
        vm.expectRevert(abi.encodeWithSelector(Policy.EmptyPath.selector, ruleOffset));
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

    /*/////////////////////////////////////////////////////////////////////////
                          CONTEXT REFERENCE OPERANDS
    /////////////////////////////////////////////////////////////////////////*/

    function test_EqCtxOperandAtMax() public view {
        harness.validate(_eqCtxBlob(PF.CTX_MAX));
    }

    function test_NegatedEqCtx() public view {
        harness.validate(_calldataRuleBlob(hex"0000", STATIC_HINT, OpCode.EQ_CTX | OpCode.NOT));
    }

    function test_ValidContextEqCtxPolicy() public view {
        bytes memory blob = PolicyBuilder.create("foo(uint256)").add(msgSender().eqCtx(PF.CTX_TX_ORIGIN)).buildUnsafe();
        harness.validate(blob);
    }

    function test_RevertWhen_EqCtxOperandAboveMax() public {
        bytes memory blob = _eqCtxBlob(PF.CTX_MAX + 1);
        uint256 ruleOffset = _firstRuleOffset(blob);
        vm.expectRevert(abi.encodeWithSelector(Policy.UnknownContextProperty.selector, ruleOffset));
        harness.validate(blob);
    }

    function test_RevertWhen_EqCtxOperandHighBytesSet() public {
        // A defined ID in the low bytes does not excuse garbage above them.
        bytes memory blob = _eqCtxBlob(PF.CTX_MSG_SENDER);
        blob[_eqCtxOperandOffset(blob)] = 0x01;
        uint256 ruleOffset = _firstRuleOffset(blob);
        vm.expectRevert(abi.encodeWithSelector(Policy.UnknownContextProperty.selector, ruleOffset));
        harness.validate(blob);
    }
}

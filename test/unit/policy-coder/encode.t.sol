// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Constraint } from "src/Constraint.sol";
import { OpCode } from "src/OpCode.sol";
import { PolicyCoder, PolicyData } from "src/PolicyCoder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

import { PolicyCoderTest } from "../PolicyCoder.t.sol";

// forge-lint: disable-next-item(unsafe-typecast)
contract EncodeTest is PolicyCoderTest {
    bytes4 internal constant SELECTOR = bytes4(keccak256("foo(uint256)"));
    bytes internal constant DESCRIPTOR = hex"";

    /*/////////////////////////////////////////////////////////////////////////
                                  BINARY FORMAT
    /////////////////////////////////////////////////////////////////////////*/

    function test_HeaderFormat() public pure {
        bytes memory blob = PolicyCoder.encode(
            _singleRule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(42)))), SELECTOR, DESCRIPTOR
        );

        assertEq(uint8(blob[PF.POLICY_HEADER_OFFSET]), PF.POLICY_VERSION, "version");
        assertEq(
            bytes4(
                bytes.concat(
                    blob[PF.POLICY_SELECTOR_OFFSET],
                    blob[PF.POLICY_SELECTOR_OFFSET + 1],
                    blob[PF.POLICY_SELECTOR_OFFSET + 2],
                    blob[PF.POLICY_SELECTOR_OFFSET + 3]
                )
            ),
            SELECTOR,
            "selector"
        );
        uint256 groupCountOffset = PF.POLICY_HEADER_PREFIX + DESCRIPTOR.length;
        assertEq(uint8(blob[groupCountOffset]), 1, "groupCount");
    }

    function test_GroupHeaderFormat() public pure {
        bytes memory blob = PolicyCoder.encode(
            _twoRules(
                PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(1)))),
                PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0001", _op1(OpCode.EQ, bytes32(uint256(2))))
            ),
            SELECTOR,
            DESCRIPTOR
        );

        uint256 groupStart = PF.POLICY_HEADER_PREFIX + DESCRIPTOR.length + PF.POLICY_GROUP_COUNT_SIZE;
        assertEq(_readU16(blob, groupStart + PF.GROUP_RULECOUNT_OFFSET), 2, "ruleCount");
        uint256 expectedRuleSize = PF.RULE_MIN_SIZE + 32;
        assertEq(_readU32(blob, groupStart + PF.GROUP_SIZE_OFFSET), expectedRuleSize * 2, "groupSize");
    }

    function test_RuleFormat() public pure {
        bytes memory blob = PolicyCoder.encode(
            _singleRule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(42)))), SELECTOR, DESCRIPTOR
        );

        assertEq(_readU16(blob, _firstRuleOffset(DESCRIPTOR.length)), PF.RULE_MIN_SIZE + 32, "ruleSize");
        assertEq(uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_SCOPE_OFFSET]), PF.SCOPE_CALLDATA, "scope");
        assertEq(uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_DEPTH_OFFSET]), 1, "pathDepth");
        assertEq(uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + 0]), 0x00, "path[0]");
        assertEq(uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + 1]), 0x00, "path[1]");
        assertEq(
            uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE]),
            OpCode.EQ,
            "opCode"
        );
        assertEq(
            _readU16(
                blob,
                _firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE + PF.RULE_OPCODE_SIZE
            ),
            32,
            "dataLength"
        );
    }

    function test_RuleSizeCalculation() public pure {
        bytes memory blob = PolicyCoder.encode(
            _singleRule(
                PF.SCOPE_CALLDATA,
                hex"00010002",
                _op3(OpCode.IN, bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3)))
            ),
            SELECTOR,
            DESCRIPTOR
        );

        uint256 pathLength = 4;
        uint256 dataLength = 96;
        assertEq(
            _readU16(blob, _firstRuleOffset(DESCRIPTOR.length)),
            (PF.RULE_MIN_SIZE - PF.PATH_STEP_SIZE) + pathLength + dataLength
        );
    }

    function test_OpCodeOnly() public pure {
        bytes memory blob = PolicyCoder.encode(
            _singleRule(PF.SCOPE_CALLDATA, hex"0000", abi.encodePacked(OpCode.EQ)), SELECTOR, DESCRIPTOR
        );

        assertEq(_readU16(blob, _firstRuleOffset(DESCRIPTOR.length)), PF.RULE_MIN_SIZE, "ruleSize with no data");
        assertEq(
            _readU16(
                blob,
                _firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE + PF.RULE_OPCODE_SIZE
            ),
            0,
            "dataLength"
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 CANONICALIZATION
    /////////////////////////////////////////////////////////////////////////*/

    function test_RuleOrderPermutationInvariant() public pure {
        PolicyCoder.Rule memory ruleA =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(1))));
        PolicyCoder.Rule memory ruleB =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0001", _op1(OpCode.EQ, bytes32(uint256(2))));

        bytes memory blobAb = PolicyCoder.encode(_twoRules(ruleA, ruleB), SELECTOR, DESCRIPTOR);
        bytes memory blobBa = PolicyCoder.encode(_twoRules(ruleB, ruleA), SELECTOR, DESCRIPTOR);

        assertEq(keccak256(blobAb), keccak256(blobBa));
    }

    function test_GroupOrderPermutationInvariant() public pure {
        PolicyCoder.Rule memory ruleA =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(1))));
        PolicyCoder.Rule memory ruleB =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0001", _op1(OpCode.EQ, bytes32(uint256(2))));

        PolicyCoder.Group[] memory groupsAb = new PolicyCoder.Group[](2);
        groupsAb[0].rules = new PolicyCoder.Rule[](1);
        groupsAb[0].rules[0] = ruleA;
        groupsAb[1].rules = new PolicyCoder.Rule[](1);
        groupsAb[1].rules[0] = ruleB;

        PolicyCoder.Group[] memory groupsBa = new PolicyCoder.Group[](2);
        groupsBa[0].rules = new PolicyCoder.Rule[](1);
        groupsBa[0].rules[0] = ruleB;
        groupsBa[1].rules = new PolicyCoder.Rule[](1);
        groupsBa[1].rules[0] = ruleA;

        bytes memory blobAb = PolicyCoder.encode(groupsAb, SELECTOR, DESCRIPTOR);
        bytes memory blobBa = PolicyCoder.encode(groupsBa, SELECTOR, DESCRIPTOR);

        assertEq(keccak256(blobAb), keccak256(blobBa));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                     SORTING
    /////////////////////////////////////////////////////////////////////////*/

    function test_SortsByScope() public pure {
        PolicyCoder.Rule memory contextRule = PolicyCoder.Rule(
            PF.SCOPE_CONTEXT,
            abi.encodePacked(PF.CTX_MSG_SENDER),
            _op1(OpCode.EQ, bytes32(uint256(uint160(address(1)))))
        );
        PolicyCoder.Rule memory calldataRule =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(42))));

        bytes memory blob = PolicyCoder.encode(_twoRules(calldataRule, contextRule), SELECTOR, DESCRIPTOR);

        assertEq(
            uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_SCOPE_OFFSET]), PF.SCOPE_CONTEXT, "context first"
        );
        uint256 secondRuleStart =
            _firstRuleOffset(DESCRIPTOR.length) + _readU16(blob, _firstRuleOffset(DESCRIPTOR.length));
        assertEq(uint8(blob[secondRuleStart + PF.RULE_SCOPE_OFFSET]), PF.SCOPE_CALLDATA, "calldata second");
    }

    function test_SortsByPathDepth() public pure {
        PolicyCoder.Rule memory shallowRule =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(1))));
        PolicyCoder.Rule memory deepRule =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"00000001", _op1(OpCode.EQ, bytes32(uint256(2))));

        bytes memory blob = PolicyCoder.encode(_twoRules(deepRule, shallowRule), SELECTOR, DESCRIPTOR);

        assertEq(uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_DEPTH_OFFSET]), 1, "depth 1 first");
        uint256 secondRuleStart =
            _firstRuleOffset(DESCRIPTOR.length) + _readU16(blob, _firstRuleOffset(DESCRIPTOR.length));
        assertEq(uint8(blob[secondRuleStart + PF.RULE_DEPTH_OFFSET]), 2, "depth 2 second");
    }

    function test_SortsByPathBytes() public pure {
        PolicyCoder.Rule memory ruleA =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(1))));
        PolicyCoder.Rule memory ruleB =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0001", _op1(OpCode.EQ, bytes32(uint256(2))));

        bytes memory blob = PolicyCoder.encode(_twoRules(ruleB, ruleA), SELECTOR, DESCRIPTOR);

        assertEq(uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET]), 0x00, "path 0x0000 first [0]");
        assertEq(
            uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + 1]), 0x00, "path 0x0000 first [1]"
        );
        uint256 secondRuleStart =
            _firstRuleOffset(DESCRIPTOR.length) + _readU16(blob, _firstRuleOffset(DESCRIPTOR.length));
        assertEq(uint8(blob[secondRuleStart + PF.RULE_PATH_OFFSET]), 0x00, "path 0x0001 second [0]");
        assertEq(uint8(blob[secondRuleStart + PF.RULE_PATH_OFFSET + 1]), 0x01, "path 0x0001 second [1]");
    }

    function test_SortsByOpCode() public pure {
        PolicyCoder.Rule memory ruleEq =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(1))));
        PolicyCoder.Rule memory ruleGt =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.GT, bytes32(uint256(1))));

        bytes memory blob = PolicyCoder.encode(_twoRules(ruleGt, ruleEq), SELECTOR, DESCRIPTOR);

        assertEq(
            uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE]),
            OpCode.EQ,
            "OP_EQ first"
        );
        uint256 secondRuleStart =
            _firstRuleOffset(DESCRIPTOR.length) + _readU16(blob, _firstRuleOffset(DESCRIPTOR.length));
        assertEq(uint8(blob[secondRuleStart + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE]), OpCode.GT, "OP_GT second");
    }

    function test_SortsByOpData() public pure {
        PolicyCoder.Rule memory ruleLow =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(1))));
        PolicyCoder.Rule memory ruleHigh =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(2))));

        bytes memory blob = PolicyCoder.encode(_twoRules(ruleHigh, ruleLow), SELECTOR, DESCRIPTOR);

        uint256 dataStart = _firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE
            + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;
        assertEq(_readBytes32(blob, dataStart), bytes32(uint256(1)), "value 1 first");

        uint256 secondRuleStart =
            _firstRuleOffset(DESCRIPTOR.length) + _readU16(blob, _firstRuleOffset(DESCRIPTOR.length));
        uint256 secondDataStart =
            secondRuleStart + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE + PF.RULE_OPCODE_SIZE + PF.RULE_DATALENGTH_SIZE;
        assertEq(_readBytes32(blob, secondDataStart), bytes32(uint256(2)), "value 2 second");
    }

    function test_SortsByOpDataLength() public pure {
        PolicyCoder.Rule memory shortIn =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.IN, bytes32(uint256(1))));
        PolicyCoder.Rule memory longIn =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op2(OpCode.IN, bytes32(uint256(1)), bytes32(uint256(2))));

        bytes memory blob = PolicyCoder.encode(_twoRules(longIn, shortIn), SELECTOR, DESCRIPTOR);

        assertEq(
            _readU16(
                blob,
                _firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE + PF.RULE_OPCODE_SIZE
            ),
            32
        );
    }

    function test_SortsByPathCommonPrefix() public pure {
        PolicyCoder.Rule memory early =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"000100020003", _op1(OpCode.EQ, bytes32(uint256(1))));
        PolicyCoder.Rule memory later =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"000100020004", _op1(OpCode.EQ, bytes32(uint256(2))));

        bytes memory blob = PolicyCoder.encode(_twoRules(later, early), SELECTOR, DESCRIPTOR);

        assertEq(uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_DEPTH_OFFSET]), 3, "depth 3");
        assertEq(uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + 0]), 0x00, "w0[0]");
        assertEq(uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + 1]), 0x01, "w0[1]");
        assertEq(
            uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + 2 * PF.PATH_STEP_SIZE + 0]),
            0x00,
            "w2[0]"
        );
        assertEq(
            uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + 2 * PF.PATH_STEP_SIZE + 1]),
            0x03,
            "w2[1]"
        );
    }

    function test_SortsByOpCode_WithNotFlag() public pure {
        PolicyCoder.Rule memory plain =
            PolicyCoder.Rule(PF.SCOPE_CALLDATA, hex"0000", _op1(OpCode.EQ, bytes32(uint256(1))));
        PolicyCoder.Rule memory negated = PolicyCoder.Rule(
            PF.SCOPE_CALLDATA, hex"0000", abi.encodePacked(uint8(OpCode.EQ | OpCode.NOT), bytes32(uint256(1)))
        );

        bytes memory blob = PolicyCoder.encode(_twoRules(negated, plain), SELECTOR, DESCRIPTOR);

        assertEq(uint8(blob[_firstRuleOffset(DESCRIPTOR.length) + PF.RULE_PATH_OFFSET + PF.PATH_STEP_SIZE]), OpCode.EQ);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SELECTORLESS ENCODING
    /////////////////////////////////////////////////////////////////////////*/

    function test_SelectorlessHeaderByte() public pure {
        PolicyData memory data;
        data.isSelectorless = true;
        data.selector = bytes4(0);
        data.descriptor = DESCRIPTOR;
        data.groups = _makeOneConstraintGroup();

        bytes memory blob = PolicyCoder.encode(data);

        uint8 header = uint8(blob[PF.POLICY_HEADER_OFFSET]);
        assertEq(header & PF.POLICY_VERSION_MASK, PF.POLICY_VERSION, "version nibble");
        assertTrue((header & PF.FLAG_NO_SELECTOR) != 0, "FLAG_NO_SELECTOR set");
    }

    function test_SelectorlessZeroedSelectorSlot() public pure {
        PolicyData memory data;
        data.isSelectorless = true;
        data.selector = bytes4(0);
        data.descriptor = DESCRIPTOR;
        data.groups = _makeOneConstraintGroup();

        bytes memory blob = PolicyCoder.encode(data);

        assertEq(blob[PF.POLICY_SELECTOR_OFFSET], bytes1(0), "sel[0]");
        assertEq(blob[PF.POLICY_SELECTOR_OFFSET + 1], bytes1(0), "sel[1]");
        assertEq(blob[PF.POLICY_SELECTOR_OFFSET + 2], bytes1(0), "sel[2]");
        assertEq(blob[PF.POLICY_SELECTOR_OFFSET + 3], bytes1(0), "sel[3]");
    }

    function test_SelectorlessZeroesNonZeroSelector() public pure {
        PolicyData memory data;
        data.isSelectorless = true;
        data.selector = bytes4(keccak256("anything()"));
        data.descriptor = DESCRIPTOR;
        data.groups = _makeOneConstraintGroup();

        bytes memory blob = PolicyCoder.encode(data);

        assertEq(blob[PF.POLICY_SELECTOR_OFFSET], bytes1(0), "sel[0]");
        assertEq(blob[PF.POLICY_SELECTOR_OFFSET + 1], bytes1(0), "sel[1]");
        assertEq(blob[PF.POLICY_SELECTOR_OFFSET + 2], bytes1(0), "sel[2]");
        assertEq(blob[PF.POLICY_SELECTOR_OFFSET + 3], bytes1(0), "sel[3]");
    }

    function test_NormalPolicyHeaderUnchanged() public pure {
        PolicyData memory data;
        data.selector = SELECTOR;
        data.descriptor = DESCRIPTOR;
        data.groups = _makeOneConstraintGroup();

        bytes memory blob = PolicyCoder.encode(data);

        assertEq(uint8(blob[PF.POLICY_HEADER_OFFSET]), PF.POLICY_VERSION, "header == version for normal");
    }

    /// @dev Creates a single-constraint group for selectorless policy tests.
    function _makeOneConstraintGroup() internal pure returns (Constraint[][] memory groups) {
        groups = new Constraint[][](1);
        groups[0] = new Constraint[](1);
        bytes[] memory operators = new bytes[](1);
        operators[0] = _op1(OpCode.EQ, bytes32(uint256(42)));
        groups[0][0] = Constraint({ scope: PF.SCOPE_CALLDATA, path: hex"0000", operators: operators });
    }

    /*/////////////////////////////////////////////////////////////////////////
                                ENCODING ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_EmptyPolicy() public {
        PolicyCoder.Group[] memory groups = new PolicyCoder.Group[](0);

        vm.expectRevert(PolicyCoder.EmptyPolicy.selector);
        PolicyCoder.encode(groups, SELECTOR, DESCRIPTOR);
    }

    function test_RevertWhen_EmptyGroup() public {
        PolicyCoder.Group[] memory groups = new PolicyCoder.Group[](1);
        groups[0].rules = new PolicyCoder.Rule[](0);

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.EmptyGroup.selector, 0));
        PolicyCoder.encode(groups, SELECTOR, DESCRIPTOR);
    }

    function test_RevertWhen_InvalidPathBytesZero() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.InvalidPathBytes.selector, 0, 0));
        PolicyCoder.encode(
            _singleRule(PF.SCOPE_CALLDATA, hex"", _op1(OpCode.EQ, bytes32(uint256(42)))), SELECTOR, DESCRIPTOR
        );
    }

    function test_RevertWhen_InvalidPathBytesOdd() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.InvalidPathBytes.selector, 0, 0));
        PolicyCoder.encode(
            _singleRule(PF.SCOPE_CALLDATA, hex"0001ff", _op1(OpCode.EQ, bytes32(uint256(42)))), SELECTOR, DESCRIPTOR
        );
    }

    function test_RevertWhen_InvalidOperatorBytes() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.InvalidOperatorBytes.selector, 0, 0));
        PolicyCoder.encode(_singleRule(PF.SCOPE_CALLDATA, hex"0001", hex""), SELECTOR, DESCRIPTOR);
    }

    function test_RevertWhen_InvalidContextPath() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.InvalidContextPath.selector, 0, 0));
        PolicyCoder.encode(
            _singleRule(PF.SCOPE_CONTEXT, hex"00010002", _op1(OpCode.EQ, bytes32(uint256(42)))), SELECTOR, DESCRIPTOR
        );
    }

    function test_RevertWhen_GroupCountOverflow() public {
        PolicyCoder.Group[] memory groups = new PolicyCoder.Group[](256);
        for (uint256 i; i < 256; ++i) {
            groups[i].rules = new PolicyCoder.Rule[](1);
            groups[i].rules[0] =
                PolicyCoder.Rule(PF.SCOPE_CALLDATA, abi.encodePacked(uint16(i)), _op1(OpCode.EQ, bytes32(uint256(42))));
        }

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.GroupCountOverflow.selector, 256));
        PolicyCoder.encode(groups, SELECTOR, DESCRIPTOR);
    }

    function test_RevertWhen_PathDepthOverflow() public {
        uint256 depth = uint256(type(uint8).max) + 1;
        bytes memory path = new bytes(depth * PF.PATH_STEP_SIZE);
        for (uint256 i; i < depth; ++i) {
            path[i * PF.PATH_STEP_SIZE] = bytes1(uint8(i >> 8));
            path[i * PF.PATH_STEP_SIZE + 1] = bytes1(uint8(i));
        }

        vm.expectRevert(abi.encodeWithSelector(PolicyCoder.PathDepthOverflow.selector, 0, 0, depth));
        PolicyCoder.encode(
            _singleRule(PF.SCOPE_CALLDATA, path, _op1(OpCode.EQ, bytes32(uint256(42)))), SELECTOR, DESCRIPTOR
        );
    }

    function test_RevertWhen_RuleSizeOverflow() public {
        uint256 dataLength = uint256(type(uint16).max) + 1 - (PF.RULE_MIN_SIZE - PF.RULE_DATALENGTH_SIZE);
        bytes memory op = new bytes(dataLength + 1);
        op[0] = bytes1(OpCode.IN);

        vm.expectRevert(
            abi.encodeWithSelector(PolicyCoder.RuleSizeOverflow.selector, 0, 0, PF.RULE_MIN_SIZE + dataLength)
        );
        PolicyCoder.encode(_singleRule(PF.SCOPE_CALLDATA, hex"0000", op), SELECTOR, DESCRIPTOR);
    }
}

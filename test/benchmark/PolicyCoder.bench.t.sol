// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { OpCode } from "src/OpCode.sol";
import { Path } from "src/Path.sol";
import { PolicyCoder } from "src/PolicyCoder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";
import { PolicyCoderHarness } from "test/harnesses/PolicyCoderHarness.sol";

/// @dev Base contract for PolicyCoder benchmarks with pre-built fixtures.
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract PolicyCoderBench is Test {
    bytes4 internal constant SELECTOR = bytes4(keccak256("foo(uint256)"));
    bytes internal constant DESCRIPTOR = hex"";

    PolicyCoderHarness internal harness;

    PolicyCoder.Group[] internal singleGroup1Rule;
    PolicyCoder.Group[] internal singleGroup4Rules;
    PolicyCoder.Group[] internal singleGroup8Rules;
    PolicyCoder.Group[] internal singleGroup16Rules;

    PolicyCoder.Group[] internal twoGroups;
    PolicyCoder.Group[] internal fourGroups;
    PolicyCoder.Group[] internal eightGroups;

    PolicyCoder.Group[] internal pathDepth1;
    PolicyCoder.Group[] internal pathDepth2;
    PolicyCoder.Group[] internal pathDepth4;

    PolicyCoder.Group[] internal dataSize32;
    PolicyCoder.Group[] internal dataSize128;
    PolicyCoder.Group[] internal dataSize256;
    PolicyCoder.Group[] internal dataSize512;

    PolicyCoder.Group[] internal reverseSortedRules;
    PolicyCoder.Group[] internal equalKeyRules;
    PolicyCoder.Group[] internal identicalGroups;

    PolicyCoder.Group[] internal groups32;
    PolicyCoder.Group[] internal groups64;
    PolicyCoder.Group[] internal groups128;
    PolicyCoder.Group[] internal groups255;

    PolicyCoder.Group[] internal contextOnly;
    PolicyCoder.Group[] internal mixedScope;

    PolicyCoder.Group[] internal pathDepth8;
    PolicyCoder.Group[] internal pathDepth16;
    PolicyCoder.Group[] internal longCommonPrefix;

    PolicyCoder.Group[] internal dataSize1024;
    PolicyCoder.Group[] internal dataSize2048;
    PolicyCoder.Group[] internal dataSize4096;

    PolicyCoder.Group[] internal manyRulesPerGroup;
    PolicyCoder.Group[] internal mixedOpCodes;

    // Pre-encoded blobs (for decode benchmarks)
    bytes internal encodedSingleGroup1Rule;
    bytes internal encodedSingleGroup4Rules;
    bytes internal encodedSingleGroup8Rules;
    bytes internal encodedSingleGroup16Rules;

    bytes internal encodedTwoGroups;
    bytes internal encodedFourGroups;
    bytes internal encodedEightGroups;

    bytes internal encodedGroups32;
    bytes internal encodedGroups64;
    bytes internal encodedGroups128;
    bytes internal encodedGroups255;

    bytes internal encodedContextOnly;
    bytes internal encodedMixedScope;

    bytes internal encodedMixedOpCodes;

    function setUp() public virtual {
        harness = new PolicyCoderHarness();
        _buildSingleGroupFixtures();
        _buildMultiGroupFixtures();
        _buildPathDepthFixtures();
        _buildDataSizeFixtures();
        _buildSortingStressFixtures();
        _buildLargeGroupCountFixtures();
        _buildContextScopeFixtures();
        _buildDeepPathFixtures();
        _buildLargePayloadFixtures();
        _buildBoundaryFixtures();
        _buildEncodedFixtures();
    }

    function _buildSingleGroupFixtures() internal {
        singleGroup1Rule = _makeGroups(1, 1);
        singleGroup4Rules = _makeGroups(1, 4);
        singleGroup8Rules = _makeGroups(1, 8);
        singleGroup16Rules = _makeGroups(1, 16);
    }

    function _buildMultiGroupFixtures() internal {
        twoGroups = _makeGroups(2, 2);
        fourGroups = _makeGroups(4, 2);
        eightGroups = _makeGroups(8, 2);
    }

    function _buildPathDepthFixtures() internal {
        pathDepth1 = _makeGroupsWithPath(1, Path.encode(0));
        pathDepth2 = _makeGroupsWithPath(1, Path.encode(0, 1));
        pathDepth4 = _makeGroupsWithPath(1, Path.encode(0, 1, 2, 3));
    }

    function _buildDataSizeFixtures() internal {
        dataSize32 = _makeGroupsWithData(1, _makeEqOp(uint256(42)));
        dataSize128 = _makeGroupsWithData(1, _makeInOp(4));
        dataSize256 = _makeGroupsWithData(1, _makeInOp(8));
        dataSize512 = _makeGroupsWithData(1, _makeInOp(16));
    }

    /// @dev Creates groups with the specified count, each with rulesPerGroup rules.
    function _makeGroups(
        uint256 groupCount,
        uint256 rulesPerGroup
    )
        internal
        pure
        returns (PolicyCoder.Group[] memory groups)
    {
        groups = new PolicyCoder.Group[](groupCount);
        for (uint256 g; g < groupCount; ++g) {
            PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](rulesPerGroup);
            for (uint256 r; r < rulesPerGroup; ++r) {
                rules[r] = PolicyCoder.Rule({
                    scope: PF.SCOPE_CALLDATA, path: Path.encode(uint16(r)), operator: _makeEqOp(uint256(r + 1))
                });
            }
            groups[g] = PolicyCoder.Group({ rules: rules });
        }
    }

    /// @dev Creates a single group with one rule using the specified path.
    function _makeGroupsWithPath(
        uint256 groupCount,
        bytes memory path
    )
        internal
        pure
        returns (PolicyCoder.Group[] memory groups)
    {
        groups = new PolicyCoder.Group[](groupCount);
        for (uint256 g; g < groupCount; ++g) {
            PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](1);
            rules[0] = PolicyCoder.Rule({ scope: PF.SCOPE_CALLDATA, path: path, operator: _makeEqOp(uint256(42)) });
            groups[g] = PolicyCoder.Group({ rules: rules });
        }
    }

    /// @dev Creates a single group with one rule using the specified operator data.
    function _makeGroupsWithData(
        uint256 groupCount,
        bytes memory operator
    )
        internal
        pure
        returns (PolicyCoder.Group[] memory groups)
    {
        groups = new PolicyCoder.Group[](groupCount);
        for (uint256 g; g < groupCount; ++g) {
            PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](1);
            rules[0] = PolicyCoder.Rule({ scope: PF.SCOPE_CALLDATA, path: Path.encode(0), operator: operator });
            groups[g] = PolicyCoder.Group({ rules: rules });
        }
    }

    /// @dev Creates an OP_EQ operator with a single 32-byte value.
    function _makeEqOp(uint256 value) internal pure returns (bytes memory) {
        return abi.encodePacked(OpCode.EQ, bytes32(value));
    }

    /// @dev Creates an OP_IN operator with the specified number of 32-byte set members.
    function _makeInOp(uint256 memberCount) internal pure returns (bytes memory) {
        bytes memory data = abi.encodePacked(OpCode.IN);
        for (uint256 i; i < memberCount; ++i) {
            data = abi.encodePacked(data, bytes32(i + 1));
        }
        return data;
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SORTING STRESS FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    function _buildSortingStressFixtures() internal {
        reverseSortedRules = _makeReverseSortedGroup(16);
        equalKeyRules = _makeEqualKeyGroup(8);
        identicalGroups = _makeIdenticalGroups(4);
    }

    /// @dev Creates a single group with rules in reverse lexicographic path order.
    function _makeReverseSortedGroup(uint256 ruleCount) internal pure returns (PolicyCoder.Group[] memory groups) {
        groups = new PolicyCoder.Group[](1);
        PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](ruleCount);
        for (uint256 i; i < ruleCount; ++i) {
            uint16 pathIndex = uint16(ruleCount - 1 - i);
            rules[i] = PolicyCoder.Rule({
                scope: PF.SCOPE_CALLDATA, path: Path.encode(pathIndex), operator: _makeEqOp(uint256(i + 1))
            });
        }
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /// @dev Creates a single group with rules having the same path but different operators.
    function _makeEqualKeyGroup(uint256 ruleCount) internal pure returns (PolicyCoder.Group[] memory groups) {
        groups = new PolicyCoder.Group[](1);
        PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](ruleCount);
        for (uint256 i; i < ruleCount; ++i) {
            rules[i] = PolicyCoder.Rule({
                scope: PF.SCOPE_CALLDATA, path: Path.encode(0), operator: _makeEqOp(uint256(i + 1))
            });
        }
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /// @dev Creates multiple groups with identical rules (same hash).
    function _makeIdenticalGroups(uint256 groupCount) internal pure returns (PolicyCoder.Group[] memory groups) {
        groups = new PolicyCoder.Group[](groupCount);
        for (uint256 g; g < groupCount; ++g) {
            PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](1);
            rules[0] =
                PolicyCoder.Rule({ scope: PF.SCOPE_CALLDATA, path: Path.encode(0), operator: _makeEqOp(uint256(42)) });
            groups[g] = PolicyCoder.Group({ rules: rules });
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                            LARGE GROUP COUNT FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    function _buildLargeGroupCountFixtures() internal {
        groups32 = _makeGroups(32, 1);
        groups64 = _makeGroups(64, 1);
        groups128 = _makeGroups(128, 1);
        groups255 = _makeGroups(255, 1);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              CONTEXT SCOPE FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    function _buildContextScopeFixtures() internal {
        contextOnly = _makeContextOnlyGroup();
        mixedScope = _makeMixedScopeGroup();
    }

    /// @dev Creates a single group with context-scope rules only.
    function _makeContextOnlyGroup() internal pure returns (PolicyCoder.Group[] memory groups) {
        groups = new PolicyCoder.Group[](1);
        PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](4);
        rules[0] = PolicyCoder.Rule({
            scope: PF.SCOPE_CONTEXT,
            path: Path.encode(PF.CTX_MSG_SENDER),
            operator: _makeEqOp(uint256(uint160(address(1))))
        });
        rules[1] = PolicyCoder.Rule({
            scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_MSG_VALUE), operator: _makeEqOp(uint256(0))
        });
        rules[2] = PolicyCoder.Rule({
            scope: PF.SCOPE_CONTEXT,
            path: Path.encode(PF.CTX_BLOCK_TIMESTAMP),
            operator: abi.encodePacked(OpCode.GT, bytes32(uint256(1000)))
        });
        rules[3] = PolicyCoder.Rule({
            scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_CHAIN_ID), operator: _makeEqOp(uint256(1))
        });
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /// @dev Creates a single group with both context and calldata scope rules.
    function _makeMixedScopeGroup() internal pure returns (PolicyCoder.Group[] memory groups) {
        groups = new PolicyCoder.Group[](1);
        PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](4);
        rules[0] = PolicyCoder.Rule({
            scope: PF.SCOPE_CONTEXT,
            path: Path.encode(PF.CTX_MSG_SENDER),
            operator: _makeEqOp(uint256(uint160(address(1))))
        });
        rules[1] =
            PolicyCoder.Rule({ scope: PF.SCOPE_CALLDATA, path: Path.encode(0), operator: _makeEqOp(uint256(100)) });
        rules[2] = PolicyCoder.Rule({
            scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_MSG_VALUE), operator: _makeEqOp(uint256(0))
        });
        rules[3] =
            PolicyCoder.Rule({ scope: PF.SCOPE_CALLDATA, path: Path.encode(1), operator: _makeEqOp(uint256(200)) });
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /*/////////////////////////////////////////////////////////////////////////
                                DEEP PATH FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    function _buildDeepPathFixtures() internal {
        pathDepth8 = _makeGroupsWithPath(1, _makeDeepPath(8));
        pathDepth16 = _makeGroupsWithPath(1, _makeDeepPath(16));
        longCommonPrefix = _makeLongCommonPrefixGroup();
    }

    /// @dev Creates a path of specified depth with incrementing indices.
    function _makeDeepPath(uint256 depth) internal pure returns (bytes memory) {
        uint16[] memory steps = new uint16[](depth);
        for (uint256 i; i < depth; ++i) {
            steps[i] = uint16(i);
        }
        return Path.encode(steps);
    }

    /// @dev Creates a group with rules sharing a long common prefix but differing at the end.
    function _makeLongCommonPrefixGroup() internal pure returns (PolicyCoder.Group[] memory groups) {
        groups = new PolicyCoder.Group[](1);
        PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](4);
        bytes memory basePath = _makeDeepPath(6);
        for (uint256 i; i < 4; ++i) {
            bytes memory fullPath = new bytes(14);
            for (uint256 j; j < 12; ++j) {
                fullPath[j] = basePath[j];
            }
            uint16 suffix = uint16(i);
            fullPath[12] = bytes1(uint8(suffix >> 8));
            fullPath[13] = bytes1(uint8(suffix));
            rules[i] =
                PolicyCoder.Rule({ scope: PF.SCOPE_CALLDATA, path: fullPath, operator: _makeEqOp(uint256(i + 1)) });
        }
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /*/////////////////////////////////////////////////////////////////////////
                            LARGE PAYLOAD FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    function _buildLargePayloadFixtures() internal {
        dataSize1024 = _makeGroupsWithData(1, _makeInOp(32));
        dataSize2048 = _makeGroupsWithData(1, _makeInOp(64));
        dataSize4096 = _makeGroupsWithData(1, _makeInOp(128));
    }

    /*/////////////////////////////////////////////////////////////////////////
                              BOUNDARY FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    function _buildBoundaryFixtures() internal {
        manyRulesPerGroup = _makeGroups(1, 100);
        mixedOpCodes = _makeMixedOpCodesGroup();
    }

    /// @dev Creates a single group with various operator types.
    function _makeMixedOpCodesGroup() internal pure returns (PolicyCoder.Group[] memory groups) {
        groups = new PolicyCoder.Group[](1);
        PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](6);
        rules[0] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA, path: Path.encode(0), operator: abi.encodePacked(OpCode.EQ, bytes32(uint256(100)))
        });
        rules[1] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA, path: Path.encode(1), operator: abi.encodePacked(OpCode.GT, bytes32(uint256(50)))
        });
        rules[2] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA, path: Path.encode(2), operator: abi.encodePacked(OpCode.LT, bytes32(uint256(200)))
        });
        rules[3] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA, path: Path.encode(3), operator: abi.encodePacked(OpCode.GTE, bytes32(uint256(10)))
        });
        rules[4] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA,
            path: Path.encode(4),
            operator: abi.encodePacked(OpCode.BETWEEN, bytes32(uint256(0)), bytes32(uint256(1000)))
        });
        rules[5] = PolicyCoder.Rule({ scope: PF.SCOPE_CALLDATA, path: Path.encode(5), operator: _makeInOp(4) });
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /*/////////////////////////////////////////////////////////////////////////
                          PRE-ENCODED BLOB FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    function _buildEncodedFixtures() internal {
        encodedSingleGroup1Rule = harness.encode(singleGroup1Rule, SELECTOR, DESCRIPTOR);
        encodedSingleGroup4Rules = harness.encode(singleGroup4Rules, SELECTOR, DESCRIPTOR);
        encodedSingleGroup8Rules = harness.encode(singleGroup8Rules, SELECTOR, DESCRIPTOR);
        encodedSingleGroup16Rules = harness.encode(singleGroup16Rules, SELECTOR, DESCRIPTOR);

        encodedTwoGroups = harness.encode(twoGroups, SELECTOR, DESCRIPTOR);
        encodedFourGroups = harness.encode(fourGroups, SELECTOR, DESCRIPTOR);
        encodedEightGroups = harness.encode(eightGroups, SELECTOR, DESCRIPTOR);

        encodedGroups32 = harness.encode(groups32, SELECTOR, DESCRIPTOR);
        encodedGroups64 = harness.encode(groups64, SELECTOR, DESCRIPTOR);
        encodedGroups128 = harness.encode(groups128, SELECTOR, DESCRIPTOR);
        encodedGroups255 = harness.encode(groups255, SELECTOR, DESCRIPTOR);

        encodedContextOnly = harness.encode(contextOnly, SELECTOR, DESCRIPTOR);
        encodedMixedScope = harness.encode(mixedScope, SELECTOR, DESCRIPTOR);

        encodedMixedOpCodes = harness.encode(mixedOpCodes, SELECTOR, DESCRIPTOR);
    }
}

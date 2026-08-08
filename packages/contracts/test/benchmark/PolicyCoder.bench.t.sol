// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { DescriptorBuilder, DescriptorDraft } from "src/DescriptorBuilder.sol";
import { OpCode } from "src/OpCode.sol";
import { Path } from "src/Path.sol";
import { Policy } from "src/Policy.sol";
import { PolicyCoder, PolicyData } from "src/PolicyCoder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";
import { TypeDesc } from "src/TypeDesc.sol";
import { PolicyCoderHarness } from "test/harnesses/PolicyCoderHarness.sol";

/// @dev Base contract for PolicyCoder benchmarks with pre-built fixtures.
abstract contract PolicyCoderBench is Test {
    /// @dev Selector written into every encoded policy header. The fixtures pair it with a wide,
    /// deeply nested descriptor rather than the signature it hashes, because encoding cost does not
    /// depend on which selector the header carries.
    bytes4 internal constant SELECTOR = bytes4(keccak256("foo(uint256)"));

    /// @dev Nesting depth of the first parameter, which every deep-path fixture descends.
    uint256 internal constant NESTING_DEPTH = 16;

    /// @dev Field index that descends one nesting level; the other fields of a level terminate.
    uint16 internal constant DESCEND_FIELD = 1;

    /// @dev Top-level parameter count: the nested first parameter, then one elementary parameter
    /// per rule the widest fixture addresses.
    uint256 internal constant PARAM_COUNT = 101;

    PolicyCoderHarness internal harness;

    bytes internal descriptorBlob;

    PolicyCoder.Group[] internal singleGroup1Rule;
    PolicyCoder.Group[] internal singleGroup4Rules;
    PolicyCoder.Group[] internal singleGroup8Rules;
    PolicyCoder.Group[] internal singleGroup16Rules;

    PolicyCoder.Group[] internal twoGroups;
    PolicyCoder.Group[] internal fourGroups;
    PolicyCoder.Group[] internal eightGroups;

    PolicyCoder.Group[] internal pathDepth2;
    PolicyCoder.Group[] internal pathDepth4;

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

    // Pre-encoded blobs (for decode benchmarks).
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
        descriptorBlob = _buildDescriptor();
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

    /*/////////////////////////////////////////////////////////////////////////
                              SNAPSHOT HELPERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Snapshots the harness call just made and rejects a blob that is not well-formed, so a
    /// fixture that stops encoding what its name claims fails instead of recording a number.
    function _benchEncode(bytes memory policy, string memory name) internal {
        vm.snapshotGasLastCall("PolicyCoder.encode", name);
        Policy.validate(policy);
    }

    /// @dev Snapshots the harness call just made and pins the group count the fixture encodes.
    function _benchDecode(PolicyData memory data, string memory name, uint256 expectedGroups) internal {
        vm.snapshotGasLastCall("PolicyCoder.decode", name);
        assertEq(data.groups.length, expectedGroups);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 DESCRIPTOR
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Builds the descriptor every fixture path navigates: a nested first parameter that
    /// descends through one field of each level, followed by elementary parameters.
    function _buildDescriptor() internal pure returns (bytes memory) {
        bytes memory nested =
            TypeDesc.tuple_(TypeDesc.uint256_(), TypeDesc.uint256_(), TypeDesc.uint256_(), TypeDesc.uint256_());
        for (uint256 i = 1; i < NESTING_DEPTH; ++i) {
            nested = TypeDesc.tuple_(TypeDesc.uint256_(), nested, TypeDesc.uint256_(), TypeDesc.uint256_());
        }

        DescriptorDraft memory draft = DescriptorBuilder.create().add(nested);
        for (uint256 i = 1; i < PARAM_COUNT; ++i) {
            draft = draft.add(TypeDesc.uint256_());
        }
        return draft.build();
    }

    /*/////////////////////////////////////////////////////////////////////////
                               CORE FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Populates single-group fixtures varying rule count.
    function _buildSingleGroupFixtures() internal {
        singleGroup1Rule = _makeGroups(1, 1);
        singleGroup4Rules = _makeGroups(1, 4);
        singleGroup8Rules = _makeGroups(1, 8);
        singleGroup16Rules = _makeGroups(1, 16);
    }

    /// @dev Populates multi-group fixtures varying group count.
    function _buildMultiGroupFixtures() internal {
        twoGroups = _makeGroups(2, 2);
        fourGroups = _makeGroups(4, 2);
        eightGroups = _makeGroups(8, 2);
    }

    /// @dev Populates fixtures varying path depth.
    function _buildPathDepthFixtures() internal {
        pathDepth2 = _makeGroupsWithPath(_makeDeepPath(2));
        pathDepth4 = _makeGroupsWithPath(_makeDeepPath(4));
    }

    /// @dev Populates fixtures varying operator data size.
    function _buildDataSizeFixtures() internal {
        dataSize128 = _makeGroupsWithData(_makeInOp(4));
        dataSize256 = _makeGroupsWithData(_makeInOp(8));
        dataSize512 = _makeGroupsWithData(_makeInOp(16));
    }

    /*/////////////////////////////////////////////////////////////////////////
                             GROUP CONSTRUCTION
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Creates groups with the specified count, each with rulesPerGroup rules. Operands are
    /// seeded from both indices, so the groups hash distinctly and the canonicalization sort runs
    /// on the distinct keys a real policy presents rather than on an all-equal degenerate input.
    /// `identicalGroups` covers the equal-key case deliberately.
    function _makeGroups(
        uint256 groupCount,
        uint256 rulesPerGroup
    )
        internal
        pure
        returns (PolicyCoder.Group[] memory groups)
    {
        groups = new PolicyCoder.Group[](groupCount);
        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](rulesPerGroup);
            for (uint256 ruleIndex; ruleIndex < rulesPerGroup; ++ruleIndex) {
                rules[ruleIndex] = PolicyCoder.Rule({
                    scope: PF.SCOPE_CALLDATA,
                    // forge-lint: disable-next-line(unsafe-typecast) loop bound is the rule count
                    path: Path.encode(uint16(ruleIndex + 1)),
                    operator: _makeEqOp(groupIndex * rulesPerGroup + ruleIndex + 1),
                    hint: ""
                });
            }
            groups[groupIndex] = PolicyCoder.Group({ rules: rules });
        }
    }

    /// @dev Creates a single group with one rule using the specified path.
    function _makeGroupsWithPath(bytes memory path) internal pure returns (PolicyCoder.Group[] memory groups) {
        PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](1);
        rules[0] =
            PolicyCoder.Rule({ scope: PF.SCOPE_CALLDATA, path: path, operator: _makeEqOp(uint256(42)), hint: "" });
        groups = new PolicyCoder.Group[](1);
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /// @dev Creates a single group with one rule using the specified operator data.
    function _makeGroupsWithData(bytes memory operator) internal pure returns (PolicyCoder.Group[] memory groups) {
        PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](1);
        rules[0] = PolicyCoder.Rule({ scope: PF.SCOPE_CALLDATA, path: Path.encode(1), operator: operator, hint: "" });
        groups = new PolicyCoder.Group[](1);
        groups[0] = PolicyCoder.Group({ rules: rules });
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

    /// @dev Populates fixtures that stress canonicalization sort paths.
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
            // forge-lint: disable-next-line(unsafe-typecast) loop bound is the rule count
            uint16 pathIndex = uint16(ruleCount - 1 - i);
            rules[i] = PolicyCoder.Rule({
                scope: PF.SCOPE_CALLDATA,
                path: Path.encode(pathIndex + 1),
                operator: _makeEqOp(uint256(i + 1)),
                hint: ""
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
                scope: PF.SCOPE_CALLDATA, path: Path.encode(1), operator: _makeEqOp(uint256(i + 1)), hint: ""
            });
        }
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /// @dev Creates multiple groups with identical rules (same hash).
    function _makeIdenticalGroups(uint256 groupCount) internal pure returns (PolicyCoder.Group[] memory groups) {
        groups = new PolicyCoder.Group[](groupCount);
        for (uint256 groupIndex; groupIndex < groupCount; ++groupIndex) {
            PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](1);
            rules[0] = PolicyCoder.Rule({
                scope: PF.SCOPE_CALLDATA, path: Path.encode(1), operator: _makeEqOp(uint256(42)), hint: ""
            });
            groups[groupIndex] = PolicyCoder.Group({ rules: rules });
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                            LARGE GROUP COUNT FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Populates fixtures with large group counts up to the format maximum.
    function _buildLargeGroupCountFixtures() internal {
        groups32 = _makeGroups(32, 1);
        groups64 = _makeGroups(64, 1);
        groups128 = _makeGroups(128, 1);
        groups255 = _makeGroups(255, 1);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              CONTEXT SCOPE FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Populates context-scope and mixed-scope fixtures.
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
            operator: _makeEqOp(uint256(uint160(address(1)))),
            hint: ""
        });
        rules[1] = PolicyCoder.Rule({
            scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_MSG_VALUE), operator: _makeEqOp(uint256(0)), hint: ""
        });
        rules[2] = PolicyCoder.Rule({
            scope: PF.SCOPE_CONTEXT,
            path: Path.encode(PF.CTX_BLOCK_TIMESTAMP),
            operator: abi.encodePacked(OpCode.GT, bytes32(uint256(1000))),
            hint: ""
        });
        rules[3] = PolicyCoder.Rule({
            scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_CHAIN_ID), operator: _makeEqOp(uint256(1)), hint: ""
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
            operator: _makeEqOp(uint256(uint160(address(1)))),
            hint: ""
        });
        rules[1] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA, path: Path.encode(1), operator: _makeEqOp(uint256(100)), hint: ""
        });
        rules[2] = PolicyCoder.Rule({
            scope: PF.SCOPE_CONTEXT, path: Path.encode(PF.CTX_MSG_VALUE), operator: _makeEqOp(uint256(0)), hint: ""
        });
        rules[3] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA, path: Path.encode(2), operator: _makeEqOp(uint256(200)), hint: ""
        });
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /*/////////////////////////////////////////////////////////////////////////
                                DEEP PATH FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Populates fixtures with deep paths and long common-prefix rules.
    function _buildDeepPathFixtures() internal {
        pathDepth8 = _makeGroupsWithPath(_makeDeepPath(8));
        pathDepth16 = _makeGroupsWithPath(_makeDeepPath(16));
        longCommonPrefix = _makeLongCommonPrefixGroup();
    }

    /// @dev Creates a path of the specified depth descending the nested first parameter and
    /// resting on an elementary field, which is what an operator can address.
    function _makeDeepPath(uint256 depth) internal pure returns (bytes memory) {
        uint16[] memory steps = new uint16[](depth);
        for (uint256 i = 1; i + 1 < depth; ++i) {
            steps[i] = DESCEND_FIELD;
        }
        return Path.encode(steps);
    }

    /// @dev Creates a path that descends every level of the nested first parameter, resting on the
    /// innermost tuple. Every field of that tuple is elementary, so any step extends it.
    function _makeDescentPath(uint256 depth) internal pure returns (bytes memory) {
        uint16[] memory steps = new uint16[](depth);
        for (uint256 i = 1; i < depth; ++i) {
            steps[i] = DESCEND_FIELD;
        }
        return Path.encode(steps);
    }

    /// @dev Creates a group with rules sharing a long common prefix but differing at the end.
    function _makeLongCommonPrefixGroup() internal pure returns (PolicyCoder.Group[] memory groups) {
        groups = new PolicyCoder.Group[](1);
        PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](4);
        bytes memory basePath = _makeDescentPath(NESTING_DEPTH);
        uint256 prefixBytes = basePath.length;
        for (uint256 i; i < 4; ++i) {
            bytes memory fullPath = new bytes(prefixBytes + PF.PATH_STEP_SIZE);
            for (uint256 j; j < prefixBytes; ++j) {
                fullPath[j] = basePath[j];
            }
            // forge-lint: disable-next-line(unsafe-typecast) loop bound is 4
            uint16 suffix = uint16(i);
            // forge-lint: disable-next-line(unsafe-typecast) deliberate big-endian split of a uint16
            fullPath[prefixBytes] = bytes1(uint8(suffix >> 8));
            // forge-lint: disable-next-line(unsafe-typecast) deliberate big-endian split of a uint16
            fullPath[prefixBytes + 1] = bytes1(uint8(suffix));
            rules[i] = PolicyCoder.Rule({
                scope: PF.SCOPE_CALLDATA, path: fullPath, operator: _makeEqOp(uint256(i + 1)), hint: ""
            });
        }
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /*/////////////////////////////////////////////////////////////////////////
                            LARGE PAYLOAD FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Populates fixtures with large IN operator payloads.
    function _buildLargePayloadFixtures() internal {
        dataSize1024 = _makeGroupsWithData(_makeInOp(32));
        dataSize2048 = _makeGroupsWithData(_makeInOp(64));
        dataSize4096 = _makeGroupsWithData(_makeInOp(128));
    }

    /*/////////////////////////////////////////////////////////////////////////
                              BOUNDARY FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Populates boundary-condition fixtures (high rule count, mixed operators).
    function _buildBoundaryFixtures() internal {
        manyRulesPerGroup = _makeGroups(1, 100);
        mixedOpCodes = _makeMixedOpCodesGroup();
    }

    /// @dev Creates a single group with various operator types.
    function _makeMixedOpCodesGroup() internal pure returns (PolicyCoder.Group[] memory groups) {
        groups = new PolicyCoder.Group[](1);
        PolicyCoder.Rule[] memory rules = new PolicyCoder.Rule[](6);
        rules[0] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA,
            path: Path.encode(1),
            operator: abi.encodePacked(OpCode.EQ, bytes32(uint256(100))),
            hint: ""
        });
        rules[1] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA,
            path: Path.encode(2),
            operator: abi.encodePacked(OpCode.GT, bytes32(uint256(50))),
            hint: ""
        });
        rules[2] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA,
            path: Path.encode(3),
            operator: abi.encodePacked(OpCode.LT, bytes32(uint256(200))),
            hint: ""
        });
        rules[3] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA,
            path: Path.encode(4),
            operator: abi.encodePacked(OpCode.GTE, bytes32(uint256(10))),
            hint: ""
        });
        rules[4] = PolicyCoder.Rule({
            scope: PF.SCOPE_CALLDATA,
            path: Path.encode(5),
            operator: abi.encodePacked(OpCode.BETWEEN, bytes32(uint256(0)), bytes32(uint256(1000))),
            hint: ""
        });
        rules[5] =
            PolicyCoder.Rule({ scope: PF.SCOPE_CALLDATA, path: Path.encode(6), operator: _makeInOp(4), hint: "" });
        groups[0] = PolicyCoder.Group({ rules: rules });
    }

    /*/////////////////////////////////////////////////////////////////////////
                          PRE-ENCODED BLOB FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Pre-encodes all group fixtures into policy blobs for decode benchmarks.
    function _buildEncodedFixtures() internal {
        encodedSingleGroup1Rule = harness.encode(singleGroup1Rule, SELECTOR, descriptorBlob);
        encodedSingleGroup4Rules = harness.encode(singleGroup4Rules, SELECTOR, descriptorBlob);
        encodedSingleGroup8Rules = harness.encode(singleGroup8Rules, SELECTOR, descriptorBlob);
        encodedSingleGroup16Rules = harness.encode(singleGroup16Rules, SELECTOR, descriptorBlob);

        encodedTwoGroups = harness.encode(twoGroups, SELECTOR, descriptorBlob);
        encodedFourGroups = harness.encode(fourGroups, SELECTOR, descriptorBlob);
        encodedEightGroups = harness.encode(eightGroups, SELECTOR, descriptorBlob);

        encodedGroups32 = harness.encode(groups32, SELECTOR, descriptorBlob);
        encodedGroups64 = harness.encode(groups64, SELECTOR, descriptorBlob);
        encodedGroups128 = harness.encode(groups128, SELECTOR, descriptorBlob);
        encodedGroups255 = harness.encode(groups255, SELECTOR, descriptorBlob);

        encodedContextOnly = harness.encode(contextOnly, SELECTOR, descriptorBlob);
        encodedMixedScope = harness.encode(mixedScope, SELECTOR, descriptorBlob);

        encodedMixedOpCodes = harness.encode(mixedOpCodes, SELECTOR, descriptorBlob);
    }
}

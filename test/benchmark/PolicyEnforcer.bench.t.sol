// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { arg, blockNumber, blockTimestamp, chainId, msgSender, msgValue } from "src/Constraint.sol";
import { Path } from "src/Path.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";

import { PolicyEnforcerTest } from "test/unit/PolicyEnforcer.t.sol";

/// @dev Base contract for PolicyEnforcer benchmarks.
// forge-lint: disable-next-item(unsafe-typecast)
// forgefmt: disable-next-item
abstract contract PolicyEnforcerBench is PolicyEnforcerTest {
    /// @dev Fixture for a single benchmark scenario.
    struct Fixture {
        bytes policy;
        bytes callData;
    }

    /*/////////////////////////////////////////////////////////////////////////
                              GROUP SCALING FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    Fixture internal groups1Pass;
    Fixture internal groups2PassEarly;
    Fixture internal groups2PassLate;
    Fixture internal groups4PassEarly;
    Fixture internal groups4PassLate;
    Fixture internal groups8PassEarly;
    Fixture internal groups8PassLate;
    Fixture internal groups16PassEarly;
    Fixture internal groups16PassLate;

    /*/////////////////////////////////////////////////////////////////////////
                              RULE SCALING FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    Fixture internal rules1Pass;
    Fixture internal rules4AllPass;
    Fixture internal rules4FailFirst;
    Fixture internal rules4FailLast;
    Fixture internal rules8AllPass;
    Fixture internal rules8FailMiddle;
    Fixture internal rules16AllPass;
    Fixture internal rules32AllPass;

    /*/////////////////////////////////////////////////////////////////////////
                              PATH DEPTH FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    Fixture internal depth1Elementary;
    Fixture internal depth2StructField;
    Fixture internal depth3NestedStruct;
    Fixture internal depth4DeepNested;
    Fixture internal depth8VeryDeep;
    Fixture internal depth2ArrayElem;
    Fixture internal depth3ArrayStructField;

    /*/////////////////////////////////////////////////////////////////////////
                              LCP BENEFIT FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    Fixture internal lcpNone4Rules;
    Fixture internal lcp1Shared4Rules;
    Fixture internal lcp3Deep4Rules;
    Fixture internal lcpIdenticalPaths;

    /*/////////////////////////////////////////////////////////////////////////
                              OPERATOR FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    Fixture internal opEq;
    Fixture internal opGt;
    Fixture internal opLt;
    Fixture internal opGte;
    Fixture internal opLte;
    Fixture internal opBetween;
    Fixture internal opIn2;
    Fixture internal opIn4;
    Fixture internal opIn6;
    Fixture internal opIn8;
    Fixture internal opIn16;
    Fixture internal opIn32;
    Fixture internal opIn64;
    Fixture internal opIn128;
    Fixture internal opBitmaskAll;
    Fixture internal opBitmaskAny;
    Fixture internal opBitmaskNone;
    Fixture internal opNotEq;
    Fixture internal opNotIn4;

    /*/////////////////////////////////////////////////////////////////////////
                              SCOPE FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    Fixture internal scopeCalldataOnly;
    Fixture internal scopeContextOnly;
    Fixture internal scopeMixed;
    Fixture internal scopeCtxMsgSender;
    Fixture internal scopeCtxMsgValue;
    Fixture internal scopeCtxTimestamp;
    Fixture internal scopeCtxBlockNumber;
    Fixture internal scopeCtxChainId;

    /*/////////////////////////////////////////////////////////////////////////
                              VALUE TYPE FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    Fixture internal typeElementary;
    Fixture internal typeAddress;
    Fixture internal typeBytes32;
    Fixture internal typeStaticStruct;
    Fixture internal typeDynStructStatic;
    Fixture internal typeArrayElement;
    Fixture internal typeStaticArrayElem;
    Fixture internal typeLargeTupleField;

    /*/////////////////////////////////////////////////////////////////////////
                              LENGTH OPERATOR FIXTURES
    /////////////////////////////////////////////////////////////////////////*/

    Fixture internal lengthEqDynArray;
    Fixture internal lengthGtDynArray;
    Fixture internal lengthBetweenBytes;
    Fixture internal lengthLtBytesEmpty;

    function setUp() public virtual override {
        super.setUp();
        _buildGroupScalingFixtures();
        _buildRuleScalingFixtures();
        _buildPathDepthFixtures();
        _buildLcpFixtures();
        _buildOperatorFixtures();
        _buildScopeFixtures();
        _buildValueTypeFixtures();
        _buildLengthOpFixtures();
    }

    /*/////////////////////////////////////////////////////////////////////////
                              GROUP SCALING BUILDERS
    /////////////////////////////////////////////////////////////////////////*/

    function _buildGroupScalingFixtures() internal {
        groups1Pass = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).eq(uint256(42))),
            abi.encodeWithSignature("foo(uint256)", uint256(42))
        );

        groups2PassEarly = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).eq(uint256(42)))
                .or()
                .add(arg(0).eq(uint256(100))),
            abi.encodeWithSignature("foo(uint256)", uint256(42))
        );

        groups2PassLate = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).eq(uint256(42)))
                .or()
                .add(arg(0).eq(uint256(100))),
            abi.encodeWithSignature("foo(uint256)", uint256(100))
        );

        groups4PassEarly = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).eq(uint256(42)))
                .or()
                .add(arg(0).eq(uint256(142)))
                .or()
                .add(arg(0).eq(uint256(242)))
                .or()
                .add(arg(0).eq(uint256(342))),
            abi.encodeWithSignature("foo(uint256)", uint256(42))
        );

        groups4PassLate = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).eq(uint256(42)))
                .or()
                .add(arg(0).eq(uint256(142)))
                .or()
                .add(arg(0).eq(uint256(242)))
                .or()
                .add(arg(0).eq(uint256(342))),
            abi.encodeWithSignature("foo(uint256)", uint256(342))
        );

        groups8PassEarly = _buildGroupsN(8, 42);
        groups8PassLate = _buildGroupsN(8, 742);
        groups16PassEarly = _buildGroupsN(16, 42);
        groups16PassLate = _buildGroupsN(16, 1542);
    }

    function _buildGroupsN(uint256 count, uint256 passingValue) internal pure returns (Fixture memory) {
        PolicyDraft memory draft = PolicyBuilder.create("foo(uint256)");
        for (uint256 i; i < count; ++i) {
            if (i > 0) draft = draft.or();
            draft = draft.add(arg(0).eq(42 + i * 100));
        }
        return Fixture({ policy: draft.buildUnsafe(), callData: abi.encodeWithSignature("foo(uint256)", passingValue) });
    }

    /*/////////////////////////////////////////////////////////////////////////
                              RULE SCALING BUILDERS
    /////////////////////////////////////////////////////////////////////////*/

    function _buildRuleScalingFixtures() internal {
        rules1Pass = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).eq(uint256(42))),
            abi.encodeWithSignature("foo(uint256)", uint256(42))
        );

        rules4AllPass = _buildRulesNWithCalldata(4, _u(1, 2, 3, 4));
        rules4FailFirst = _buildRulesNWithCalldata(4, _u(999, 2, 3, 4));
        rules4FailLast = _buildRulesNWithCalldata(4, _u(1, 2, 3, 999));
        rules8AllPass = _buildRulesNWithCalldata(8, _u(1, 2, 3, 4, 5, 6, 7, 8));
        rules8FailMiddle = _buildRulesNWithCalldata(8, _u(1, 2, 3, 4, 999, 6, 7, 8));
        rules16AllPass = _buildRulesN(16);
        rules32AllPass = _buildRulesN(32);
    }

    function _buildRulesN(uint256 count) internal pure returns (Fixture memory) {
        string memory sig = _tupleSignature(count);
        PolicyDraft memory draft = PolicyBuilder.create(sig);
        for (uint256 i; i < count; ++i) {
            draft = draft.add(arg(0, uint16(i)).eq(i + 1));
        }
        return Fixture({ policy: draft.buildUnsafe(), callData: _encodeTupleCalldata(sig, count) });
    }

    function _buildRulesNWithCalldata(uint256 count, uint256[] memory values) internal pure returns (Fixture memory) {
        string memory sig = _tupleSignature(count);
        PolicyDraft memory draft = PolicyBuilder.create(sig);
        for (uint256 i; i < count; ++i) {
            draft = draft.add(arg(0, uint16(i)).eq(i + 1));
        }
        bytes memory callData = abi.encodeWithSignature(sig);
        for (uint256 i; i < values.length; ++i) {
            callData = abi.encodePacked(callData, bytes32(values[i]));
        }
        return Fixture({ policy: draft.buildUnsafe(), callData: callData });
    }

    function _tupleSignature(uint256 count) internal pure returns (string memory) {
        bytes memory fields;
        for (uint256 i; i < count; ++i) {
            if (i > 0) fields = abi.encodePacked(fields, ",");
            fields = abi.encodePacked(fields, "uint256");
        }
        return string(abi.encodePacked("foo((", fields, "))"));
    }

    function _encodeTupleCalldata(string memory sig, uint256 count) internal pure returns (bytes memory) {
        bytes memory data = abi.encodeWithSignature(sig);
        for (uint256 i; i < count; ++i) {
            data = abi.encodePacked(data, bytes32(i + 1));
        }
        return data;
    }

    function _u(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](4);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
    }

    function _u(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d,
        uint256 e,
        uint256 f,
        uint256 g,
        uint256 h
    )
        internal
        pure
        returns (uint256[] memory arr)
    {
        arr = new uint256[](8);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        arr[4] = e;
        arr[5] = f;
        arr[6] = g;
        arr[7] = h;
    }

    /*/////////////////////////////////////////////////////////////////////////
                              PATH DEPTH BUILDERS
    /////////////////////////////////////////////////////////////////////////*/

    function _buildPathDepthFixtures() internal {
        depth1Elementary = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).eq(uint256(42))),
            abi.encodeWithSignature("foo(uint256)", uint256(42))
        );

        depth2StructField = _buildFixture(
            PolicyBuilder.create("foo((address,uint256))")
                .add(arg(0, 1).eq(uint256(42))),
            _encodeStruct2(address(1), 42)
        );

        depth3NestedStruct = _buildFixture(
            PolicyBuilder.create("foo(((address,uint256),uint256))")
                .add(arg(0, 0, 1).eq(uint256(42))),
            _encodeNestedStruct3(address(1), 42, 100)
        );

        depth4DeepNested = _buildFixture(
            PolicyBuilder.create("foo((((address,uint256),uint256),uint256))")
                .add(arg(0, 0, 0, 1).eq(uint256(42))),
            _encodeNestedStruct4(address(1), 42, 100, 200)
        );

        depth8VeryDeep = _buildDeepNested(8);

        uint256[] memory arr = new uint256[](10);
        for (uint256 i; i < 10; ++i) {
            arr[i] = i + 1;
        }
        depth2ArrayElem = _buildFixture(
            PolicyBuilder.create("foo(uint256[])")
                .add(arg(0, 5).eq(uint256(6))),
            abi.encodeWithSignature("foo(uint256[])", arr)
        );

        depth3ArrayStructField = _buildArrayStruct();
    }

    function _encodeNestedStruct4(
        address addr,
        uint256 val1,
        uint256 val2,
        uint256 val3
    )
        internal
        pure
        returns (bytes memory)
    {
        bytes memory data = abi.encodeWithSignature("foo((((address,uint256),uint256),uint256))");
        return abi.encodePacked(data, bytes32(uint256(uint160(addr))), bytes32(val1), bytes32(val2), bytes32(val3));
    }

    function _buildDeepNested(uint256 depth) internal pure returns (Fixture memory) {
        bytes memory innerTypes = bytes("address,uint256");
        for (uint256 i = 2; i < depth; ++i) {
            innerTypes = abi.encodePacked("(", innerTypes, "),uint256");
        }
        string memory sig = string(abi.encodePacked("foo((", innerTypes, "))"));

        PolicyDraft memory draft = PolicyBuilder.create(sig);
        uint16[] memory pathSteps = new uint16[](depth);
        for (uint256 i; i < depth - 1; ++i) {
            pathSteps[i] = 0;
        }
        pathSteps[depth - 1] = 1;
        draft = draft.add(arg(Path.encode(pathSteps)).eq(uint256(42)));

        bytes memory callData = abi.encodeWithSignature(sig);
        callData = abi.encodePacked(callData, bytes32(uint256(uint160(address(1)))));
        callData = abi.encodePacked(callData, bytes32(uint256(42)));
        for (uint256 i = 2; i < depth; ++i) {
            callData = abi.encodePacked(callData, bytes32(i + 1));
        }

        return Fixture({ policy: draft.buildUnsafe(), callData: callData });
    }

    function _buildArrayStruct() internal pure returns (Fixture memory) {
        bytes memory policy = PolicyBuilder.create("foo((uint256,address)[])")
            .add(arg(0, 2, 0).eq(uint256(42)))
            .buildUnsafe();

        bytes memory callData = abi.encodeWithSignature("foo((uint256,address)[])");
        callData = abi.encodePacked(callData, bytes32(uint256(32)));
        callData = abi.encodePacked(callData, bytes32(uint256(5)));
        for (uint256 i; i < 5; ++i) {
            uint256 val = (i == 2) ? 42 : i * 10;
            callData = abi.encodePacked(callData, bytes32(val), bytes32(uint256(uint160(address(uint160(i))))));
        }

        return Fixture({ policy: policy, callData: callData });
    }

    /*/////////////////////////////////////////////////////////////////////////
                              LCP BENEFIT BUILDERS
    /////////////////////////////////////////////////////////////////////////*/

    function _buildLcpFixtures() internal {
        // "None": 4 separate top-level parameters, paths are [0], [1], [2], [3]
        // (no shared prefix across the set beyond "calldata scope" itself).
        {
            string memory sig = "foo(uint256,uint256,uint256,uint256)";
            bytes memory callData = abi.encodeWithSignature(sig, uint256(1), uint256(2), uint256(3), uint256(4));
            lcpNone4Rules = _buildFixture(
                PolicyBuilder.create(sig)
                    .add(arg(0).eq(uint256(1)))
                    .add(arg(1).eq(uint256(2)))
                    .add(arg(2).eq(uint256(3)))
                    .add(arg(3).eq(uint256(4))),
                callData
            );
        }

        // "1 shared": tuple field accesses share the first path step [0]
        {
            string memory sig = "foo((uint256,uint256,uint256,uint256))";
            bytes memory callData = _encodeTupleCalldata(sig, 4);
            lcp1Shared4Rules = _buildFixture(
                PolicyBuilder.create(sig)
                    .add(arg(0, 0).eq(uint256(1)))
                    .add(arg(0, 1).eq(uint256(2)))
                    .add(arg(0, 2).eq(uint256(3)))
                    .add(arg(0, 3).eq(uint256(4))),
                callData
            );
        }

        // "3 deep": deeply nested tuple, paths share [0, 0, 0]
        {
            string memory sig = "foo((((uint256,uint256,uint256,uint256),uint256),uint256))";
            bytes memory callData = abi.encodePacked(
                abi.encodeWithSignature(sig),
                bytes32(uint256(1)),
                bytes32(uint256(2)),
                bytes32(uint256(3)),
                bytes32(uint256(4)),
                bytes32(uint256(5)),
                bytes32(uint256(6))
            );
            lcp3Deep4Rules = _buildFixture(
                PolicyBuilder.create(sig)
                    .add(arg(0, 0, 0, 0).eq(uint256(1)))
                    .add(arg(0, 0, 0, 1).eq(uint256(2)))
                    .add(arg(0, 0, 0, 2).eq(uint256(3)))
                    .add(arg(0, 0, 0, 3).eq(uint256(4))),
                callData
            );
        }

        // "Identical paths": all rules share the exact same path [0, 0]
        {
            string memory sig = "foo((uint256,uint256,uint256,uint256))";
            bytes memory callData = _encodeTupleCalldata(sig, 4);
            lcpIdenticalPaths = _buildFixture(
                PolicyBuilder.create(sig)
                    .add(arg(0, 0).gte(uint256(0)).gte(uint256(1)).lte(uint256(100)).lte(uint256(200))),
                callData
            );
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                              OPERATOR BUILDERS
    /////////////////////////////////////////////////////////////////////////*/

    function _buildOperatorFixtures() internal {
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        opEq = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).eq(uint256(42))),
            callData
        );

        opGt = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).gt(uint256(40))),
            callData
        );

        opLt = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).lt(uint256(50))),
            callData
        );

        opGte = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).gte(uint256(42))),
            callData
        );

        opLte = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).lte(uint256(50))),
            callData
        );

        opBetween = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).between(uint256(40), uint256(50))),
            callData
        );

        opIn2 = _buildIn(2);
        opIn4 = _buildIn(4);
        opIn6 = _buildIn(6);
        opIn8 = _buildIn(8);
        opIn16 = _buildIn(16);
        opIn32 = _buildIn(32);
        opIn64 = _buildIn(64);
        opIn128 = _buildIn(128);

        opBitmaskAll = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).bitmaskAll(0x0F)),
            abi.encodeWithSignature("foo(uint256)", uint256(0xFF))
        );

        opBitmaskAny = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).bitmaskAny(0x0F)),
            abi.encodeWithSignature("foo(uint256)", uint256(0x01))
        );

        opBitmaskNone = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).bitmaskNone(0x0F)),
            abi.encodeWithSignature("foo(uint256)", uint256(0xF0))
        );

        opNotEq = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).neq(uint256(100))),
            callData
        );

        uint256[] memory notSet = new uint256[](4);
        for (uint256 i; i < 4; ++i) {
            notSet[i] = i + 1;
        }
        opNotIn4 = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).notIn(notSet)),
            abi.encodeWithSignature("foo(uint256)", uint256(100))
        );
    }

    function _buildIn(uint256 count) internal pure returns (Fixture memory) {
        uint256[] memory set = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            set[i] = i + 1;
        }
        bytes memory policy = PolicyBuilder.create("foo(uint256)")
            .add(arg(0).isIn(set))
            .buildUnsafe();
        return Fixture({ policy: policy, callData: abi.encodeWithSignature("foo(uint256)", count) });
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SCOPE BUILDERS
    /////////////////////////////////////////////////////////////////////////*/

    function _buildScopeFixtures() internal {
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", uint256(42));

        scopeCalldataOnly = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).gte(uint256(0)).gte(uint256(10)).gte(uint256(20)).gte(uint256(30))),
            callData
        );

        scopeContextOnly = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(msgSender().eq(address(this)))
                .add(msgValue().eq(uint256(0)))
                .add(blockTimestamp().gt(uint256(0)))
                .add(chainId().gt(uint256(0))),
            callData
        );

        scopeMixed = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(msgSender().eq(address(this)))
                .add(msgValue().eq(uint256(0)))
                .add(arg(0).eq(uint256(42)).gte(uint256(0))),
            callData
        );

        scopeCtxMsgSender = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(msgSender().eq(address(this))),
            callData
        );

        scopeCtxMsgValue = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(msgValue().eq(uint256(0))),
            callData
        );

        scopeCtxTimestamp = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(blockTimestamp().gt(uint256(0))),
            callData
        );

        scopeCtxBlockNumber = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(blockNumber().gt(uint256(0))),
            callData
        );

        scopeCtxChainId = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(chainId().gt(uint256(0))),
            callData
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                              VALUE TYPE BUILDERS
    /////////////////////////////////////////////////////////////////////////*/

    function _buildValueTypeFixtures() internal {
        typeElementary = _buildFixture(
            PolicyBuilder.create("foo(uint256)")
                .add(arg(0).eq(uint256(42))),
            abi.encodeWithSignature("foo(uint256)", uint256(42))
        );

        typeAddress = _buildFixture(
            PolicyBuilder.create("foo(address)")
                .add(arg(0).eq(address(1))),
            abi.encodeWithSignature("foo(address)", address(1))
        );

        typeBytes32 = _buildFixture(
            PolicyBuilder.create("foo(bytes32)")
                .add(arg(0).eq(bytes32(uint256(42)))),
            abi.encodeWithSignature("foo(bytes32)", bytes32(uint256(42)))
        );

        typeStaticStruct = _buildFixture(
            PolicyBuilder.create("foo((address,uint256))")
                .add(arg(0, 1).eq(uint256(42))),
            _encodeStruct2(address(1), 42)
        );

        typeDynStructStatic = _buildFixture(
            PolicyBuilder.create("foo((address,bytes))")
                .add(arg(0, 0).eq(address(1))),
            abi.encodeWithSignature("foo((address,bytes))", address(1), hex"0102")
        );

        uint256[] memory arr = new uint256[](10);
        for (uint256 i; i < 10; ++i) {
            arr[i] = i + 1;
        }
        typeArrayElement = _buildFixture(
            PolicyBuilder.create("foo(uint256[])")
                .add(arg(0, 5).eq(uint256(6))),
            abi.encodeWithSignature("foo(uint256[])", arr)
        );

        uint256[10] memory staticArr = [uint256(1), 2, 3, 4, 5, 6, 7, 8, 9, 10];
        typeStaticArrayElem = _buildFixture(
            PolicyBuilder.create("foo(uint256[10])")
                .add(arg(0, 5).eq(uint256(6))),
            abi.encodeWithSignature("foo(uint256[10])", staticArr)
        );

        typeLargeTupleField = _buildRulesN(32);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              LENGTH OPERATOR BUILDERS
    /////////////////////////////////////////////////////////////////////////*/

    function _buildLengthOpFixtures() internal {
        uint256[] memory arr10 = new uint256[](10);
        for (uint256 i; i < 10; ++i) {
            arr10[i] = i;
        }
        lengthEqDynArray = _buildFixture(
            PolicyBuilder.create("foo(uint256[])")
                .add(arg(0).lengthEq(10)),
            abi.encodeWithSignature("foo(uint256[])", arr10)
        );

        uint256[] memory arr100 = new uint256[](100);
        for (uint256 i; i < 100; ++i) {
            arr100[i] = i;
        }
        lengthGtDynArray = _buildFixture(
            PolicyBuilder.create("foo(uint256[])")
                .add(arg(0).lengthGt(50)),
            abi.encodeWithSignature("foo(uint256[])", arr100)
        );

        bytes memory bytesData = new bytes(256);
        for (uint256 i; i < 256; ++i) {
            bytesData[i] = bytes1(uint8(i));
        }
        lengthBetweenBytes = _buildFixture(
            PolicyBuilder.create("foo(bytes)")
                .add(arg(0).lengthBetween(100, 300)),
            abi.encodeWithSignature("foo(bytes)", bytesData)
        );

        lengthLtBytesEmpty = _buildFixture(
            PolicyBuilder.create("foo(bytes)")
                .add(arg(0).lengthLt(1)),
            abi.encodeWithSignature("foo(bytes)", hex"")
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    HELPERS
    /////////////////////////////////////////////////////////////////////////*/

    function _buildFixture(PolicyDraft memory draft, bytes memory callData) internal pure returns (Fixture memory) {
        return Fixture({ policy: draft.buildUnsafe(), callData: callData });
    }
}

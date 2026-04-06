// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Constraint, Operator, arg } from "src/Constraint.sol";
import { OpCode } from "src/OpCode.sol";

import { ConstraintTest } from "test/unit/Constraint.t.sol";

contract ConstraintIsInTest is ConstraintTest {
    /*/////////////////////////////////////////////////////////////////////////
                              FUZZ TESTS (CORE PROPERTIES)
    /////////////////////////////////////////////////////////////////////////*/

    function testFuzz_Uint256_SortedAndDeduped(uint256[] memory values) public pure {
        vm.assume(values.length > 0 && values.length <= 32);
        if (values.length > 1) values[values.length / 2] = values[0]; // Inject dupe

        bytes32[] memory set = _extractPackedSet(arg(0).isIn(values).operators[0]);
        assertCanonicalSet(set, _toBytes32Array(values));
    }

    function testFuzz_Int256_SortedAndDeduped(int256[] memory values) public pure {
        vm.assume(values.length > 0 && values.length <= 32);
        if (values.length > 1) values[values.length / 2] = values[0];

        bytes32[] memory set = _extractPackedSet(arg(0).isIn(values).operators[0]);
        assertCanonicalSet(set, _toBytes32Array(values));
    }

    function testFuzz_Address_SortedAndDeduped(address[] memory values) public pure {
        vm.assume(values.length > 0 && values.length <= 32);
        if (values.length > 1) values[values.length / 2] = values[0];

        bytes32[] memory set = _extractPackedSet(arg(0).isIn(values).operators[0]);
        assertCanonicalSet(set, _toBytes32Array(values));
    }

    function testFuzz_Bytes32_SortedAndDeduped(bytes32[] memory values) public pure {
        vm.assume(values.length > 0 && values.length <= 32);
        if (values.length > 1) values[values.length / 2] = values[0];

        bytes32[] memory set = _extractPackedSet(arg(0).isIn(values).operators[0]);
        assertCanonicalSet(set, values);
    }

    function testFuzz_Uint256_PermutationInvariant(uint256[] memory values, uint256 seed) public pure {
        vm.assume(values.length > 1 && values.length <= 16);
        uint256[] memory shuffled = new uint256[](values.length);
        for (uint256 i; i < values.length; ++i) {
            shuffled[i] = values[i];
        }
        _shuffle(shuffled, seed);

        // forgefmt: disable-next-item
        assertArrayEq(
            _extractPackedSet(arg(0).isIn(values).operators[0]),
            _extractPackedSet(arg(0).isIn(shuffled).operators[0])
        );
    }

    function testFuzz_Int256_PermutationInvariant(int256[] memory values, uint256 seed) public pure {
        vm.assume(values.length > 1 && values.length <= 16);
        int256[] memory shuffled = new int256[](values.length);
        for (uint256 i; i < values.length; ++i) {
            shuffled[i] = values[i];
        }
        _shuffle(shuffled, seed);

        // forgefmt: disable-next-item
        assertArrayEq(
            _extractPackedSet(arg(0).isIn(values).operators[0]),
            _extractPackedSet(arg(0).isIn(shuffled).operators[0])
        );
    }

    function testFuzz_Address_PermutationInvariant(address[] memory values, uint256 seed) public pure {
        vm.assume(values.length > 1 && values.length <= 16);
        address[] memory shuffled = new address[](values.length);
        for (uint256 i; i < values.length; ++i) {
            shuffled[i] = values[i];
        }
        _shuffle(shuffled, seed);

        // forgefmt: disable-next-item
        assertArrayEq(
            _extractPackedSet(arg(0).isIn(values).operators[0]),
            _extractPackedSet(arg(0).isIn(shuffled).operators[0])
        );
    }

    function testFuzz_Bytes32_PermutationInvariant(bytes32[] memory values, uint256 seed) public pure {
        vm.assume(values.length > 1 && values.length <= 16);
        bytes32[] memory shuffled = new bytes32[](values.length);
        for (uint256 i; i < values.length; ++i) {
            shuffled[i] = values[i];
        }
        _shuffle(shuffled, seed);

        // forgefmt: disable-next-item
        assertArrayEq(
            _extractPackedSet(arg(0).isIn(values).operators[0]),
            _extractPackedSet(arg(0).isIn(shuffled).operators[0])
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                              EDGE CASES (CONCRETE)
    /////////////////////////////////////////////////////////////////////////*/

    function test_Uint256_SingleElement() public pure {
        uint256[] memory values = new uint256[](1);
        values[0] = 42;

        bytes32[] memory set = _extractPackedSet(arg(0).isIn(values).operators[0]);
        assertEq(set.length, 1);
        assertEq(set[0], bytes32(uint256(42)));
    }

    function test_Uint256_AllDuplicatesReducesToOne() public pure {
        uint256[] memory values = new uint256[](3);
        values[0] = 42;
        values[1] = 42;
        values[2] = 42;

        bytes32[] memory set = _extractPackedSet(arg(0).isIn(values).operators[0]);
        assertEq(set.length, 1);
        assertEq(set[0], bytes32(uint256(42)));
    }

    function test_Int256_SortsByBytesNotSignedValue() public pure {
        int256[] memory values = new int256[](3);
        values[0] = -1;
        values[1] = 0;
        values[2] = 1;

        bytes32[] memory set = _extractPackedSet(arg(0).isIn(values).operators[0]);
        assertEq(set.length, 3);
        // Unsigned byte ordering: 0 < 1 < -1 (0xFFFF...FFFF)
        assertEq(set[0], bytes32(uint256(0)));
        assertEq(set[1], bytes32(uint256(1)));
        assertEq(set[2], bytes32(type(uint256).max)); // -1 as bytes
    }

    function test_Int256_ExtremesOrderedByEncodedBytes() public pure {
        int256[] memory values = new int256[](5);
        values[0] = type(int256).min; // 0x80..00
        values[1] = type(int256).max; // 0x7F..FF
        values[2] = -1; // 0xFF..FF
        values[3] = 0; // 0x00..00
        values[4] = 1; // 0x00..01

        bytes32[] memory set = _extractPackedSet(arg(0).isIn(values).operators[0]);

        assertEq(set.length, 5);
        // Unsigned byte ordering: 0 < 1 < MAX < MIN < -1
        assertEq(set[0], bytes32(uint256(0)));
        assertEq(set[1], bytes32(uint256(1)));
        assertEq(set[2], bytes32(uint256(type(int256).max)));
        assertEq(set[3], bytes32(uint256(type(int256).min)));
        assertEq(set[4], bytes32(type(uint256).max)); // -1
    }

    function test_Bytes32_MSBFirst_HighByteDominates() public pure {
        // Explicitly differ at the most-significant byte to validate MSB-first ordering.
        bytes32[] memory values = new bytes32[](2);
        values[0] = bytes32(uint256(0x01) << 248); // 0x01 00..00
        values[1] = bytes32(uint256(0xFF)); // 0x00..FF

        bytes32[] memory set = _extractPackedSet(arg(0).isIn(values).operators[0]);
        assertEq(set.length, 2);

        // 0x00..FF sorts before 0x01 00..00 (MSB-first lexicographic)
        assertEq(set[0], bytes32(uint256(0xFF)));
        assertEq(set[1], bytes32(uint256(0x01) << 248));
    }

    /*/////////////////////////////////////////////////////////////////////////
                              NOTIN TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_NotIn_HasNotFlag() public pure {
        uint256[] memory values = new uint256[](1);
        values[0] = 42;

        Constraint memory c = arg(0).notIn(values);

        // First byte of operator should be OP_IN | NOT_FLAG
        assertEq(uint8(c.operators[0][0]), OpCode.IN | OpCode.NOT);
    }

    function testFuzz_NotIn_SamePackingAsIsIn(uint256[] memory values) public pure {
        vm.assume(values.length > 0 && values.length <= 16);
        // forgefmt: disable-next-item
        assertArrayEq(
            _extractPackedSet(arg(0).isIn(values).operators[0]),
            _extractPackedSet(arg(0).notIn(values).operators[0])
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  EMPTY SET
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_EmptyUint256Set() public {
        uint256[] memory values = new uint256[](0);

        vm.expectRevert(Operator.EmptySet.selector);
        arg(0).isIn(values);
    }

    function test_RevertWhen_EmptyInt256Set() public {
        int256[] memory values = new int256[](0);

        vm.expectRevert(Operator.EmptySet.selector);
        arg(0).isIn(values);
    }

    function test_RevertWhen_EmptyAddressSet() public {
        address[] memory values = new address[](0);

        vm.expectRevert(Operator.EmptySet.selector);
        arg(0).isIn(values);
    }

    function test_RevertWhen_EmptyBytes32Set() public {
        bytes32[] memory values = new bytes32[](0);

        vm.expectRevert(Operator.EmptySet.selector);
        arg(0).isIn(values);
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SET CARDINALITY LIMIT
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_SetExceedsMaxCardinality() public {
        uint256[] memory values = new uint256[](2048);
        for (uint256 i; i < 2048; ++i) {
            values[i] = i;
        }

        vm.expectRevert(Operator.SetTooLarge.selector);
        arg(0).isIn(values);
    }

    function test_MaxCardinalityAccepted() public pure {
        uint256[] memory values = new uint256[](2047);
        for (uint256 i; i < 2047; ++i) {
            values[i] = i;
        }

        Constraint memory c = arg(0).isIn(values);
        assertEq(c.operators.length, 1);
    }
}

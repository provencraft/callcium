// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Descriptor } from "src/Descriptor.sol";
import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { TypeCode } from "src/TypeCode.sol";
import { TypeDesc } from "src/TypeDesc.sol";

import { DescriptorHarness } from "test/harnesses/DescriptorHarness.sol";
import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Benchmarks for Descriptor.typeAt path traversal. Descriptors only — traversal never reads
///      calldata, so this suite builds no calldata corpus.
contract TypeAtBench is BaseTest {
    DescriptorHarness internal harness;

    bytes internal descElementary;
    bytes internal descStaticStruct;
    bytes internal descStaticTuple10;
    bytes internal descStaticTuple32;

    function setUp() public {
        harness = new DescriptorHarness();

        descElementary = DescriptorBuilder.fromTypes("uint256");
        descStaticStruct = DescriptorBuilder.fromTypes("(address,uint256)");
        descStaticTuple10 = DescriptorBuilder.create().add(TypeDesc.tuple_(_alternatingFields(10))).build();
        descStaticTuple32 = DescriptorBuilder.create().add(TypeDesc.tuple_(_alternatingFields(32))).build();
    }

    /// @dev Builds `count` tuple fields alternating between address and uint256.
    function _alternatingFields(uint256 count) private pure returns (bytes[] memory fields) {
        fields = new bytes[](count);
        for (uint256 i; i < count; ++i) {
            fields[i] = (i % 2 == 0) ? TypeDesc.address_() : TypeDesc.uint256_();
        }
    }

    /// @dev Snapshots the harness call just made and pins the type it is built to resolve to.
    function _bench(Descriptor.TypeInfo memory info, string memory name, uint8 expectedCode) private {
        vm.snapshotGasLastCall("Descriptor.typeAt", name);
        assertEq(info.code, expectedCode);
    }

    function test_Depth1() public {
        _bench(harness.typeAt(descElementary, _path(0)), "depth1", TypeCode.UINT256);
    }

    function test_Depth2() public {
        _bench(harness.typeAt(descStaticStruct, _path(0, 1)), "depth2", TypeCode.UINT256);
    }

    function test_Tuple10Last() public {
        _bench(harness.typeAt(descStaticTuple10, _path(0, 9)), "tuple10_last", TypeCode.UINT256);
    }

    function test_Tuple32Last() public {
        _bench(harness.typeAt(descStaticTuple32, _path(0, 31)), "tuple32_last", TypeCode.UINT256);
    }
}

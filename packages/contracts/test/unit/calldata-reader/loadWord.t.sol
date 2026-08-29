// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// forge-lint: disable-start(unused-return)

import { LibBytes } from "solady/utils/LibBytes.sol";

import { CalldataReader } from "src/CalldataReader.sol";

import { CalldataReaderHarness } from "test/harnesses/CalldataReaderHarness.sol";
import { BaseTest } from "test/unit/BaseTest.sol";

contract LoadWordTest is BaseTest {
    CalldataReaderHarness internal harness;

    function setUp() public {
        harness = new CalldataReaderHarness();
    }

    function test_ReadsWordAtOffsetZero() public view {
        bytes memory callData = abi.encode(uint256(42));
        assertEq(uint256(harness.loadWord(callData, 0)), 42);
    }

    function test_ReadsWordAtNonZeroOffset() public view {
        bytes memory callData = abi.encode(uint256(1), uint256(99));
        assertEq(uint256(harness.loadWord(callData, 32)), 99);
    }

    function test_ReadsAtExactUpperBound() public view {
        bytes memory callData = abi.encode(uint256(7));
        assertEq(uint256(harness.loadWord(callData, callData.length - 32)), 7);
    }

    function test_RevertWhen_OffsetPastEnd() public {
        bytes memory callData = abi.encode(uint256(1));
        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
        harness.loadWord(callData, 1);
    }

    function test_RevertWhen_BufferShorterThanWord() public {
        vm.expectRevert(CalldataReader.CalldataOutOfBounds.selector);
        harness.loadWord(hex"00112233", 0);
    }

    function testFuzz_ReadsAnyInBoundsWord(uint256 value, uint256 seed) public view {
        bytes memory callData = abi.encode(uint256(0), value, uint256(0));
        uint256 offset = bound(seed, 0, callData.length - 32);
        assertEq(harness.loadWord(callData, offset), LibBytes.load(callData, offset));
    }
}

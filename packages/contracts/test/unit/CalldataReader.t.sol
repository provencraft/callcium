// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { CalldataReader } from "src/CalldataReader.sol";

import { CalldataReaderHarness } from "test/harnesses/CalldataReaderHarness.sol";

contract CalldataReaderLoadWordTest is Test {
    CalldataReaderHarness internal harness;

    function setUp() public {
        harness = new CalldataReaderHarness();
    }

    /// @dev Over every calldata length up to three words and every offset, a load returns the word at the offset
    /// exactly when it lies within the calldata, and reverts otherwise.
    function prove_ReadsExactlyTheWordsWithinTheCalldata(
        bytes32 first,
        bytes32 second,
        bytes32 third,
        uint256 length,
        uint256 offset
    )
        public
        view
    {
        vm.assume(length <= 96);
        bytes memory callData = abi.encodePacked(first, second, third);
        bool inBounds = length >= 32 && offset <= length - 32;
        // An in-bounds offset is at most two words in, so the word is a window over two adjacent calldata words.
        bytes32 head = offset < 32 ? first : offset < 64 ? second : third;
        bytes32 tail = offset < 32 ? second : offset < 64 ? third : bytes32(0);
        uint256 shift = (offset % 32) * 8;
        try harness.loadWordWithin(callData, length, offset) returns (bytes32 word) {
            assertTrue(inBounds);
            assertEq(word, (head << shift) | (tail >> (256 - shift)));
        } catch (bytes memory reason) {
            assertFalse(inBounds);
            assertEq(bytes4(reason), CalldataReader.CalldataOutOfBounds.selector);
        }
    }
}

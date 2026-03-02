// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { LibBytes } from "solady/utils/LibBytes.sol";

import { CalldataReader } from "src/CalldataReader.sol";

import { CalldataReaderHarness } from "test/harnesses/CalldataReaderHarness.sol";
import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for CalldataReader unit tests.
abstract contract CalldataReaderTest is BaseTest {
    CalldataReaderHarness internal harness;
    bytes4 internal constant SELECTOR = bytes4(keccak256("foo(uint256)"));

    // Shared config.
    CalldataReader.Config internal cfg; // baseOffset = 4.

    struct SimpleTuple {
        address addr;
        uint256 val;
    }

    struct AddressWithArray {
        address addr;
        uint256[] vals;
    }

    struct AddressWithBytes {
        address addr;
        bytes data;
    }

    function setUp() public virtual {
        harness = new CalldataReaderHarness();
        cfg.baseOffset = 4;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                      HELPERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev ABI-encodes an array of addresses into contiguous words.
    function _encodeAddresses(address[] memory addrs) internal pure returns (bytes memory) {
        bytes memory result;
        for (uint256 i; i < addrs.length; ++i) {
            result = abi.encodePacked(result, abi.encode(addrs[i]));
        }
        return result;
    }

    /// @dev Extracts bytes from `callData` using `slice` bounds.
    function _sliceToBytes(
        bytes memory callData,
        CalldataReader.DynamicSlice memory slice
    )
        internal
        pure
        returns (bytes memory)
    {
        return LibBytes.slice(callData, slice.dataOffset, slice.dataOffset + slice.length);
    }

    /// @dev Asserts that `slice` matches `expected` bytes in `callData`.
    function _assertSlice(
        bytes memory callData,
        CalldataReader.DynamicSlice memory slice,
        bytes memory expected
    )
        internal
        pure
    {
        assertEq(slice.length, expected.length);
        assertTrue(LibBytes.eq(_sliceToBytes(callData, slice), expected));
    }

    /// @dev Asserts that two locations have identical fields.
    function _assertLocationMatches(
        CalldataReader.Location memory actual,
        CalldataReader.Location memory expected
    )
        internal
        pure
    {
        assertEq(actual.head, expected.head);
        assertEq(actual.base, expected.base);
        assertEq(actual.descOffset, expected.descOffset);
    }
}

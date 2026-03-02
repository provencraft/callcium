// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyEnforcerHarness } from "test/harnesses/PolicyEnforcerHarness.sol";
import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for PolicyEnforcer unit tests.
abstract contract PolicyEnforcerTest is BaseTest {
    PolicyEnforcerHarness internal harness;

    function setUp() public virtual {
        harness = new PolicyEnforcerHarness();
    }

    /// @dev Encodes a static struct (address, uint256) into calldata.
    function _encodeStruct2(address addr, uint256 val) internal pure returns (bytes memory) {
        bytes memory data = abi.encodeWithSignature("foo((address,uint256))");
        return abi.encodePacked(data, bytes32(uint256(uint160(addr))), bytes32(val));
    }

    /// @dev Encodes a nested struct ((address, uint256), uint256) into calldata.
    function _encodeNestedStruct3(address addr, uint256 val1, uint256 val2) internal pure returns (bytes memory) {
        bytes memory data = abi.encodeWithSignature("foo(((address,uint256),uint256))");
        return abi.encodePacked(data, bytes32(uint256(uint160(addr))), bytes32(val1), bytes32(val2));
    }

    /// @dev Creates an array of uint256 values [1, 2, ..., length].
    function _uintArray(uint256 length) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            arr[i] = i + 1;
        }
    }
}

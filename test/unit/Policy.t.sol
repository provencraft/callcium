// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Be16 } from "src/Be16.sol";
import { arg, msgSender } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

import { PolicyHarness } from "test/harnesses/PolicyHarness.sol";
import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for Policy unit tests.
abstract contract PolicyTest is BaseTest {
    PolicyHarness internal harness;

    function setUp() public virtual {
        harness = new PolicyHarness();
    }

    /// @dev Builds a valid single-rule policy: foo(uint256) with arg(0).eq(42).
    function _validBlob() internal pure returns (bytes memory) {
        return PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(42))).buildUnsafe();
    }

    /// @dev Builds a valid two-group policy for OR-group tests.
    function _twoGroupBlob() internal pure returns (bytes memory) {
        return
            PolicyBuilder.create("foo(uint256)").add(arg(0).eq(uint256(1))).or().add(arg(0).eq(uint256(2)))
                .buildUnsafe();
    }

    /// @dev Builds a valid context-scope policy: msgSender().eq(address).
    function _contextBlob() internal pure returns (bytes memory) {
        return PolicyBuilder.create("foo(uint256)").add(msgSender().eq(address(1))).buildUnsafe();
    }

    /// @dev Returns the offset of the first group header within a policy blob.
    function _firstGroupOffset(bytes memory blob) internal pure returns (uint256) {
        uint16 descLen = Be16.readUnchecked(blob, PF.POLICY_DESC_LENGTH_OFFSET);
        return PF.POLICY_HEADER_PREFIX + descLen + PF.POLICY_GROUP_COUNT_SIZE;
    }

    /// @dev Returns the offset of the first rule within the first group.
    function _firstRuleOffset(bytes memory blob) internal pure returns (uint256) {
        return _firstGroupOffset(blob) + PF.GROUP_HEADER_SIZE;
    }

    /// @dev Zeroes the 4-byte selector slot in a policy blob.
    function _zeroSelector(bytes memory blob) internal pure {
        blob[PF.POLICY_SELECTOR_OFFSET] = 0x00;
        blob[PF.POLICY_SELECTOR_OFFSET + 1] = 0x00;
        blob[PF.POLICY_SELECTOR_OFFSET + 2] = 0x00;
        blob[PF.POLICY_SELECTOR_OFFSET + 3] = 0x00;
    }

    /// @dev Writes a big-endian uint32 into `blob` at `offset`.
    function _writeU32(bytes memory blob, uint256 offset, uint32 value) internal pure {
        // forge-lint: disable-next-line(unsafe-typecast) casting to 'uint8' is safe because value is uint32 and the shift discards upper bits
        blob[offset] = bytes1(uint8(value >> 24));
        // forge-lint: disable-next-line(unsafe-typecast)
        blob[offset + 1] = bytes1(uint8(value >> 16));
        // forge-lint: disable-next-line(unsafe-typecast)
        blob[offset + 2] = bytes1(uint8(value >> 8));
        // forge-lint: disable-next-line(unsafe-typecast)
        blob[offset + 3] = bytes1(uint8(value));
    }
}

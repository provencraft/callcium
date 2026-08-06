// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Be16 } from "src/Be16.sol";
import { arg, msgSender } from "src/Constraint.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

import { PolicyHarness } from "test/harnesses/PolicyHarness.sol";
import { BaseTest } from "test/unit/BaseTest.sol";

/// @dev Base contract for Policy unit tests.
abstract contract PolicyTest is BaseTest {
    /// @dev The sentinel hint block: a path that does not compile to concrete offsets.
    bytes internal constant SENTINEL_HINT = hex"ffffffff00";

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

    /// @dev Builds a context-scope policy and rewrites its property ID to `ctxId`, bypassing builder validation.
    function _contextBlob(uint16 ctxId) internal pure returns (bytes memory) {
        bytes memory blob = _contextBlob();
        Be16.write(blob, _firstRuleOffset(blob) + PF.RULE_PATH_OFFSET, ctxId);
        return blob;
    }

    /// @dev Zeroes the 4-byte selector slot in a policy blob.
    function _zeroSelector(bytes memory blob) internal pure {
        blob[PF.POLICY_SELECTOR_OFFSET] = 0x00;
        blob[PF.POLICY_SELECTOR_OFFSET + 1] = 0x00;
        blob[PF.POLICY_SELECTOR_OFFSET + 2] = 0x00;
        blob[PF.POLICY_SELECTOR_OFFSET + 3] = 0x00;
    }
}

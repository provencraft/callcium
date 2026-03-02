// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyTest } from "../Policy.t.sol";

import { PolicyFormat as PF } from "src/PolicyFormat.sol";

contract VersionTest is PolicyTest {
    function test_ReturnsCurrentVersion() public view {
        bytes memory blob = _validBlob();
        assertEq(harness.version(blob), PF.POLICY_VERSION);
    }

    function test_MaskedCorrectlyWithFlag() public view {
        bytes memory blob = _validBlob();
        blob[PF.POLICY_HEADER_OFFSET] = bytes1(PF.POLICY_VERSION | PF.FLAG_NO_SELECTOR);
        _zeroSelector(blob);
        assertEq(harness.version(blob), PF.POLICY_VERSION);
    }
}

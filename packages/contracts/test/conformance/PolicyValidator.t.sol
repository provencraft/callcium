// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyValidator } from "src/PolicyValidator.sol";

import { ConformanceTest } from "test/conformance/ConformanceTest.sol";

contract PolicyValidatorConformanceTest is ConformanceTest {
    /// @dev Returns the issue keys of the vector at `key`.
    function _expectedKeys(string memory json, string memory key) private view returns (string[] memory keys) {
        uint256 count = 0;
        while (vm.keyExistsJson(json, string.concat(key, ".issues[", vm.toString(count), "]"))) ++count;
        keys = new string[](count);
        for (uint256 i = 0; i < count; ++i) {
            string memory issueKey = string.concat(key, ".issues[", vm.toString(i), "]");
            string memory location = vm.parseJsonString(json, string.concat(issueKey, ".location"));
            keys[i] = vm.parseJsonString(json, string.concat(issueKey, ".code"));
            if (bytes(location).length != 0) keys[i] = string.concat(keys[i], "@", location);
        }
    }

    function test_ValidatesConformWithSpecification() public view {
        string memory json = vm.readFile("../../spec/vectors/validation.json");
        uint256 count = _vectorCount(json);
        assertGt(count, 0, "no vectors");
        for (uint256 i = 0; i < count; ++i) {
            string memory key = string.concat(".[", vm.toString(i), "]");
            string memory id = vm.parseJsonString(json, string.concat(key, ".id"));
            bytes memory blob = vm.parseJsonBytes(json, string.concat(key, ".blob"));
            _assertSameIssues(_issueKeys(PolicyValidator.validate(blob)), _expectedKeys(json, key), id);
        }
    }
}

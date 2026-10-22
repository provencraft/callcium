// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Descriptor } from "src/Descriptor.sol";

import { ConformanceTest } from "test/conformance/ConformanceTest.sol";

contract DescriptorConformanceTest is ConformanceTest {
    struct DescriptorParam {
        /// @dev Whether the parameter type is dynamically sized.
        bool isDynamic;
        /// @dev ABI head size in bytes; zero for dynamic types.
        uint256 staticSize;
        /// @dev TypeDesc type code.
        uint256 typeCode;
    }

    struct DescriptorFixture {
        /// @dev Descriptor blob.
        bytes blob;
        /// @dev What the vector exercises.
        string description;
        /// @dev Expected error name, or empty string for valid cases.
        string error;
        /// @dev Arguments of the expected error, one word each; empty for valid cases.
        bytes32[] errorArgs;
        /// @dev Vector identifier.
        string id;
        /// @dev Parameter type metadata for valid descriptors.
        DescriptorParam[] params;
        /// @dev Descriptor format version.
        uint256 version;
    }

    /// @dev External so `vm.expectRevert` intercepts each call in the vector loop.
    function validate(bytes memory blob) external pure {
        Descriptor.validate(blob);
    }

    /// @dev Loads and parses all fixtures from the descriptor vector file.
    function _fixtures() private view returns (DescriptorFixture[] memory fixtures) {
        string memory json = vm.readFile("../../spec/vectors/descriptors.json");
        uint256 count = _vectorCount(json);
        assertGt(count, 0, "no vectors");
        fixtures = new DescriptorFixture[](count);
        for (uint256 i = 0; i < count; ++i) {
            fixtures[i] = abi.decode(vm.parseJson(json, string.concat(".[", vm.toString(i), "]")), (DescriptorFixture));
        }
    }

    /// @dev Maps a fixture error name to its error selector.
    function _errorSelector(string memory name) private pure returns (bytes4) {
        bytes32 nameHash = keccak256(bytes(name));
        if (nameHash == keccak256("InvalidArrayLength")) return Descriptor.InvalidArrayLength.selector;
        if (nameHash == keccak256("InvalidTupleFieldCount")) return Descriptor.InvalidTupleFieldCount.selector;
        if (nameHash == keccak256("MalformedHeader")) return Descriptor.MalformedHeader.selector;
        if (nameHash == keccak256("NestingTooDeep")) return Descriptor.NestingTooDeep.selector;
        if (nameHash == keccak256("NodeLengthTooSmall")) return Descriptor.NodeLengthTooSmall.selector;
        if (nameHash == keccak256("NodeOverflow")) return Descriptor.NodeOverflow.selector;
        if (nameHash == keccak256("ParamCountMismatch")) return Descriptor.ParamCountMismatch.selector;
        if (nameHash == keccak256("TooManyParams")) return Descriptor.TooManyParams.selector;
        if (nameHash == keccak256("UnexpectedEnd")) return Descriptor.UnexpectedEnd.selector;
        if (nameHash == keccak256("UnknownTypeCode")) return Descriptor.UnknownTypeCode.selector;
        if (nameHash == keccak256("UnsupportedVersion")) return Descriptor.UnsupportedVersion.selector;
        revert UnknownFixtureError(name);
    }

    function test_ValidatesConformWithSpecification() public {
        DescriptorFixture[] memory fixtures = _fixtures();
        for (uint256 i = 0; i < fixtures.length; ++i) {
            DescriptorFixture memory fixture = fixtures[i];
            if (bytes(fixture.error).length > 0) {
                bytes memory revertData = abi.encodePacked(_errorSelector(fixture.error));
                for (uint256 j = 0; j < fixture.errorArgs.length; ++j) {
                    revertData = bytes.concat(revertData, fixture.errorArgs[j]);
                }
                vm.expectRevert(revertData);
                this.validate(fixture.blob);
                continue;
            }
            Descriptor.validate(fixture.blob);
        }
    }

    function test_ParamCountConformsWithSpecification() public view {
        DescriptorFixture[] memory fixtures = _fixtures();
        for (uint256 i = 0; i < fixtures.length; ++i) {
            DescriptorFixture memory fixture = fixtures[i];
            if (bytes(fixture.error).length > 0) continue;
            assertEq(Descriptor.paramCount(fixture.blob), fixture.params.length, fixture.id);
        }
    }
}

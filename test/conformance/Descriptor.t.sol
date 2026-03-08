// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Descriptor } from "src/Descriptor.sol";

import { BaseTest } from "test/unit/BaseTest.sol";

// forge-lint: disable-next-item(unsafe-cheatcode)
contract DescriptorConformanceTest is BaseTest {
    using Descriptor for bytes;

    struct DescriptorParam {
        /// @dev Parameter index within the descriptor.
        uint256 index;
        /// @dev Whether the parameter type is dynamically sized.
        bool isDynamic;
        /// @dev Encoded path to the parameter.
        bytes path;
        /// @dev Static word count for fixed-size types.
        uint256 staticSize;
        /// @dev TypeDesc type code.
        uint256 typeCode;
    }

    struct DescriptorFixture {
        /// @dev ABI-encoded descriptor blob.
        bytes blob;
        /// @dev Human-readable description of the test case.
        string description;
        /// @dev Expected error name, or empty string for valid cases.
        string error;
        /// @dev ABI-encoded 32-byte arguments for the expected error, or empty.
        bytes32[] errorArgs;
        /// @dev Unique fixture identifier.
        string id;
        /// @dev Parameter type metadata for valid descriptors.
        DescriptorParam[] params;
        /// @dev Descriptor format version.
        uint256 version;
    }

    error UnknownFixtureError(string name);

    /// @dev Loads and parses all fixtures from the descriptor vector file.
    function _fixtures() private view returns (DescriptorFixture[] memory fixtures) {
        string memory json = vm.readFile("test/vectors/descriptors.json");
        uint256 count;
        while (vm.keyExistsJson(json, string.concat(".[", vm.toString(count), "]"))) ++count;
        fixtures = new DescriptorFixture[](count);
        for (uint256 i; i < count; ++i) {
            fixtures[i] = abi.decode(vm.parseJson(json, string.concat(".[", vm.toString(i), "]")), (DescriptorFixture));
        }
    }

    /// @dev External wrapper so `vm.expectRevert` can intercept reverts from validate.
    function validate(bytes memory blob) external pure {
        Descriptor.validate(blob);
    }

    /// @dev Maps a fixture error name to its error selector.
    function _errorSelector(string memory name) private pure returns (bytes4) {
        bytes32 h = keccak256(bytes(name));
        if (h == keccak256("MalformedHeader")) return Descriptor.MalformedHeader.selector;
        if (h == keccak256("NodeLengthTooSmall")) return Descriptor.NodeLengthTooSmall.selector;
        if (h == keccak256("NodeOverflow")) return Descriptor.NodeOverflow.selector;
        if (h == keccak256("ParamCountMismatch")) return Descriptor.ParamCountMismatch.selector;
        if (h == keccak256("UnexpectedEnd")) return Descriptor.UnexpectedEnd.selector;
        if (h == keccak256("UnsupportedVersion")) return Descriptor.UnsupportedVersion.selector;
        revert UnknownFixtureError(name);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                SPECIFICATION TESTS
    /////////////////////////////////////////////////////////////////////////*/

    function test_ValidatesConformWithSpecification() public {
        DescriptorFixture[] memory fixtures = _fixtures();
        for (uint256 i; i < fixtures.length; ++i) {
            DescriptorFixture memory f = fixtures[i];
            if (bytes(f.error).length > 0) {
                bytes4 sel = _errorSelector(f.error);
                bytes memory revertData = abi.encodePacked(sel);
                for (uint256 j; j < f.errorArgs.length; ++j) {
                    revertData = bytes.concat(revertData, f.errorArgs[j]);
                }
                vm.expectRevert(revertData);
                this.validate(f.blob);
                continue;
            }
            Descriptor.validate(f.blob);
        }
    }

    function test_ParamCountConformsWithSpecification() public {
        DescriptorFixture[] memory fixtures = _fixtures();
        for (uint256 i; i < fixtures.length; ++i) {
            DescriptorFixture memory f = fixtures[i];
            if (bytes(f.error).length > 0) continue;
            assertEq(Descriptor.paramCount(f.blob), f.params.length, f.id);
        }
    }

    function test_TypeAtConformsWithSpecification() public {
        DescriptorFixture[] memory fixtures = _fixtures();
        for (uint256 i; i < fixtures.length; ++i) {
            DescriptorFixture memory f = fixtures[i];
            if (bytes(f.error).length > 0) continue;
            if (f.params.length == 0) continue;
            for (uint256 j; j < f.params.length; ++j) {
                DescriptorParam memory param = f.params[j];
                // forge-lint: disable-next-line(unsafe-typecast)
                Descriptor.TypeInfo memory t = f.blob.typeAt(_path(uint16(j)));
                // forge-lint: disable-next-line(unsafe-typecast)
                assertEq(t.code, uint8(param.typeCode), string.concat(f.id, ":code"));
                assertEq(t.isDynamic, param.isDynamic, string.concat(f.id, ":isDynamic"));
                // forge-lint: disable-next-line(unsafe-typecast)
                assertEq(t.staticSize, uint32(param.staticSize), string.concat(f.id, ":staticSize"));
            }
        }
    }
}

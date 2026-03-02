// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PathTest } from "../Path.t.sol";
import { Path } from "src/Path.sol";

// forge-lint: disable-next-item(unsafe-typecast)
contract PathValidateTest is PathTest {
    function test_Validate_ValidPath() public pure {
        bytes memory p = Path.encode(uint16(1), uint16(2), uint16(3));
        uint256 depth = Path.validate(p);
        assertEq(depth, 3);
    }

    function test_RevertWhen_Validate_EmptyPath() public {
        bytes memory p = new bytes(0);
        vm.expectRevert(Path.MalformedPath.selector);
        Path.validate(p);
    }

    function test_RevertWhen_Validate_OddLengthPath() public {
        bytes memory p = hex"01"; // length = 1.
        vm.expectRevert(Path.MalformedPath.selector);
        Path.validate(p);
    }

    function testFuzz_Validate_AcceptsEvenNonEmpty(uint256 depthSeed) public pure {
        uint256 depth = bound(depthSeed, 1, 128);
        uint16[] memory steps = new uint16[](depth);
        for (uint256 i; i < depth; ++i) {
            steps[i] = uint16(i);
        }
        bytes memory p = Path.encode(steps);
        assertEq(Path.validate(p), depth);
    }

    function testFuzz_RevertWhen_Validate_OddLength(uint256 oddSeed) public {
        uint256 oddLength = bound(oddSeed, 1, 255);
        if (oddLength % 2 == 0) oddLength += 1;
        bytes memory p = new bytes(oddLength);
        vm.expectRevert(Path.MalformedPath.selector);
        Path.validate(p);
    }
}

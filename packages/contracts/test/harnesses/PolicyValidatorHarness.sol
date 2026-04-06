// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/// @dev Standalone harness that replicates the set-intersection algorithm
/// used by PolicyValidator._updateSet so we can unit-test ordering semantics
/// without exposing private library functions.
contract PolicyValidatorHarness {
    function checkSetIntersection(uint256[] memory set1, uint256[] memory set2) public pure returns (uint256[] memory) {
        // Mirrors the intersection logic inside PolicyValidator._updateSet:
        // allocate worst-case, fill matches preserving set1 order, then trim.
        uint256[] memory intersection = new uint256[](set1.length);
        uint256 intersectionCount;
        for (uint256 i; i < set1.length; ++i) {
            for (uint256 j; j < set2.length; ++j) {
                if (set1[i] == set2[j]) {
                    intersection[intersectionCount++] = set1[i];
                    break;
                }
            }
        }
        assembly ("memory-safe") {
            mstore(intersection, intersectionCount)
        }
        return intersection;
    }
}

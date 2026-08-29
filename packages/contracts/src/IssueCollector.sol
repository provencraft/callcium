// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Issue } from "./ValidationIssue.sol";

/// @title IssueCollector
/// @notice A growable buffer of validation issues.
library IssueCollector {
    /// @notice A growable buffer of validation issues.
    struct Buffer {
        /// Backing storage; its length is a capacity hint, grown as needed.
        Issue[] items;
        /// Number of issues written.
        uint256 count;
    }

    /// @notice Pushes an issue, doubling the backing storage when full.
    /// @param buffer The issue buffer to push onto.
    /// @param issue The issue to push.
    function push(Buffer memory buffer, Issue memory issue) internal pure {
        uint256 count = buffer.count;
        if (count == buffer.items.length) {
            Issue[] memory grown = new Issue[](count == 0 ? 1 : count * 2);
            for (uint256 i = 0; i < count; ++i) {
                grown[i] = buffer.items[i];
            }
            buffer.items = grown;
        }
        buffer.items[count] = issue;
        unchecked {
            buffer.count = count + 1;
        }
    }

    /// @notice Returns the pushed issues, trimmed to the number written.
    /// @dev Shrinks the backing array in place; a later push re-grows it.
    /// @param buffer The issue buffer to read.
    /// @return result The pushed issues.
    function toArray(Buffer memory buffer) internal pure returns (Issue[] memory result) {
        result = buffer.items;
        uint256 count = buffer.count;
        assembly ("memory-safe") {
            mstore(result, count)
        }
    }
}

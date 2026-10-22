// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CommonBase } from "forge-std/Base.sol";

import { LibBytes } from "src/vendor/solady/utils/LibBytes.sol";

/// @dev Mutates ABI payloads towards the faults a decoder must reject, drawing from Foundry's seeded random cheatcodes.
abstract contract CalldataMutation is CommonBase {
    /// @dev Returns a draw below `bound`.
    function below(uint256 bound) internal view returns (uint256) {
        return vm.randomUint(0, bound - 1);
    }

    /// @dev Returns up to `maxLength` random bytes.
    function randomBytes(uint256 maxLength) internal view returns (bytes memory) {
        return vm.randomBytes(below(maxLength + 1));
    }

    /// @dev Overwrites up to four words, then sometimes appends bytes, truncates, or overwrites one byte.
    function mutate(bytes memory payload) internal view returns (bytes memory mutated) {
        mutated = bytes.concat(payload);
        uint256 writes = below(5);
        for (uint256 i; i < writes && mutated.length >= 32; ++i) {
            uint256 offset = below(8) != 0 ? below(mutated.length / 32) * 32 : below(mutated.length - 31);
            _storeWord(mutated, offset, _pickWord(mutated, uint256(LibBytes.load(mutated, offset))));
        }
        uint256 edit = below(16);
        if (edit == 0) {
            bytes memory extra = below(2) == 0 ? new bytes(1 + below(96)) : randomBytes(96);
            mutated = bytes.concat(mutated, extra);
        } else if (edit == 1 && mutated.length > 0) {
            uint256 cut = 1 + below(mutated.length < 64 ? mutated.length : 64);
            mutated = LibBytes.truncate(mutated, mutated.length - cut);
        } else if (edit == 2 && mutated.length > 0) {
            mutated[below(mutated.length)] = bytes1(uint8(vm.randomUint()));
        }
    }

    /// @dev A replacement for `current`, a word of `data`, biased towards offsets, lengths and words at type edges.
    function _pickWord(bytes memory data, uint256 current) private view returns (uint256) {
        uint256 length = data.length;
        uint256 kind = below(16);
        uint256 entropy = vm.randomUint();
        // An aligned offset within the data or up to one word past it.
        if (kind == 0) return 32 * (entropy % (length / 32 + 2));
        // Any offset within the data or up to one word past it.
        if (kind == 1) return entropy % (length + 33);
        // An offset at the end of the data.
        if (kind == 2) {
            uint256 choice = entropy % 5;
            if (choice == 0) return length >= 32 ? length - 32 : 0;
            if (choice == 1) return length;
            if (choice == 2) return length >= 64 ? length - 64 : 0;
            if (choice == 3) return length + 32;
            return length >= 4 ? length - 4 : 0;
        }
        // Another word of the data.
        if (kind == 3) return uint256(LibBytes.load(data, (entropy % (length / 32)) * 32));
        // The word moved by -3 to +3 words, wrapping below zero.
        if (kind == 4) {
            unchecked {
                return current + 32 * (entropy % 7) - 96;
            }
        }
        // One bit flipped.
        if (kind == 5) return current ^ (uint256(1) << (entropy % 256));
        // Negative as a signed word.
        if (kind == 6) return (uint256(1) << 255) + entropy % 64;
        // A negative offset of one to four words.
        if (kind == 7) return uint256(-int256(32 * (1 + entropy % 4)));
        // A length at or past Solidity's 64-bit bound.
        if (kind == 8) {
            uint256 choice = entropy % 4;
            if (choice == 0) return type(uint64).max;
            if (choice == 1) return uint256(type(uint64).max) + 1;
            if (choice == 2) return uint256(1) << (64 + (entropy >> 8) % 192);
            return type(uint256).max;
        }
        // A small count.
        if (kind == 9) return entropy % 17;
        // Any word.
        if (kind == 10) return entropy;
        // Dirty high bytes.
        if (kind == 11) return current | ((1 + entropy % 255) << (8 * (1 + (entropy >> 8) % 31)));
        // A word at the edge of a narrow type.
        if (kind == 12) {
            uint256 choice = entropy % 6;
            if (choice == 0) return type(uint256).max;
            if (choice == 1) return 0xff;
            if (choice == 2) return 0x8000;
            if (choice == 3) return (uint256(uint24(entropy >> 8)) << 232) | 1;
            if (choice == 4) return 0x100 | (entropy & 0xff);
            return 2;
        }
        // An unaligned offset.
        if (kind == 13) {
            unchecked {
                return entropy % 2 == 0 ? current + 1 : current - 1;
            }
        }
        // A zero word.
        return 0;
    }

    /// @dev Writes `word` at `offset` within `data`. Requires `offset + 32 <= data.length`.
    function _storeWord(bytes memory data, uint256 offset, uint256 word) private pure {
        assembly ("memory-safe") {
            mstore(add(add(data, 32), offset), word)
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Descriptor } from "./Descriptor.sol";
import { DescriptorFormat as DF } from "./DescriptorFormat.sol";
import { TypeDesc } from "./TypeDesc.sol";
import { DynamicBufferLib } from "solady/utils/DynamicBufferLib.sol";

/// @notice Internal state for drafting a parameter descriptor.
struct DescriptorDraft {
    /// The buffer holding the descriptor bytes being built.
    DynamicBufferLib.DynamicBuffer buffer;
    /// The number of top-level parameters added so far.
    uint8 paramCount;
}

using DescriptorBuilder for DescriptorDraft global;

library DescriptorBuilder {
    using DynamicBufferLib for DynamicBufferLib.DynamicBuffer;

    /*/////////////////////////////////////////////////////////////////////////
                                     ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when attempting to build a malformed descriptor.
    error MalformedDescriptor();

    /// @notice Thrown when the type string is malformed.
    error MalformedTypeString();

    /// @notice Thrown when an unknown type is encountered.
    error UnknownType();

    /*/////////////////////////////////////////////////////////////////////////
                                     FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a new descriptor draft instance.
    /// @return draft The initialized draft.
    function create() internal pure returns (DescriptorDraft memory draft) {
        draft.buffer = draft.buffer.pUint8(DF.VERSION).pUint8(0);
    }

    /// @notice Finalizes and returns the descriptor.
    /// @param draft The draft to finalize.
    /// @return desc The descriptor bytes.
    function build(DescriptorDraft memory draft) internal pure returns (bytes memory desc) {
        desc = draft.buffer.data;
        require(desc.length >= DF.HEADER_SIZE, MalformedDescriptor());
        desc[DF.HEADER_PARAMCOUNT_OFFSET] = bytes1(draft.paramCount);
    }

    /// @notice Adds a top-level parameter with the given type descriptor.
    /// @param draft The draft to update.
    /// @param typeDesc The type descriptor bytes for the parameter.
    /// @return The updated draft.
    function add(DescriptorDraft memory draft, bytes memory typeDesc) internal pure returns (DescriptorDraft memory) {
        require(typeDesc.length != 0, TypeDesc.EmptyType());
        require(draft.paramCount != type(uint8).max, Descriptor.TooManyParams());
        draft.buffer = draft.buffer.p(typeDesc);
        unchecked {
            draft.paramCount++;
        }
        return draft;
    }

    /// @notice Builds a descriptor from a comma-separated type string.
    /// @dev Parses types like "address,uint256,(bool,bytes32)[],string".
    /// @param typesCsv The comma-separated type string (no function name, no outer parentheses).
    /// @return desc The descriptor bytes.
    function fromTypes(string memory typesCsv) internal pure returns (bytes memory) {
        bytes memory input = bytes(typesCsv);
        if (input.length == 0) return create().build();
        DescriptorDraft memory draft = create();
        uint256 cursor = 0;
        uint256 inputLength = input.length;
        while (cursor < inputLength) {
            uint256 typeEnd = _findTypeEnd(input, cursor);
            bytes memory typeDesc = _parseType(input, cursor, typeEnd);
            draft = draft.add(typeDesc);
            cursor = typeEnd;
            if (cursor < inputLength) {
                require(input[cursor] == ",", MalformedTypeString());
                cursor++;
                require(cursor < inputLength, MalformedTypeString());
            }
        }
        return draft.build();
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Finds the end of a type starting at `cursor`, respecting nested parentheses and brackets.
    function _findTypeEnd(bytes memory input, uint256 cursor) private pure returns (uint256) {
        uint256 depth = 0;
        uint256 i = cursor;
        uint256 inputLength = input.length;
        while (i < inputLength) {
            bytes1 char = input[i];
            if (char == "(" || char == "[") {
                depth++;
            } else if (char == ")" || char == "]") {
                require(depth > 0, MalformedTypeString());
                depth--;
            } else if (char == "," && depth == 0) {
                break;
            }
            unchecked {
                i++;
            }
        }
        require(depth == 0, MalformedTypeString());
        return i;
    }

    /// @dev Parses a single type from `input[start:end]` and returns its type descriptor.
    function _parseType(bytes memory input, uint256 start, uint256 end) private pure returns (bytes memory) {
        require(end > start, MalformedTypeString());

        uint256 baseEnd = end;
        uint256 arrayStart = end;

        // Scan backwards to find where array suffixes begin, so the base type can be
        // parsed first, then suffixes applied left-to-right (innermost array first).
        if (input[end - 1] == "]") {
            uint256 i = end;
            while (i > start) {
                unchecked {
                    --i;
                }
                if (input[i] == "]") {
                    // Find matching '['.
                    uint256 bracketStart = i;
                    while (bracketStart > start && input[bracketStart] != "[") {
                        unchecked {
                            --bracketStart;
                        }
                    }
                    require(input[bracketStart] == "[", MalformedTypeString());
                    arrayStart = bracketStart;
                    baseEnd = bracketStart;
                    i = bracketStart;
                } else {
                    break;
                }
            }
        }

        // Parse the base type.
        bytes memory baseDesc = _parseBaseType(input, start, baseEnd);

        // Apply array suffixes from left to right.
        uint256 cursor = arrayStart;
        while (cursor < end) {
            require(input[cursor] == "[", MalformedTypeString());
            uint256 closeBracket = cursor + 1;
            while (closeBracket < end && input[closeBracket] != "]") {
                unchecked {
                    closeBracket++;
                }
            }
            require(closeBracket < end && input[closeBracket] == "]", MalformedTypeString());

            if (closeBracket == cursor + 1) {
                // Dynamic array [].
                baseDesc = TypeDesc.array_(baseDesc);
            } else {
                // Static array [N].
                uint256 length = _parseUint(input, cursor + 1, closeBracket);
                require(length <= type(uint16).max, MalformedTypeString());
                // forge-lint: disable-next-line(unsafe-typecast)
                baseDesc = TypeDesc.array_(baseDesc, uint16(length));
            }
            cursor = closeBracket + 1;
        }

        return baseDesc;
    }

    /// @dev Parses a base type (non-array) from `input[start:end]`.
    function _parseBaseType(bytes memory input, uint256 start, uint256 end) private pure returns (bytes memory) {
        require(end > start, MalformedTypeString());
        uint256 length = end - start;
        bytes1 firstChar = input[start];

        // forgefmt: disable-next-item
        if (firstChar == "a") {
            if (length == 7 && _eq(input, start, end, "address")) return TypeDesc.address_();
        }
        else if (firstChar == "u") {
            if (length == 7 && _eq(input, start, end, "uint256")) return TypeDesc.uint256_();
            if (length >= 5 && _eq(input, start, start + 4, "uint")) {
                uint256 bits = _parseUint(input, start + 4, end);
                require(bits >= 8 && bits <= 256 && bits % 8 == 0, UnknownType());
                // forge-lint: disable-next-line(unsafe-typecast)
                return TypeDesc.uintN_(uint16(bits));
            }
        } else if (firstChar == "b") {
            if (length == 4 && _eq(input, start, end, "bool")) return TypeDesc.bool_();
            if (length == 7 && _eq(input, start, end, "bytes32")) return TypeDesc.bytes32_();
            if (length >= 5 && _eq(input, start, start + 5, "bytes")) {
                if (length == 5) return TypeDesc.bytes_();
                uint256 byteCount = _parseUint(input, start + 5, end);
                require(byteCount >= 1 && byteCount <= 32, UnknownType());
                // forge-lint: disable-next-line(unsafe-typecast)
                return TypeDesc.bytesN_(uint8(byteCount));
            }
        } else if (firstChar == "s") {
            if (length == 6 && _eq(input, start, end, "string")) return TypeDesc.string_();
        } else if (firstChar == "(") {
            require(input[end - 1] == ")", MalformedTypeString());
            return _parseTuple(input, start + 1, end - 1);
        } else if (firstChar == "i") {
            if (length == 6 && _eq(input, start, end, "int256")) return TypeDesc.int256_();
            if (length >= 4 && _eq(input, start, start + 3, "int")) {
                uint256 bits = _parseUint(input, start + 3, end);
                require(bits >= 8 && bits <= 256 && bits % 8 == 0, UnknownType());
                // forge-lint: disable-next-line(unsafe-typecast)
                return TypeDesc.intN_(uint16(bits));
            }
        } else if (firstChar == "f") {
            if (length == 8 && _eq(input, start, end, "function")) return TypeDesc.function_();
        }

        revert UnknownType();
    }

    /// @dev Parses tuple fields from `input[start:end]` (content between parentheses).
    function _parseTuple(bytes memory input, uint256 start, uint256 end) private pure returns (bytes memory) {
        if (start == end) {
            // Empty tuple ().
            bytes[] memory empty = new bytes[](0);
            return TypeDesc.tuple_(empty);
        }

        // Allocate worst-case (each field is at least 1 char + 1 comma), fill in single pass, then trim.
        bytes[] memory fields = new bytes[]((end - start + 1) / 2 + 1);
        uint256 fieldCount;
        uint256 fieldStart = start;
        uint256 depth;

        for (uint256 i = start; i <= end; i++) {
            bool isEnd = (i == end);
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes1 char = isEnd ? bytes1(",") : input[i];

            if (char == "(" || char == "[") {
                depth++;
            } else if (char == ")" || char == "]") {
                depth--;
            } else if (char == "," && depth == 0) {
                fields[fieldCount++] = _parseType(input, fieldStart, i);
                fieldStart = i + 1;
            }
        }

        assembly ("memory-safe") {
            mstore(fields, fieldCount)
        }
        return TypeDesc.tuple_(fields);
    }

    /// @dev Parses an unsigned integer from `input[start:end]`.
    function _parseUint(bytes memory input, uint256 start, uint256 end) private pure returns (uint256 result) {
        require(end > start, MalformedTypeString());
        for (uint256 i = start; i < end; i++) {
            bytes1 char = input[i];
            require(char >= "0" && char <= "9", MalformedTypeString());
            unchecked {
                result = result * 10 + (uint8(char) - 48);
            }
        }
    }

    /// @dev Compares `input[start:end]` to `literal` without allocating.
    function _eq(
        bytes memory input,
        uint256 start,
        uint256 end,
        string memory literal
    )
        private
        pure
        returns (bool result)
    {
        assembly {
            let length := sub(end, start)
            let literalLength := mload(literal)

            if eq(length, literalLength) {
                let inputPtr := add(add(input, 0x20), start)
                let litPtr := add(literal, 0x20)
                result := 1

                for { let i := 0 } lt(i, length) { i := add(i, 0x20) } {
                    let remaining := sub(length, i)
                    let w1 := mload(add(inputPtr, i))
                    let w2 := mload(add(litPtr, i))

                    if lt(remaining, 32) {
                        let shift := shl(3, sub(32, remaining))
                        let mask := not(sub(shl(shift, 1), 1))
                        w1 := and(w1, mask)
                        w2 := and(w2, mask)
                    }

                    if iszero(eq(w1, w2)) {
                        result := 0
                        break
                    }
                }
            }
        }
    }
}

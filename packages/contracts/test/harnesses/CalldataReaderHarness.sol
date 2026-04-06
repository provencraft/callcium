// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CalldataReader } from "src/CalldataReader.sol";

/// @notice Harness contract to expose CalldataReader internal functions for testing.
contract CalldataReaderHarness {
    function locate(
        bytes memory desc,
        bytes calldata callData,
        bytes memory path,
        CalldataReader.Config memory cfg
    )
        external
        pure
        returns (CalldataReader.Location memory)
    {
        return CalldataReader.locate(desc, callData, path, cfg);
    }

    function loadScalar(CalldataReader.Location memory loc, bytes calldata callData) external pure returns (bytes32) {
        return CalldataReader.loadScalar(loc, callData);
    }

    function loadSlice(
        CalldataReader.Location memory loc,
        bytes calldata callData
    )
        external
        pure
        returns (CalldataReader.DynamicSlice memory)
    {
        return CalldataReader.loadSlice(loc, callData);
    }

    function arrayShape(
        bytes memory desc,
        bytes calldata callData,
        bytes memory path,
        CalldataReader.Config memory cfg
    )
        external
        pure
        returns (CalldataReader.ArrayShape memory)
    {
        return CalldataReader.arrayShape(desc, callData, path, cfg);
    }

    function arrayShape(
        bytes memory desc,
        bytes calldata callData,
        CalldataReader.Location memory location
    )
        external
        pure
        returns (CalldataReader.ArrayShape memory)
    {
        return CalldataReader.arrayShape(desc, callData, location);
    }

    function arrayElementAt(
        CalldataReader.ArrayShape memory shape,
        uint256 elementIndex,
        bytes calldata callData
    )
        external
        pure
        returns (CalldataReader.Location memory)
    {
        return CalldataReader.arrayElementAt(shape, elementIndex, callData);
    }

    function tupleField(
        bytes memory desc,
        CalldataReader.Location memory loc,
        uint16 fieldIndex,
        bytes calldata callData
    )
        external
        pure
        returns (CalldataReader.Location memory)
    {
        return CalldataReader.tupleField(desc, loc, fieldIndex, callData);
    }
}

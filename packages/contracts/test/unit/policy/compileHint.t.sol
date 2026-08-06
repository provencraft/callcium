// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyTest } from "../Policy.t.sol";

import { Path } from "src/Path.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

contract CompileHintTest is PolicyTest {
    /// @dev Returns the descriptor for a function signature.
    function _desc(string memory signature) private pure returns (bytes memory) {
        return PolicyBuilder.create(signature).data.descriptor;
    }

    /// @dev Compiles the hint for `path` against the descriptor of `signature`.
    function _compile(string memory signature, bytes memory path) private view returns (bytes memory) {
        return harness.compileHint(_desc(signature), path);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 STATIC LAYOUT
    /////////////////////////////////////////////////////////////////////////*/

    function test_FirstArgument() public view {
        assertEq(_compile("foo(uint256)", Path.encode(0)), hex"0000000020");
    }

    function test_SecondArgumentSkipsPrecedingHead() public view {
        assertEq(_compile("foo(uint256,address)", Path.encode(1)), hex"0000002041");
    }

    function test_DynamicSiblingOccupiesOneWord() public view {
        assertEq(_compile("foo(bytes,uint256)", Path.encode(1)), hex"0000002020");
    }

    function test_StaticTupleField() public view {
        assertEq(_compile("foo((address,uint256))", Path.encode(0, 1)), hex"0000002020");
    }

    function test_StaticArrayElement() public view {
        assertEq(_compile("foo(uint256[3])", Path.encode(0, 2)), hex"0000004020");
    }

    function test_NestedStaticTuple() public view {
        assertEq(_compile("foo(((uint256,address),uint256))", Path.encode(0, 0, 1)), hex"0000002041");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                DYNAMIC TARGETS
    /////////////////////////////////////////////////////////////////////////*/

    function test_BytesTargetAddressesHeadSlot() public view {
        assertEq(_compile("foo(uint256,bytes)", Path.encode(1)), hex"0000002070");
    }

    function test_DynamicArrayTarget() public view {
        assertEq(_compile("foo(uint256[])", Path.encode(0)), hex"0000000081");
    }

    /*/////////////////////////////////////////////////////////////////////////
                               QUANTIFIED LAYOUT
    /////////////////////////////////////////////////////////////////////////*/

    function test_QuantifierOverDynamicArray() public view {
        assertEq(_compile("foo(uint256[])", Path.encode(0, Path.ALL)), hex"00000000000000200000000020");
    }

    function test_QuantifierCarriesArrayHead() public view {
        assertEq(_compile("foo(uint256,address[])", Path.encode(1, Path.ANY)), hex"00000020000000200000000041");
    }

    function test_QuantifierWithSuffix() public view {
        // Elements are (address, uint256): stride 64, target field at 32 within the element.
        assertEq(
            _compile("foo((address,uint256)[])", Path.encode(0, Path.ALL_OR_EMPTY, 1)), hex"00000000000000400000002020"
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    SENTINEL
    /////////////////////////////////////////////////////////////////////////*/

    function test_QuantifierOverStaticArray() public view {
        assertEq(_compile("foo(uint256[3])", Path.encode(0, Path.ALL)), SENTINEL_HINT);
    }

    function test_QuantifierOverDynamicElements() public view {
        assertEq(_compile("foo(bytes[])", Path.encode(0, Path.ALL)), SENTINEL_HINT);
    }

    function test_QuantifierOverNonArray() public view {
        assertEq(_compile("foo((address,uint256))", Path.encode(0, Path.ALL)), SENTINEL_HINT);
    }

    function test_ConcreteIndexIntoDynamicArray() public view {
        assertEq(_compile("foo(uint256[])", Path.encode(0, 1)), SENTINEL_HINT);
    }

    function test_FieldOfDynamicTuple() public view {
        assertEq(_compile("foo((bytes,uint256))", Path.encode(0, 1)), SENTINEL_HINT);
    }

    function test_ArgumentIndexOutOfBounds() public view {
        assertEq(_compile("foo(uint256)", Path.encode(1)), SENTINEL_HINT);
    }

    function test_TupleFieldOutOfBounds() public view {
        assertEq(_compile("foo((address,uint256))", Path.encode(0, 2)), SENTINEL_HINT);
    }

    function test_StaticArrayIndexOutOfBounds() public view {
        assertEq(_compile("foo(uint256[3])", Path.encode(0, 3)), SENTINEL_HINT);
    }

    function test_StepIntoElementary() public view {
        assertEq(_compile("foo(uint256)", Path.encode(0, 0)), SENTINEL_HINT);
    }
}

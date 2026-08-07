// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyTest } from "../Policy.t.sol";

import { Path } from "src/Path.sol";
import { Policy } from "src/Policy.sol";
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
                                  HOP-FREE PATHS
    /////////////////////////////////////////////////////////////////////////*/

    function test_FirstArgument() public view {
        assertEq(_compile("foo(uint256)", Path.encode(0)), hex"0000000000000020");
    }

    function test_SecondArgumentSkipsPrecedingHead() public view {
        assertEq(_compile("foo(uint256,address)", Path.encode(1)), hex"0000000020000041");
    }

    function test_DynamicSiblingOccupiesOneWord() public view {
        assertEq(_compile("foo(bytes,uint256)", Path.encode(1)), hex"0000000020000020");
    }

    function test_StaticTupleField() public view {
        assertEq(_compile("foo((address,uint256))", Path.encode(0, 1)), hex"0000000020000020");
    }

    function test_StaticArrayElement() public view {
        assertEq(_compile("foo(uint256[3])", Path.encode(0, 2)), hex"0000000040000020");
    }

    function test_NestedStaticTuple() public view {
        assertEq(_compile("foo(((uint256,address),uint256))", Path.encode(0, 0, 1)), hex"0000000020000041");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                INDIRECTED TARGETS
    /////////////////////////////////////////////////////////////////////////*/

    function test_BytesTargetEntersItsPayload() public view {
        assertEq(_compile("foo(bytes)", Path.encode(0)), hex"0100000000ffff000000000000000070");
    }

    function test_BytesTargetPastAStaticSibling() public view {
        assertEq(_compile("foo(uint256,bytes)", Path.encode(1)), hex"0100000020ffff000000000000000070");
    }

    function test_DynamicArrayTargetCarriesItsStride() public view {
        assertEq(_compile("foo(uint256[])", Path.encode(0)), hex"0100000000ffff000000000000400181");
    }

    function test_DynamicArrayOfDynamicElementsTarget() public view {
        assertEq(_compile("foo(bytes[])", Path.encode(0)), hex"0100000000ffff000000000000c00181");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    HOP CHAINS
    /////////////////////////////////////////////////////////////////////////*/

    function test_FieldOfDynamicTuple() public view {
        assertEq(_compile("foo((address,uint256,bytes))", Path.encode(0, 0)), hex"0100000000ffff000000000000000041");
    }

    function test_FieldOfDynamicTuplePastADynamicSibling() public view {
        // The bytes field ahead of the target occupies one offset word in the tuple head.
        assertEq(_compile("foo((bytes,uint256))", Path.encode(0, 1)), hex"0100000000ffff000000000020000020");
    }

    function test_ConcreteIndexIntoDynamicArray() public view {
        assertEq(_compile("foo(uint256[])", Path.encode(0, 1)), hex"0200000000ffff0000000000000001400100000000000020");
    }

    function test_ConsecutiveArrayCrossings() public view {
        assertEq(
            _compile("foo(uint256[][])", Path.encode(0, 1, 2)),
            hex"0300000000ffff0000000000000001c001000000000002400100000000000020"
        );
    }

    function test_StaticArrayOfDynamicElements() public view {
        assertEq(_compile("foo(bytes[3])", Path.encode(0, 2)), hex"0200000000ffff0000000000000002800100000000000070");
    }

    function test_NestedDynamicTuples() public view {
        assertEq(
            _compile("foo(((bytes,uint256),uint256))", Path.encode(0, 0, 1)),
            hex"0200000000ffff000000000000ffff000000000020000020"
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                                QUANTIFIED LAYOUT
    /////////////////////////////////////////////////////////////////////////*/

    function test_QuantifierOverDynamicArray() public view {
        assertEq(
            _compile("foo(uint256[])", Path.encode(0, Path.ALL)),
            hex"4100000000ffff000000000000000040010000000000000020"
        );
    }

    function test_QuantifierCarriesArrayDelta() public view {
        assertEq(
            _compile("foo(uint256,address[])", Path.encode(1, Path.ANY)),
            hex"8100000020ffff000000000000000040010000000000000041"
        );
    }

    function test_QuantifierOverStaticArrayDeclaresItsCount() public view {
        assertEq(_compile("foo(uint256[3])", Path.encode(0, Path.ALL)), hex"4000000000000300010000000000000020");
    }

    function test_QuantifierOverDynamicElements() public view {
        assertEq(
            _compile("foo(bytes[])", Path.encode(0, Path.ALL)), hex"4100000000ffff0000000000000000c0010000000000000070"
        );
    }

    function test_QuantifierWithSuffix() public view {
        // Elements are (address, uint256): stride two words, target field one word into the element.
        assertEq(
            _compile("foo((address,uint256)[])", Path.encode(0, Path.ALL, 1)),
            hex"4100000000ffff000000000000000040020000000020000020"
        );
    }

    function test_QuantifierOverDynamicElementsWithSuffix() public view {
        assertEq(
            _compile("foo((bytes,uint256)[])", Path.encode(0, Path.ALL, 1)),
            hex"4100000000ffff0000000000000000c0010000000020000020"
        );
    }

    /*/////////////////////////////////////////////////////////////////////////
                                UNCOMPILABLE PATHS
    /////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_ArgumentIndexOutOfBounds() public {
        vm.expectRevert(abi.encodeWithSelector(Policy.UncompilablePath.selector, 0));
        _compile("foo(uint256)", Path.encode(1));
    }

    function test_RevertWhen_TupleFieldOutOfBounds() public {
        vm.expectRevert(abi.encodeWithSelector(Policy.UncompilablePath.selector, 1));
        _compile("foo((address,uint256))", Path.encode(0, 2));
    }

    function test_RevertWhen_StaticArrayIndexOutOfBounds() public {
        vm.expectRevert(abi.encodeWithSelector(Policy.UncompilablePath.selector, 1));
        _compile("foo(uint256[3])", Path.encode(0, 3));
    }

    function test_RevertWhen_StepIntoElementary() public {
        vm.expectRevert(abi.encodeWithSelector(Policy.UncompilablePath.selector, 1));
        _compile("foo(uint256)", Path.encode(0, 0));
    }

    function test_RevertWhen_QuantifierOverNonArray() public {
        vm.expectRevert(abi.encodeWithSelector(Policy.UncompilablePath.selector, 1));
        _compile("foo((address,uint256))", Path.encode(0, Path.ALL));
    }

    function test_RevertWhen_NestedQuantifiers() public {
        vm.expectRevert(abi.encodeWithSelector(Policy.UncompilablePath.selector, 2));
        _compile("foo(uint256[][])", Path.encode(0, Path.ALL, Path.ALL));
    }
}

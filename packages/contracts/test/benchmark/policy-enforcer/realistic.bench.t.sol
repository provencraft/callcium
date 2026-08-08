// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { arg, msgSender } from "src/Constraint.sol";
import { Path } from "src/Path.sol";
import { PolicyBuilder } from "src/PolicyBuilder.sol";

import { PolicyEnforcerBench } from "../PolicyEnforcer.bench.t.sol";

/// @dev End-to-end cost of policies over signatures with the argument shapes real ABIs produce,
///      as opposed to the single-constraint scenarios that isolate one cost each. Every policy
///      here is accepted by the strict builder, so the corpus also records which argument shapes
///      resolve through a hint and which fall back to descriptor traversal.
contract RealisticBench is PolicyEnforcerBench {
    Fixture internal tokenApproval;
    Fixture internal swapStaticParams;
    Fixture internal swapWithPath;
    Fixture internal batchTransfer;

    function setUp() public override {
        super.setUp();
        _buildTokenApproval();
        _buildSwapStaticParams();
        _buildSwapWithPath();
        _buildBatchTransfer();
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    BUILDERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Spender allowlist and an amount ceiling on a token approval. Elementary arguments,
    /// so every calldata rule resolves through a hint.
    function _buildTokenApproval() private {
        string memory sig = "approve(address,uint256)";
        address[] memory spenders = new address[](2);
        spenders[0] = address(1);
        spenders[1] = address(2);

        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.create(sig)
            .add(msgSender().eq(address(this)))
            .add(arg(0).isIn(spenders))
            .add(arg(1).lte(uint256(1_000_000e18)))
            .build();

        tokenApproval = _fixture(policy, abi.encodeWithSignature(sig, spenders[0], uint256(1000e18)));
    }

    /// @dev Token pair, recipient and amount ceiling on a swap whose parameters are one static
    /// struct. A static struct places its fields at fixed offsets, so the rules stay hinted.
    function _buildSwapStaticParams() private {
        string memory sig = "exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))";

        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.create(sig)
            .add(arg(0, 0).eq(address(1)))
            .add(arg(0, 1).eq(address(2)))
            .add(arg(0, 3).eq(address(this)))
            .add(arg(0, 4).lte(uint256(1000e18)))
            .build();

        // A static struct encodes as its fields laid out inline, which is what passing them
        // flat produces. A dynamic struct would additionally need its head offset.
        bytes memory callData = abi.encodeWithSignature(
            sig, address(1), address(2), uint24(3000), address(this), uint256(500e18), uint256(0), uint160(0)
        );

        swapStaticParams = _fixture(policy, callData);
    }

    /// @dev The same intent over a swap that carries an encoded route. The `bytes` member makes
    /// the whole struct dynamic, so none of these rules compiles to a hint.
    function _buildSwapWithPath() private {
        string memory sig = "exactInput((bytes,address,uint256,uint256))";

        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.create(sig)
            .add(arg(0, 0).lengthGte(43))
            .add(arg(0, 1).eq(address(this)))
            .add(arg(0, 2).lte(uint256(1000e18)))
            .build();

        // A single-hop route: two 20-byte tokens either side of a 3-byte pool fee.
        bytes memory route = new bytes(43);
        bytes memory callData = _encodeDynTupleArg(sig, abi.encode(route, address(this), uint256(500e18), uint256(0)));

        swapWithPath = _fixture(policy, callData);
    }

    /// @dev Recipient, batch size and a ceiling on every token id. The quantified array holds
    /// static elements and sits behind static arguments, so it addresses through a hint.
    function _buildBatchTransfer() private {
        string memory sig = "safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)";

        // forgefmt: disable-next-item
        bytes memory policy = PolicyBuilder.create(sig)
            .add(arg(1).eq(address(this)))
            .add(arg(2).lengthLte(10))
            .add(arg(2, Path.ALL).lte(uint256(1000)))
            .build();

        uint256[] memory ids = _uintArray(8);
        uint256[] memory amounts = _uintArray(8);
        bytes memory callData = abi.encodeWithSignature(sig, address(1), address(this), ids, amounts, hex"");

        batchTransfer = _fixture(policy, callData);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   BENCHMARKS
    /////////////////////////////////////////////////////////////////////////*/

    function test_TokenApproval() public {
        _benchCheckPasses(tokenApproval, "realistic_token_approval");
    }

    function test_SwapStaticParams() public {
        _benchCheckPasses(swapStaticParams, "realistic_swap_static_params");
    }

    function test_SwapWithPath() public {
        _benchCheckPasses(swapWithPath, "realistic_swap_with_path");
    }

    function test_BatchTransfer() public {
        _benchCheckPasses(batchTransfer, "realistic_batch_transfer");
    }
}

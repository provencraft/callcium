// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { arg, blockTimestamp, msgSender, msgValue, txOrigin } from "src/Constraint.sol";
import { OpCode } from "src/OpCode.sol";
import { PolicyBuilder, PolicyDraft } from "src/PolicyBuilder.sol";

/// @dev Generates policy blobs for docs/tools/policy-inspector/tests/explainer-blobs.json.
///      Run: forge script script/PolicyInspectorFixtureGenerator.s.sol --via-ir -v
// forgefmt: disable-next-item
contract PolicyInspectorFixtureGenerator is Script {
    using PolicyBuilder for PolicyDraft;

    string private constant OBJ = "blobs";

    function run() external {
        // Operand decoding.
        _add("EQ_UINT256", PolicyBuilder.create("f(uint256)").add(arg(0).eq(uint256(42))).build());
        _add("EQ_UINT8", PolicyBuilder.create("f(uint8)").add(arg(0).eq(uint256(255))).build());
        _add("EQ_INT256_POS", PolicyBuilder.create("f(int256)").add(arg(0).eq(int256(100))).build());
        _add("EQ_INT256_NEG", PolicyBuilder.create("f(int256)").add(arg(0).eq(int256(-1))).build());
        _add("EQ_INT256_BOUNDARY", PolicyBuilder.create("f(int256)").add(arg(0).eq(int256(-128))).build());
        _add("EQ_INT8", PolicyBuilder.create("f(int8)").add(arg(0).eq(int8(-1))).build());
        _add("EQ_BOOL_TRUE", PolicyBuilder.create("f(bool)").add(arg(0).eq(true)).build());
        _add("EQ_BOOL_FALSE", PolicyBuilder.create("f(bool)").add(arg(0).eq(false)).build());
        _add("EQ_ADDRESS", PolicyBuilder.create("f(address)").add(arg(0).eq(address(1))).build());
        _add("EQ_BYTES1", PolicyBuilder.create("f(bytes1)").add(arg(0).eq(bytes32(bytes1(0xff)))).build());
        _add("EQ_BYTES32", PolicyBuilder.create("f(bytes32)").add(arg(0).eq(bytes32(uint256(0xab) << 248))).build());

        // Operator types.
        uint256[] memory inSet = new uint256[](3);
        inSet[0] = 1;
        inSet[1] = 2;
        inSet[2] = 3;
        _add("IN_UINT256", PolicyBuilder.create("f(uint256)").add(arg(0).isIn(inSet)).build());
        _add("BETWEEN_UINT256", PolicyBuilder.create("f(uint256)").add(arg(0).between(uint256(10), uint256(100))).build());
        _add("NEQ_UINT256", PolicyBuilder.create("f(uint256)").add(arg(0).neq(uint256(42))).build());
        _add("NGT_UINT256", PolicyBuilder.create("f(uint256)").add(arg(0).addOp(OpCode.GT | OpCode.NOT, abi.encode(uint256(99)))).build());
        _add("LENGTH_EQ", PolicyBuilder.create("f(uint256[])").add(arg(0).lengthEq(uint256(5))).build());

        // Scope and path.
        _add("CALLDATA_ARG1", PolicyBuilder.create("f(uint256,address)").add(arg(1).eq(address(1))).build());
        _add("CTX_MSG_SENDER", PolicyBuilder.create("f(uint256)").add(msgSender().eq(address(1))).build());
        _add("CTX_MSG_VALUE", PolicyBuilder.create("f(uint256)").add(msgValue().eq(uint256(1))).build());
        _add("CTX_BLOCK_TIMESTAMP", PolicyBuilder.create("f(uint256)").add(blockTimestamp().eq(uint256(1))).build());
        _add("CTX_TX_ORIGIN", PolicyBuilder.create("f(uint256)").add(txOrigin().eq(address(1))).build());
        _add("TUPLE_FIELD", PolicyBuilder.create("f((uint256,address))").add(arg(0, 1).eq(address(1))).build());
        _add("DYNAMIC_ARRAY_ELEM", PolicyBuilder.create("f(uint256[])").add(arg(0, 0).eq(uint256(7))).build());

        // Structure.
        _add("MULTI_GROUP", PolicyBuilder.create("f(uint256)").add(arg(0).eq(uint256(1))).or().add(arg(0).eq(uint256(2))).build());
        _add("MULTI_CONSTRAINT", PolicyBuilder.create("f(uint256)").add(arg(0).gt(uint256(0))).add(msgSender().eq(address(1))).build());
        _add("MULTI_RULE", PolicyBuilder.create("f(uint256)").add(arg(0).gt(uint256(10)).lt(uint256(100))).build());
        _add("MULTI_PARAM", PolicyBuilder.create("f(uint256,address,bool)").add(arg(0).eq(uint256(1))).build());

        // Complex multi-group with varying constraint counts per group.
        {
            uint256[] memory allowed = new uint256[](2);
            allowed[0] = 100;
            allowed[1] = 200;
            _add("COMPLEX_MULTI_GROUP", PolicyBuilder
                .create("f(uint256)")
                // Group 1: 3 constraints (range + sender + value).
                .add(arg(0).between(uint256(1), uint256(1000)))
                .add(msgSender().eq(address(1)))
                .add(msgValue().lte(uint256(1 ether)))
                .or()
                // Group 2: 1 constraint (exact match).
                .add(arg(0).eq(uint256(42)))
                .or()
                // Group 3: 2 constraints (set membership + timestamp).
                .add(arg(0).isIn(allowed))
                .add(blockTimestamp().gte(uint256(1700000000)))
                .build()
            );
        }

        // Selectorless.
        _add("SELECTORLESS", PolicyBuilder.createRaw("uint256").add(arg(0).eq(uint256(1))).build());

        // ABI enrichment (approve).
        _add("APPROVE_ARG0", PolicyBuilder.create("approve(address,uint256)").add(arg(0).eq(address(1))).build());
        string memory json = _addLast("APPROVE_ARG1", PolicyBuilder.create("approve(address,uint256)").add(arg(1).eq(uint256(1))).build());

        console2.log(json);
    }

    function _add(string memory key, bytes memory blob) private {
        vm.serializeBytes(OBJ, key, blob);
    }

    function _addLast(string memory key, bytes memory blob) private returns (string memory) {
        return vm.serializeBytes(OBJ, key, blob);
    }
}

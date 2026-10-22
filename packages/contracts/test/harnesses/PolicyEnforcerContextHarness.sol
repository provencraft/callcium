// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyEnforcer } from "src/PolicyEnforcer.sol";
import { PolicyFormat as PF } from "src/PolicyFormat.sol";

/// @notice Harness contract that runs PolicyEnforcer and reports the context the call ran under.
contract PolicyEnforcerContextHarness {
    /// @dev Payable entry point returning the verdict and the context properties the call observed, by property ID.
    function checkWithContext(
        bytes memory policy,
        bytes calldata callData
    )
        external
        payable
        returns (bool ok, bytes32[] memory context)
    {
        ok = PolicyEnforcer.check(policy, callData);
        context = new bytes32[](PF.CTX_MAX + 1);
        context[PF.CTX_MSG_SENDER] = bytes32(uint256(uint160(msg.sender)));
        context[PF.CTX_MSG_VALUE] = bytes32(msg.value);
        context[PF.CTX_BLOCK_TIMESTAMP] = bytes32(block.timestamp);
        context[PF.CTX_BLOCK_NUMBER] = bytes32(block.number);
        context[PF.CTX_CHAIN_ID] = bytes32(block.chainid);
        context[PF.CTX_TX_ORIGIN] = bytes32(uint256(uint160(tx.origin)));
        context[PF.CTX_BASE_FEE] = bytes32(block.basefee);
        context[PF.CTX_GAS_PRICE] = bytes32(tx.gasprice);
    }
}

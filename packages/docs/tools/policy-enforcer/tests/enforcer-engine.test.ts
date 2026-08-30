import { ContextProperty, PolicyBuilder, arg, msgSender } from "@callcium/sdk";
import { encodeFunctionData, parseAbi } from "viem";
import { describe, expect, it } from "vitest";
import type { Hex } from "@callcium/sdk";
import { formatViolation } from "../../../lib/format-violation";
import { checkPolicy } from "../enforcer-engine";

///////////////////////////////////////////////////////////////////////////
// Test helpers
///////////////////////////////////////////////////////////////////////////

const abi = parseAbi(["function approve(address spender, uint256 amount) returns (bool)"]);
const spender = "0x1111111254eeb25477b68fb85ed929f73a960582";

function buildApprovePolicy(address: string): Hex {
  return PolicyBuilder.create("approve(address,uint256)").add(arg(0).eq(address)).build();
}

function encodeApprove(address: string, amount: bigint): Hex {
  return encodeFunctionData({ abi, functionName: "approve", args: [address as `0x${string}`, amount] });
}

///////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////

describe("checkPolicy", () => {
  const policy = buildApprovePolicy(spender);

  it("returns pass when calldata matches", () => {
    const result = checkPolicy(policy, encodeApprove(spender, 1000n));
    expect(result.status).toBe("pass");
    expect(result.violations).toEqual([]);
  });

  it("returns fail when calldata does not match", () => {
    const wrong = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045";
    const result = checkPolicy(policy, encodeApprove(wrong, 1000n));
    expect(result.status).toBe("fail");
    expect(result.violations.length).toBeGreaterThan(0);
  });

  it("returns inconclusive when context is missing", () => {
    const sender = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045";
    const policyWithContext = PolicyBuilder.create("approve(address,uint256)")
      .add(arg(0).eq(spender))
      .add(msgSender().eq(sender))
      .build();
    const result = checkPolicy(policyWithContext, encodeApprove(spender, 1000n));
    expect(result.status).toBe("inconclusive");
    expect(result.skipped.length).toBeGreaterThan(0);
  });

  it("returns pass with context provided", () => {
    const sender = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045";
    const policyWithContext = PolicyBuilder.create("approve(address,uint256)")
      .add(arg(0).eq(spender))
      .add(msgSender().eq(sender))
      .build();
    const result = checkPolicy(policyWithContext, encodeApprove(spender, 1000n), {
      msgSender: sender as `0x${string}`,
    });
    expect(result.status).toBe("pass");
  });

  it("names the operand property when an eqCtx rule's context is missing", () => {
    const eqCtxPolicy = PolicyBuilder.create("approve(address,uint256)")
      .add(arg(0).eqCtx(ContextProperty.MSG_SENDER))
      .build();
    const result = checkPolicy(eqCtxPolicy, encodeApprove(spender, 1000n));
    expect(result.status).toBe("inconclusive");
    expect(formatViolation(result.skipped[0], result.params)).toBe("msg.sender not provided (referenced by arg(0))");
  });

  it("returns error for invalid policy hex", () => {
    const result = checkPolicy("0x11111111" as Hex, "0x00000000" as Hex);
    expect(result.status).toBe("error");
    expect(result.errorMessage).toBeDefined();
  });
});

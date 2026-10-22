import {
  type Context,
  ContextProperty,
  type Hex,
  PolicyBuilder,
  PolicyCoder,
  PolicyEnforcer,
  Quantifier,
  arg,
  msgSender,
} from "@callcium/sdk";
import { encodeFunctionData, parseAbi, toFunctionSelector } from "viem";
import { describe, expect, it } from "vitest";
import { formatViolation } from "./format-violation";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

const abi = parseAbi([
  "function f(uint256)",
  "function g(bool)",
  "function h(address)",
  "function k(bytes)",
  "function m(uint256[])",
  "function n((address,uint256)[])",
]);

const ADDRESS_A = "0x0000000000000000000000000000000000000001";
const ADDRESS_B = "0x0000000000000000000000000000000000000002";

/** Enforce `policy` on `callData` and render its first violation. */
function render(policy: Hex, callData: Hex, context?: Context): string {
  const result = PolicyEnforcer.check(policy, callData, context);
  if (result.ok) throw new Error("Policy passed");
  return formatViolation(result.violations[0], PolicyCoder.inspect(policy));
}

const f = (value: bigint) => encodeFunctionData({ abi, functionName: "f", args: [value] });

///////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////

describe("formatViolation", () => {
  it("formats a scalar leaf VALUE_MISMATCH with decimal integer rendering", () => {
    const policy = PolicyBuilder.create("f(uint256)").add(arg(0).lt(1_000_000_000_000_000_000n)).build();
    expect(render(policy, f(105_200_000_000_000_000_000_000n))).toBe(
      "arg(0): < 1000000000000000000 violated by 105200000000000000000000",
    );
  });

  it("braces a set operand list and brackets a range one", () => {
    const isIn = PolicyBuilder.create("f(uint256)")
      .add(arg(0).isIn([1n, 2n]))
      .build();
    const between = PolicyBuilder.create("f(uint256)").add(arg(0).between(1n, 2n)).build();
    expect(render(isIn, f(7n))).toBe("arg(0): in {1, 2} violated by 7");
    expect(render(between, f(7n))).toBe("arg(0): between [1, 2] violated by 7");
  });

  it("formats a context VALUE_MISMATCH with checksummed address rendering", () => {
    const policy = PolicyBuilder.create("f(uint256)").add(msgSender().eq(ADDRESS_A)).build();
    const context = { msgSender: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045" } as const;
    expect(render(policy, f(0n), context)).toBe(
      "msg.sender: == 0x0000000000000000000000000000000000000001 violated by 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
    );
  });

  it("appends the resolved operand value to a context-operand VALUE_MISMATCH", () => {
    const policy = PolicyBuilder.create("f(uint256)").add(arg(0).eqCtx(ContextProperty.MSG_VALUE)).build();
    expect(render(policy, f(7n), { msgValue: 9n })).toBe("arg(0): == ctx msg.value (9) violated by 7");
  });

  it("collapses NOT-eq into != and renders bool literals", () => {
    const policy = PolicyBuilder.create("g(bool)").add(arg(0).neq(false)).build();
    expect(render(policy, encodeFunctionData({ abi, functionName: "g", args: [false] }))).toBe(
      "arg(0): != false violated by false",
    );
  });

  it("prefixes a loop body test's path with its loop and names the failing element", () => {
    const policy = PolicyBuilder.create("n((address,uint256)[])")
      .add(arg(0, Quantifier.ALL, 1).lte(100n))
      .build();
    const callData = encodeFunctionData({
      abi,
      functionName: "n",
      args: [
        [
          [ADDRESS_A, 1n],
          [ADDRESS_B, 500n],
        ],
      ],
    });
    expect(render(policy, callData)).toBe("arg(0)[all].field(1): <= 100 violated at element 1 by 500");
  });

  it("formats QUANTIFIER_NO_MATCH at the loop", () => {
    const policy = PolicyBuilder.create("n((address,uint256)[])")
      .add(arg(0, Quantifier.ANY, 1).gt(100n))
      .build();
    const callData = encodeFunctionData({ abi, functionName: "n", args: [[]] });
    expect(render(policy, callData)).toBe("arg(0)[any]: no element satisfies the loop body");
  });

  it("formats SELECTOR_MISMATCH with expected and actual selectors", () => {
    const policy = PolicyBuilder.create("f(uint256)").add(arg(0).eq(1n)).build();
    expect(render(policy, "0x12345678")).toBe(
      `selector mismatch: expected ${toFunctionSelector("f(uint256)")}, got 0x12345678`,
    );
  });

  it("formats QUANTIFIER_LIMIT_EXCEEDED with a decimal count", () => {
    const policy = PolicyBuilder.create("m(uint256[])").add(arg(0, Quantifier.ALL).lte(5n)).build();
    const callData = encodeFunctionData({ abi, functionName: "m", args: [Array.from({ length: 300 }, () => 1n)] });
    expect(render(policy, callData)).toBe("arg(0)[all]: array length 300 exceeds maximum");
  });

  it("formats length-op violations with decimal counts on both sides", () => {
    const policy = PolicyBuilder.create("k(bytes)").add(arg(0).lengthEq(5n)).build();
    const callData = encodeFunctionData({ abi, functionName: "k", args: ["0x00000000000000"] });
    expect(render(policy, callData)).toBe("arg(0): length == 5 violated by 7");
  });

  it("names the subject property for a MISSING_CONTEXT on a context-scoped rule", () => {
    const policy = PolicyBuilder.create("f(uint256)").add(msgSender().eq(ADDRESS_A)).build();
    expect(render(policy, f(0n))).toBe("msg.sender not provided");
  });

  it("names the operand property for a MISSING_CONTEXT on a calldata context-operand rule", () => {
    const policy = PolicyBuilder.create("h(address)").add(arg(0).eqCtx(ContextProperty.MSG_SENDER)).build();
    const callData = encodeFunctionData({ abi, functionName: "h", args: [ADDRESS_A] });
    expect(render(policy, callData)).toBe("msg.sender not provided (referenced by arg(0))");
  });

  it("names the operand property for a MISSING_CONTEXT on a context-scoped context-operand rule", () => {
    const policy = PolicyBuilder.create("f(uint256)").add(msgSender().eqCtx(ContextProperty.TX_ORIGIN)).build();
    expect(render(policy, f(0n), { msgSender: ADDRESS_A })).toBe("tx.origin not provided (referenced by msg.sender)");
  });
});

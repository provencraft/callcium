import { arg, PolicyBuilder, PolicyCoder, type Span } from "@callcium/sdk";
import type { Abi } from "viem";
import { explainPolicy, flattenGroup, formatOperands } from "@/tools/policy-inspector";

/** One decoded "meaning" row, carrying the byte span it owns for bytes↔rule linking. */
export type LensRow = {
  path: string;
  operator: string;
  value: string;
  type: string;
  span: Span;
};

/** The hero policy rendered both as canonical bytes and as a curated set of meaning rows. */
export type LensData = {
  hex: string;
  signature: string;
  selector: string;
  signatureSpan: Span;
  rows: LensRow[];
};

// Neutral placeholder spenders (no meme hex). Both implementations build identical bytes.
const SPENDERS = ["0x1111111111111111111111111111111111111111", "0x2222222222222222222222222222222222222222"];
const MAX_AMOUNT = 1_000_000_000_000n; // 1,000,000 at 6 decimals.

// ERC-20 approve, supplying parameter names so the lens resolves `spender`/`value` instead of `arg(0)`/`arg(1)`.
const APPROVE_ABI: Abi = [
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { type: "address", name: "spender" },
      { type: "uint256", name: "value" },
    ],
    outputs: [{ type: "bool", name: "" }],
  },
];

/**
 * Build the canonical APPROVE policy and decode it into the hero lens model: the
 * byte blob plus curated meaning rows, each tagged with the span it occupies so
 * the lens can trace bytes to rules in both directions.
 */
export function buildApproveLens(): LensData {
  const hex = PolicyBuilder.create("approve(address,uint256)")
    .add(arg(0).isIn(SPENDERS))
    .add(arg(1).lte(MAX_AMOUNT))
    .build();

  const decoded = PolicyCoder.inspect(hex);
  const explained = explainPolicy(decoded, { abi: APPROVE_ABI });

  const group = decoded.groups[0];
  const explainedGroup = explained.groups[0];
  const flat = explainedGroup ? flattenGroup(explainedGroup) : [];

  const rows: LensRow[] = flat.map(({ constraint, rule }, i) => ({
    path: constraint.pathLabel,
    operator: rule.operator,
    value: formatOperands(rule),
    type: constraint.targetType,
    span: group?.rules[i]?.span ?? { start: 0, end: 0 },
  }));

  const params = explained.params.map((p) => (p.name ? `${p.type} ${p.name}` : p.type)).join(", ");

  return {
    hex,
    signature: `${explained.functionName ?? "approve"}(${params})`,
    selector: decoded.selector.value,
    // The function plus its argument shape: selector through descriptor.
    signatureSpan: { start: decoded.selector.span.start, end: decoded.descriptor.span.end },
    rows,
  };
}

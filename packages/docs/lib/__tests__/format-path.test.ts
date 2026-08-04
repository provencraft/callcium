import { lookupQuantifier, Quantifier, TypeCode, type TypeInfo } from "@callcium/sdk";
import { describe, expect, it } from "vitest";
import { formatPath } from "../format-path";
import type { ParamNode } from "@/tools/policy-builder";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

const WORD: TypeInfo = { typeCode: TypeCode.UINT_MAX, isDynamic: false, staticSize: 32 };

/** Build a ParamNode with leaf defaults, overridden per case. */
function node(partial: Partial<ParamNode> & { index: number; type: string }): ParamNode {
  return { name: null, typeInfo: WORD, children: null, element: null, ...partial };
}

/** Params for `batchTransfer((address to, uint256 amount)[] items, bytes32 ref)`. */
function structArrayParams(): ParamNode[] {
  const element = node({
    index: 0,
    type: "tuple",
    children: [node({ index: 0, type: "address", name: "to" }), node({ index: 1, type: "uint256", name: "amount" })],
  });
  return [
    node({ index: 0, type: "tuple[]", name: "items", element }),
    node({ index: 1, type: "bytes32", name: "ref" }),
  ];
}

const ALL = lookupQuantifier(Quantifier.ALL).label;

///////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////

describe("formatPath", () => {
  it("places a separate quantifier at the array level, ahead of the field steps", () => {
    const label = formatPath({
      scope: "calldata",
      path: [0, 1],
      quantifier: Quantifier.ALL,
      params: structArrayParams(),
    });
    expect(label).toBe(`items[${ALL}].amount`);
  });

  it("quantifies an elementary array with no field steps", () => {
    const params = [
      node({ index: 0, type: "uint256[]", name: "amounts", element: node({ index: 0, type: "uint256" }) }),
    ];
    expect(formatPath({ scope: "calldata", path: [0], quantifier: Quantifier.ALL, params })).toBe(`amounts[${ALL}]`);
  });

  it("falls back to positional notation when no param tree is available", () => {
    expect(formatPath({ scope: "calldata", path: [0, 1], quantifier: Quantifier.ALL })).toBe(`arg(0)[${ALL}].field(1)`);
  });

  it("treats a step as an array index when no quantifier is set", () => {
    expect(formatPath({ scope: "calldata", path: [0, 1, 1], params: structArrayParams() })).toBe("items[1].amount");
  });
});

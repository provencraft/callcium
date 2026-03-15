import type { Abi } from "viem";
import { describe, expect, it } from "vitest";
import policyVectors from "../../../../test/vectors/policies.json";
import type { DecodedPolicy, Hex, Span } from "../decoder";
import { decodePolicy } from "../decoder";
import { explainPolicy } from "../explainer";
import B from "./explainer-blobs.json";

///////////////////////////////////////////////////////////////////////////
//                            TEST HELPERS
///////////////////////////////////////////////////////////////////////////

function _explain(blob: string) {
  return explainPolicy(decodePolicy(blob));
}

function _firstConstraint(blob: string) {
  return _explain(blob).groups[0].constraints[0];
}

function _firstRule(blob: string) {
  return _firstConstraint(blob).rules[0];
}

// Approve ABI fixture used across ABI and signature tests.
const approveAbi: Abi = [
  {
    type: "function",
    name: "approve",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
  },
];

///////////////////////////////////////////////////////////////////////////
//                        OPERAND DECODING
///////////////////////////////////////////////////////////////////////////

describe("operand decoding", () => {
  const cases: [string, string, string][] = [
    ["uint256", B.EQ_UINT256, "42"],
    ["uint8", B.EQ_UINT8, "255"],
    ["positive int256", B.EQ_INT256_POS, "100"],
    ["negative int256", B.EQ_INT256_NEG, "-1"],
    ["int256 boundary -128", B.EQ_INT256_BOUNDARY, "-128"],
    ["int8", B.EQ_INT8, "-1"],
    ["bool true", B.EQ_BOOL_TRUE, "true"],
    ["bool false", B.EQ_BOOL_FALSE, "false"],
    ["address", B.EQ_ADDRESS, "0x0000000000000000000000000000000000000001"],
  ];

  for (const [label, blob, expected] of cases) {
    it(`decodes ${label}`, () => {
      expect(_firstRule(blob).operands).toEqual([expected]);
    });
  }

  it("decodes bytes1", () => {
    expect(_firstRule(B.EQ_BYTES1).operands).toEqual(["0xff"]);
  });

  it("decodes bytes32", () => {
    const rule = _firstRule(B.EQ_BYTES32);
    expect(rule.operands[0]).toMatch(/^0x/);
    expect(rule.operands[0]).toHaveLength(66); // "0x" + 64 hex chars.
  });
});

///////////////////////////////////////////////////////////////////////////
//                          OPERATOR TYPES
///////////////////////////////////////////////////////////////////////////

describe("operator types", () => {
  it("decodes IN with multiple operands", () => {
    const rule = _firstRule(B.IN_UINT256);
    expect(rule.operator).toBe("in");
    expect(rule.operands).toEqual(["1", "2", "3"]);
  });

  it("decodes BETWEEN with two operands", () => {
    const rule = _firstRule(B.BETWEEN_UINT256);
    expect(rule.operator).toBe("between");
    expect(rule.operands).toEqual(["10", "100"]);
  });

  it("decodes negated operator", () => {
    const rule = _firstRule(B.NEQ_UINT256);
    expect(rule.operator).toBe("!=");
    expect(rule.negated).toBe(true);
    expect(rule.operands).toEqual(["42"]);
  });

  it("decodes negated GT", () => {
    const rule = _firstRule(B.NGT_UINT256);
    expect(rule.operator).toBe("not >");
    expect(rule.negated).toBe(true);
  });

  it("decodes length operator with uint256 operands", () => {
    const rule = _firstRule(B.LENGTH_EQ);
    expect(rule.operator).toBe("length ==");
    expect(rule.operands).toEqual(["5"]);
  });
});

///////////////////////////////////////////////////////////////////////////
//                          SCOPE AND PATH
///////////////////////////////////////////////////////////////////////////

describe("scope and path resolution", () => {
  it("labels calldata scope with positional arg", () => {
    const constraint = _firstConstraint(B.CALLDATA_ARG1);
    expect(constraint.scope).toBe("calldata");
    expect(constraint.pathLabel).toBe("arg(1)");
    expect(constraint.targetType).toBe("address");
  });

  it("resolves msg.sender as address", () => {
    const constraint = _firstConstraint(B.CTX_MSG_SENDER);
    expect(constraint.scope).toBe("context");
    expect(constraint.pathLabel).toBe("msg.sender");
    expect(constraint.targetType).toBe("address");
  });

  it("resolves msg.value as uint256", () => {
    const constraint = _firstConstraint(B.CTX_MSG_VALUE);
    expect(constraint.pathLabel).toBe("msg.value");
    expect(constraint.targetType).toBe("uint256");
  });

  it("resolves block.timestamp", () => {
    expect(_firstConstraint(B.CTX_BLOCK_TIMESTAMP).pathLabel).toBe("block.timestamp");
  });

  it("resolves tx.origin as address", () => {
    const constraint = _firstConstraint(B.CTX_TX_ORIGIN);
    expect(constraint.pathLabel).toBe("tx.origin");
    expect(constraint.targetType).toBe("address");
  });

  it("resolves tuple field path", () => {
    const constraint = _firstConstraint(B.TUPLE_FIELD);
    expect(constraint.pathLabel).toBe("arg(0).field(1)");
    expect(constraint.targetType).toBe("address");
  });

  it("resolves dynamic array element path", () => {
    const constraint = _firstConstraint(B.DYNAMIC_ARRAY_ELEM);
    expect(constraint.pathLabel).toBe("arg(0)[]");
    expect(constraint.targetType).toBe("uint256");
  });
});

///////////////////////////////////////////////////////////////////////////
//                        STRUCTURE AND GROUPS
///////////////////////////////////////////////////////////////////////////

describe("structure", () => {
  it("handles multiple groups", () => {
    const { groups } = _explain(B.MULTI_GROUP);
    expect(groups).toHaveLength(2);
    expect(groups[0].constraints[0].rules[0].operands).toEqual(["2"]);
    expect(groups[1].constraints[0].rules[0].operands).toEqual(["1"]);
  });

  it("handles multiple constraints per group", () => {
    const { constraints } = _explain(B.MULTI_CONSTRAINT).groups[0];
    expect(constraints).toHaveLength(2);
    expect(constraints[0].scope).toBe("context");
    expect(constraints[0].pathLabel).toBe("msg.sender");
    expect(constraints[1].scope).toBe("calldata");
  });

  it("handles multiple rules per constraint", () => {
    const { rules } = _firstConstraint(B.MULTI_RULE);
    expect(rules).toHaveLength(2);
    expect(rules[0].operator).toBe(">");
    expect(rules[1].operator).toBe("<");
  });

  it("reports params from descriptor", () => {
    const { params } = _explain(B.MULTI_PARAM);
    expect(params).toHaveLength(3);
    expect(params[0].type).toBe("uint256");
    expect(params[1].type).toBe("address");
    expect(params[2].type).toBe("bool");
    expect(params.every((p) => p.name === null)).toBe(true);
  });
});

///////////////////////////////////////////////////////////////////////////
//                          SELECTORLESS
///////////////////////////////////////////////////////////////////////////

describe("selectorless", () => {
  it("reports isSelectorless and null function name", () => {
    const explained = _explain(B.SELECTORLESS);
    expect(explained.isSelectorless).toBe(true);
    expect(explained.functionName).toBeNull();
  });
});

///////////////////////////////////////////////////////////////////////////
//                          SPANS PASSTHROUGH
///////////////////////////////////////////////////////////////////////////

describe("spans passthrough", () => {
  it("preserves spans from decoded policy", () => {
    const policySpan: Span = { start: 0, end: 100 };
    const groupSpan: Span = { start: 10, end: 90 };
    const ruleSpan: Span = { start: 30, end: 70 };
    const paramSpan: Span = { start: 9, end: 10 };

    const input: DecodedPolicy = {
      header: { value: 0x01, span: { start: 0, end: 1 } },
      selector: { value: "0x12345678", span: { start: 1, end: 5 } },
      descLength: { value: 3, span: { start: 5, end: 7 } },
      descriptor: {
        raw: "0x01011f",
        params: [
          {
            index: 0,
            typeCode: 0x1f,
            isDynamic: false,
            staticSize: 32,
            path: "0x0000" as Hex,
            span: paramSpan,
          },
        ],
        span: { start: 7, end: 10 },
      },
      groupCount: { value: 1, span: { start: 10, end: 11 } },
      groups: [
        {
          ruleCount: { value: 1, span: { start: 11, end: 13 } },
          groupSize: { value: 39, span: { start: 13, end: 17 } },
          rules: [
            {
              ruleSize: { value: 39, span: { start: 30, end: 32 } },
              scope: { value: 0x01, span: { start: 32, end: 33 } },
              pathDepth: { value: 1, span: { start: 33, end: 34 } },
              path: { value: "0x0000" as Hex, span: { start: 34, end: 36 } },
              opCode: { value: 0x01, span: { start: 36, end: 37 } },
              dataLength: { value: 32, span: { start: 37, end: 39 } },
              data: {
                value: "0x0000000000000000000000000000000000000000000000000000000000000001" as Hex,
                span: { start: 39, end: 71 },
              },
              span: ruleSpan,
            },
          ],
          span: groupSpan,
        },
      ],
      span: policySpan,
      version: 1,
      isSelectorless: false,
    };

    const explained = explainPolicy(input);
    expect(explained.span).toEqual(policySpan);
    expect(explained.groups[0].span).toEqual(groupSpan);
    expect(explained.groups[0].constraints[0].rules[0].span).toEqual(ruleSpan);
  });
});

///////////////////////////////////////////////////////////////////////////
//                      DECODER FIELD SPANS
///////////////////////////////////////////////////////////////////////////

describe("decoder field spans", () => {
  it("assigns correct spans to policy-level fields", () => {
    const decoded = decodePolicy(B.EQ_UINT256);
    expect(decoded.header.span).toEqual({ start: 0, end: 1 });
    expect(decoded.selector.span).toEqual({ start: 1, end: 5 });
    expect(decoded.descLength.span).toEqual({ start: 5, end: 7 });
    expect(decoded.descriptor.span.start).toBe(7);
    expect(decoded.descriptor.span.end).toBe(7 + decoded.descLength.value);
    const groupCountStart = decoded.descriptor.span.end;
    expect(decoded.groupCount.span).toEqual({
      start: groupCountStart,
      end: groupCountStart + 1,
    });
  });

  it("assigns correct spans to rule fields", () => {
    const decoded = decodePolicy(B.EQ_UINT256);
    const rule = decoded.groups[0].rules[0];

    // Fields must be contiguous within the rule.
    expect(rule.ruleSize.span.start).toBe(rule.span.start);
    expect(rule.scope.span.start).toBe(rule.ruleSize.span.end);
    expect(rule.pathDepth.span.start).toBe(rule.scope.span.end);
    expect(rule.path.span.start).toBe(rule.pathDepth.span.end);
    expect(rule.opCode.span.start).toBe(rule.path.span.end);
    expect(rule.dataLength.span.start).toBe(rule.opCode.span.end);
    expect(rule.data.span.start).toBe(rule.dataLength.span.end);
    expect(rule.data.span.end).toBe(rule.span.end);
  });

  it("assigns correct spans to group header fields", () => {
    const decoded = decodePolicy(B.EQ_UINT256);
    const group = decoded.groups[0];

    expect(group.ruleCount.span.start).toBe(group.span.start);
    expect(group.ruleCount.span.end).toBe(group.span.start + 2);
    expect(group.groupSize.span.start).toBe(group.ruleCount.span.end);
    expect(group.groupSize.span.end).toBe(group.ruleCount.span.end + 4);
  });
});

///////////////////////////////////////////////////////////////////////////
//                          ABI ENRICHMENT
///////////////////////////////////////////////////////////////////////////

describe("ABI enrichment", () => {
  const opts = { abi: approveAbi };

  it("resolves function name from ABI", () => {
    const explained = explainPolicy(decodePolicy(B.APPROVE_ARG0), opts);
    expect(explained.functionName).toBe("approve");
  });

  it("resolves param names from ABI", () => {
    const { params } = explainPolicy(decodePolicy(B.APPROVE_ARG0), opts);
    expect(params[0].name).toBe("spender");
    expect(params[1].name).toBe("amount");
  });

  it("uses ABI param names in path labels", () => {
    const explained = explainPolicy(decodePolicy(B.APPROVE_ARG1), opts);
    expect(explained.groups[0].constraints[0].pathLabel).toBe("amount");
  });

  it("falls back to positional labels when ABI does not match", () => {
    const explained = explainPolicy(decodePolicy(B.EQ_UINT256), opts);
    expect(explained.functionName).toBeNull();
    expect(explained.params[0].name).toBeNull();
    expect(explained.groups[0].constraints[0].pathLabel).toBe("arg(0)");
  });

  it("ignores ABI for selectorless policies", () => {
    const explained = explainPolicy(decodePolicy(B.SELECTORLESS), opts);
    expect(explained.functionName).toBeNull();
    expect(explained.params[0].name).toBeNull();
  });
});

///////////////////////////////////////////////////////////////////////////
//                          SMOKE TEST
///////////////////////////////////////////////////////////////////////////

describe("smoke", () => {
  it("explains all valid conformance vectors without throwing", () => {
    (policyVectors as { blob: string; error: string }[])
      .filter((vec) => vec.error === "")
      .forEach((vec) => {
        expect(() => explainPolicy(decodePolicy(vec.blob))).not.toThrow();
      });
  });
});

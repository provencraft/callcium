import { CallciumError, PolicyCoder } from "@callcium/sdk";
import { type Abi, parseAbi } from "viem";
import { describe, expect, it } from "vitest";
import type { Hex } from "@callcium/sdk";
import enforcementVectors from "../../../spec/vectors/enforcement.json";
import policyVectors from "../../../spec/vectors/policies.json";
import validationVectors from "../../../spec/vectors/validation.json";
import { type ExplainedLoop, type ExplainedTest, explainPolicy } from "./policy-inspector";

///////////////////////////////////////////////////////////////////////////
// Test helpers
///////////////////////////////////////////////////////////////////////////

/** The blob of the vector `id` in `vectors`. */
function vectorBlob(vectors: { id: string; blob: string }[], id: string): Hex {
  const vector = vectors.find((v) => v.id === id);
  if (!vector) throw new Error(`No vector ${id}`);
  return vector.blob as Hex;
}

const policy = (id: string) => vectorBlob(policyVectors, id);
const enforcement = (id: string) => vectorBlob(enforcementVectors, id);
const validation = (id: string) => vectorBlob(validationVectors, id);

function _explain(blob: Hex, abi?: Abi) {
  return explainPolicy(PolicyCoder.inspect(blob), abi ? { abi } : undefined);
}

/** The root test at `index` of the first group. */
function _test(blob: Hex, index = 0): ExplainedTest {
  const rule = _explain(blob).groups[0].rules[index];
  if ("body" in rule) throw new Error("Root test expected");
  return rule;
}

/** The first rule of the first group, a loop. */
function _loop(blob: Hex): ExplainedLoop {
  const rule = _explain(blob).groups[0].rules[0];
  if (!("body" in rule)) throw new Error("Loop expected");
  return rule;
}

///////////////////////////////////////////////////////////////////////////
// Operand decoding
///////////////////////////////////////////////////////////////////////////

describe("operand decoding", () => {
  const cases: [string, Hex, string[]][] = [
    ["uint256", policy("calldata-eq-uint256"), ["42"]],
    ["uint8", enforcement("gt-uint8-pass"), ["254"]],
    ["negative and positive int256", enforcement("signed-between-pass"), ["-100", "100"]],
    ["negative int8", policy("calldata-gt-int8"), ["-1"]],
    ["bool true", enforcement("eq-bool-pass"), ["true"]],
    ["bool false", validation("bool-contradiction"), ["false"]],
    ["address", policy("calldata-eq-address"), ["0x0000000000000000000000000000000000000001"]],
    ["bytes1", validation("left-aligned-contradiction"), ["0x00"]],
  ];

  for (const [label, blob, expected] of cases) {
    it(`decodes ${label}`, () => {
      expect(_test(blob).operands).toEqual(expected);
    });
  }

  it("decodes a bytes1 operand as its left-aligned byte", () => {
    expect(_test(validation("left-aligned-contradiction"), 1).operands).toEqual(["0x80"]);
  });

  it("decodes bytes32", () => {
    const [operand] = _test(validation("numeric-op-on-bytes32")).operands;
    expect(operand).toMatch(/^0x/);
    expect(operand).toHaveLength(66); // "0x" + 64 hex chars.
  });
});

///////////////////////////////////////////////////////////////////////////
// Operator types
///////////////////////////////////////////////////////////////////////////

describe("operator types", () => {
  it("decodes IN with multiple operands", () => {
    const test = _test(enforcement("in-pass"));
    expect(test.operator).toBe("in");
    expect(test.operands).toEqual(["10", "20", "30"]);
  });

  it("decodes BETWEEN with two operands", () => {
    const test = _test(policy("calldata-between-uint256"));
    expect(test.operator).toBe("between");
    expect(test.operands).toEqual(["10", "100"]);
  });

  it("decodes negated operator", () => {
    const test = _test(policy("calldata-not-eq"));
    expect(test.operator).toBe("!=");
    expect(test.negated).toBe(true);
    expect(test.operands).toEqual(["42"]);
  });

  it("decodes negated GT", () => {
    const test = _test(enforcement("not-gt-ctx-value-pass"));
    expect(test.operator).toBe("not > ctx");
    expect(test.negated).toBe(true);
  });

  it("decodes length operator with decimal operands", () => {
    const test = _test(policy("calldata-length-eq-bytes"));
    expect(test.operator).toBe("length ==");
    expect(test.operands).toEqual(["5"]);
  });

  it("decodes a context operand", () => {
    const test = _test(policy("calldata-eq-context-sender"));
    expect(test.operator).toBe("== ctx");
    expect(test.operands).toEqual(["msg.sender"]);
  });

  it("decodes a negated context operand", () => {
    const test = _test(enforcement("eq-ctx-negated-pass"));
    expect(test.operator).toBe("!= ctx");
    expect(test.negated).toBe(true);
    expect(test.operands).toEqual(["msg.sender"]);
  });
});

///////////////////////////////////////////////////////////////////////////
// Scope and path
///////////////////////////////////////////////////////////////////////////

describe("scope and path resolution", () => {
  it("labels calldata scope with positional arg", () => {
    const test = _test(validation("ordering-ops-on-address"), 1);
    expect(test.scope).toBe("calldata");
    expect(test.pathLabel).toBe("arg(1)");
    expect(test.targetType).toBe("address");
  });

  const contextCases: [Hex, string, string][] = [
    [policy("context-eq-sender"), "msg.sender", "address"],
    [policy("context-gte-value"), "msg.value", "uint256"],
    [enforcement("context-timestamp-pass"), "block.timestamp", "uint256"],
    [enforcement("context-origin-pass"), "tx.origin", "address"],
    [enforcement("context-basefee-pass"), "block.basefee", "uint256"],
    [enforcement("context-gasprice-pass"), "tx.gasprice", "uint256"],
  ];

  for (const [blob, label, type] of contextCases) {
    it(`resolves ${label} as ${type}`, () => {
      const test = _test(blob);
      expect(test.scope).toBe("context");
      expect(test.pathLabel).toBe(label);
      expect(test.targetType).toBe(type);
    });
  }

  it("resolves tuple field path", () => {
    const test = _test(enforcement("tuple-field-pass"));
    expect(test.pathLabel).toBe("arg(0).field(1)");
    expect(test.targetType).toBe("address");
  });

  it("resolves dynamic array element path", () => {
    const test = _test(enforcement("group-local-array-index-multi-group"));
    expect(test.pathLabel).toBe("arg(0)[5]");
    expect(test.targetType).toBe("uint256");
  });

  it("heads a loop's body with its array and quantifier, labelling each body test from the element", () => {
    const loop = _loop(policy("loop-any-two-tests"));
    expect(loop.pathLabel).toBe("arg(0)[any]");
    expect(loop.body.map((test) => [test.pathLabel, test.operator, test.targetType])).toEqual([
      [".field(0)", "==", "address"],
      [".field(1)", ">=", "uint256"],
    ]);
  });
});

///////////////////////////////////////////////////////////////////////////
// Structure and groups
///////////////////////////////////////////////////////////////////////////

describe("structure", () => {
  it("handles multiple groups", () => {
    const { groups } = _explain(policy("two-groups"));
    expect(groups).toHaveLength(2);
    expect(groups.map((group) => (group.rules[0] as ExplainedTest).operands[0])).toEqual(["1", "2"]);
  });

  it("handles context and calldata tests in one group", () => {
    const { rules } = _explain(policy("context-and-calldata")).groups[0];
    expect(rules.map((rule) => [(rule as ExplainedTest).scope, rule.pathLabel])).toEqual([
      ["context", "msg.sender"],
      ["calldata", "arg(0)"],
    ]);
  });

  it("handles multiple tests on one path", () => {
    const blob = enforcement("multi-rule-and-pass");
    expect([_test(blob, 0).operator, _test(blob, 1).operator]).toEqual([">", "<="]);
  });

  it("reports params from descriptor", () => {
    const { params } = _explain(validation("unnavigable-path-beside-numeric-op"));
    expect(params.map((p) => p.type)).toEqual(["tuple", "address"]);
    expect(params.every((p) => p.name === null)).toBe(true);
  });
});

///////////////////////////////////////////////////////////////////////////
// Selectorless
///////////////////////////////////////////////////////////////////////////

describe("selectorless", () => {
  it("reports isSelectorless and null function name", () => {
    const explained = _explain(policy("selectorless"));
    expect(explained.isSelectorless).toBe(true);
    expect(explained.functionName).toBeNull();
  });
});

///////////////////////////////////////////////////////////////////////////
// Spans
///////////////////////////////////////////////////////////////////////////

describe("spans", () => {
  it("keeps the decoded policy's span and each decoded rule", () => {
    const decoded = PolicyCoder.inspect(policy("calldata-eq-uint256"));
    const explained = explainPolicy(decoded);

    expect(explained.span).toEqual(decoded.span);
    expect(explained.groups[0].rules[0].rule).toBe(decoded.groups[0].rules[0]);
  });
});

///////////////////////////////////////////////////////////////////////////
// ABI enrichment
///////////////////////////////////////////////////////////////////////////

describe("ABI enrichment", () => {
  // The vector's function is `foo(uint256,uint8)`.
  const abi = parseAbi(["function foo(uint256 amount, uint8 decimals)"]);
  const blob = enforcement("group-order-from-blob");

  it("resolves function name from ABI", () => {
    expect(_explain(blob, abi).functionName).toBe("foo");
  });

  it("resolves param names from ABI", () => {
    const { params } = _explain(blob, abi);
    expect(params.map((p) => p.name)).toEqual(["amount", "decimals"]);
  });

  it("uses ABI param names in path labels", () => {
    expect(_explain(blob, abi).groups[0].rules[0].pathLabel).toBe("decimals");
  });

  it("uses ABI component names in struct field labels", () => {
    const structAbi = parseAbi(["function foo((uint256 amount, address recipient) order)"]);
    expect(_explain(enforcement("tuple-field-pass"), structAbi).groups[0].rules[0].pathLabel).toBe("order.recipient");
  });

  it("falls back to positional labels when ABI does not match", () => {
    const explained = _explain(policy("calldata-eq-uint256"), abi);
    expect(explained.functionName).toBeNull();
    expect(explained.params[0].name).toBeNull();
    expect(explained.groups[0].rules[0].pathLabel).toBe("arg(0)");
  });

  it("ignores ABI for selectorless policies", () => {
    const explained = _explain(policy("selectorless"), abi);
    expect(explained.functionName).toBeNull();
    expect(explained.params[0].name).toBeNull();
  });
});

///////////////////////////////////////////////////////////////////////////
// Smoke test
///////////////////////////////////////////////////////////////////////////

describe("smoke", () => {
  // Stored blobs whose descriptor fails DV-1 or DV-2, which inspection refuses.
  const descriptorFaults = new Set(["descriptor-node-length", "descriptor-static-words"]);

  it("explains every stored conformance vector whose descriptor inspection accepts", () => {
    for (const vec of policyVectors.filter((v) => v.error === "")) {
      const blob = vec.blob as Hex;
      if (descriptorFaults.has(vec.id)) expect(() => PolicyCoder.inspect(blob)).toThrow(CallciumError);
      else expect(() => explainPolicy(PolicyCoder.inspect(blob))).not.toThrow();
    }
  });
});

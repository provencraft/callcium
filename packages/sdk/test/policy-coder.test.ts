import { describe, expect, test } from "vitest";

import storageVectors from "../../../spec/vectors/policies.json";
import { bigintToHex, bytesToHex, hexToBytes, toHex } from "../src/bytes";
import {
  ContextProperty,
  DescriptorFormat as DF,
  fieldMax,
  LoopQuantifier,
  Op,
  PolicyFormat,
  Scope,
  Source,
  TypeCode,
} from "../src/constants";
import { arg } from "../src/constraint";
import { DescriptorCoder } from "../src/descriptor-coder";
import { CallciumError } from "../src/errors";
import { LENGTH_TYPE } from "../src/operators";
import { encodePath } from "../src/path";
import { PolicyBuilder } from "../src/policy-builder";
import { operatorHex, PolicyCoder, validatePolicy } from "../src/policy-coder";
import { expectErrorCode, hex, inOp, op, vectorById } from "./helpers";

import type {
  BodyRule,
  DecodedNode,
  DecodedPolicy,
  DecodedRule,
  DecodedTest,
  Hex,
  PolicyData,
  Rule,
  Span,
} from "../src/types";

///////////////////////////////////////////////////////////////////////////
// Fixtures
///////////////////////////////////////////////////////////////////////////

/** A policy over `foo(uint256)` of the given groups. */
function policyData(groups: Rule[][], descriptor: Hex = bytesToHex(DescriptorCoder.fromTypes("uint256"))): PolicyData {
  return { isSelectorless: false, selector: "0x2fbebd38", descriptor, groups };
}

/** An equality on argument 0 against `value`. */
function eq(value: bigint): BodyRule {
  return { scope: Scope.CALLDATA, path: encodePath([0]), operator: op(Op.EQ, value) };
}

/** The blob of the storage vector `id`. */
function storageBlob(id: string): Hex {
  return hex(vectorById(storageVectors, id).blob);
}

/** A meta word with no flag and no stride. */
const NO_META = { isElementDynamic: false, isDynamicArray: false, strideWords: 0 } as const;

/** One distinct group more than the group count holds. */
function overfullGroups(): BodyRule[][] {
  return Array.from({ length: fieldMax(PolicyFormat.GROUP_COUNT_SIZE) + 1 }, (_, index) => [eq(BigInt(index))]);
}

/** The blobs of every storage vector that storage accepts. */
const acceptedBlobs: Hex[] = storageVectors.filter((vector) => vector.error === "").map((vector) => hex(vector.blob));

/** The policy data an inspected policy states, its hints sliced from `blob`. */
function project(inspected: DecodedPolicy, blob: Hex): PolicyData {
  const data = hexToBytes(blob);
  const slice = (span: Span) => toHex(data, span.start, span.end);
  const projectTest = (rule: DecodedTest): BodyRule => {
    const base = { scope: rule.scope.value, path: rule.path.value, operator: operatorHex(rule.operator) };
    return rule.hint === undefined ? base : { ...base, hint: slice(rule.hint.span) };
  };
  const projectRule = (rule: DecodedRule): Rule => {
    if (!("body" in rule)) return projectTest(rule);
    const loop = { scope: rule.scope.value, quantifier: rule.quantifier.value, path: rule.path.value };
    return { ...loop, hint: slice(rule.hint.span), body: rule.body.map(projectTest) };
  };
  return {
    isSelectorless: inspected.header.value.isSelectorless,
    selector: inspected.selector.value,
    descriptor: slice(inspected.descriptor.span),
    groups: inspected.groups.map((group) => group.rules.map(projectRule)),
  };
}

/** Expect `parts` to fill `whole` in order, each starting where the one before it ends. */
function expectTiles(whole: Span, parts: Span[]): void {
  let cursor = whole.start;
  for (const part of parts) {
    expect(part.start).toBe(cursor);
    cursor = part.end;
  }
  expect(cursor).toBe(whole.end);
}

/** Expect a descriptor node's children to fill it past its header. */
function expectNodeTiles(node: DecodedNode): void {
  switch (node.typeClass) {
    case "elementary":
      expect(node.span.end - node.span.start).toBe(DF.TYPECODE_SIZE);
      return;
    case "tuple":
      expectTiles(
        { start: node.span.start + DF.TUPLE_HEADER_SIZE, end: node.span.end },
        node.fields.map((field) => field.span),
      );
      node.fields.forEach(expectNodeTiles);
      return;
    case "staticArray":
      expectTiles({ start: node.span.start + DF.ARRAY_HEADER_SIZE, end: node.span.end - DF.ARRAY_LENGTH_SIZE }, [
        node.element.span,
      ]);
      expectNodeTiles(node.element);
      return;
    case "dynamicArray":
      expectTiles({ start: node.span.start + DF.ARRAY_HEADER_SIZE, end: node.span.end }, [node.element.span]);
      expectNodeTiles(node.element);
      return;
    default:
      return node satisfies never;
  }
}

/** Expect a test's fields, and its hint's, to fill it. */
function expectTestTiles(rule: DecodedTest): void {
  const hint = rule.hint === undefined ? [] : [rule.hint.span];
  const head = [rule.ruleSize.span, rule.scope.span, rule.pathDepth.span, rule.path.span];
  expectTiles(rule.span, [...head, ...hint, rule.opCode.span, rule.dataLength.span, rule.data.span]);
  if (rule.hint !== undefined) {
    const { hopCount, hops, targetDelta, targetMeta, typeCode } = rule.hint;
    const parts = [hopCount.span, ...hops.map((hop) => hop.span), targetDelta.span, targetMeta.span, typeCode.span];
    expectTiles(rule.hint.span, parts);
    for (const hop of hops) expectTiles(hop.span, [hop.delta.span, hop.index.span, hop.meta.span]);
  }
}

/** Expect every field of an inspected policy to fill the field holding it. */
function expectPolicyTiles(inspected: DecodedPolicy): void {
  const { header, selector, descLength, descriptor, groupCount, groups } = inspected;
  const top = [header.span, selector.span, descLength.span, descriptor.span, groupCount.span];
  expectTiles(inspected.span, [...top, ...groups.map((group) => group.span)]);
  expectTiles(descriptor.span, [
    descriptor.version.span,
    descriptor.paramCount.span,
    ...descriptor.params.map((param) => param.span),
  ]);
  descriptor.params.forEach(expectNodeTiles);
  for (const group of groups) {
    expectTiles(group.span, [group.ruleCount.span, group.groupSize.span, ...group.rules.map((rule) => rule.span)]);
    for (const rule of group.rules) {
      if (!("body" in rule)) {
        expectTestTiles(rule);
        continue;
      }
      const head = [rule.ruleSize.span, rule.scope.span, rule.quantifier.span, rule.pathDepth.span, rule.path.span];
      expectTiles(rule.span, [
        ...head,
        rule.hint.span,
        rule.ruleCount.span,
        ...rule.body.map((bodyRule) => bodyRule.span),
      ]);
      const { hopCount, hops, arrayDelta, count, meta } = rule.hint;
      expectTiles(rule.hint.span, [
        hopCount.span,
        ...hops.map((hop) => hop.span),
        arrayDelta.span,
        count.span,
        meta.span,
      ]);
      for (const hop of hops) expectTiles(hop.span, [hop.delta.span, hop.index.span, hop.meta.span]);
      rule.body.forEach(expectTestTiles);
    }
  }
}

///////////////////////////////////////////////////////////////////////////
// Error offsets
///////////////////////////////////////////////////////////////////////////

// The storage vectors pin error names, not offsets.

/** Offset of the group in each `foo(uint256)` blob below. */
const GROUP_OFFSET = 11;

/** Offset of that group's first rule. */
const RULE_OFFSET = 17;

/** Offset of the first body test in each `foo(uint256[])` loop blob below. */
const BODY_RULE_OFFSET = 47;

describe("validatePolicy - error offsets", () => {
  test("reports rules overrunning their group at the group", () => {
    const blob = storageBlob("rule-count-over");
    expect(expectErrorCode(() => validatePolicy(blob), "GROUP_SIZE_MISMATCH").offset).toBe(GROUP_OFFSET);
  });

  test("reports a hint target that addresses no value at its rule", () => {
    const blob = storageBlob("hint-target-tuple");
    expect(expectErrorCode(() => validatePolicy(blob), "MALFORMED_HINT").offset).toBe(RULE_OFFSET);
  });

  test("reports an operator family that mismatches its target at its rule", () => {
    const blob = storageBlob("length-on-word");
    expect(expectErrorCode(() => validatePolicy(blob), "OPERATOR_TARGET_MISMATCH").offset).toBe(RULE_OFFSET);
  });

  test("reports a body path too deep at the body test, with the depth across the loop", () => {
    const blob = storageBlob("loop-path-too-deep");
    const error = expectErrorCode(() => validatePolicy(blob), "PATH_TOO_DEEP");
    expect(error.offset).toBe(BODY_RULE_OFFSET);
    expect(error.message).toBe(
      `[offset ${BODY_RULE_OFFSET}] Path depth 64 exceeds maximum ${PolicyFormat.MAX_PATH_DEPTH}`,
    );
  });
});

///////////////////////////////////////////////////////////////////////////
// Encoder field shapes
///////////////////////////////////////////////////////////////////////////

describe("PolicyCoder.encode field shapes", () => {
  test("rejects a policy without groups", () => {
    expectErrorCode(() => PolicyCoder.encode(policyData([])), "EMPTY_POLICY");
  });

  test("rejects an empty group", () => {
    expectErrorCode(() => PolicyCoder.encode(policyData([[]])), "EMPTY_GROUP");
  });

  test("rejects an empty path", () => {
    expectErrorCode(() => PolicyCoder.encode(policyData([[{ ...eq(1n), path: "0x" }]])), "EMPTY_PATH");
  });

  test("rejects a context operand past its two-byte field", () => {
    const contextEq = Op.EQ | (Source.CONTEXT << Op.SOURCE_SHIFT);
    expectErrorCode(
      () => PolicyCoder.encode(policyData([[{ ...eq(1n), operator: op(contextEq, 2n ** 16n) }]])),
      "INVALID_OPERATOR_BYTES",
    );
  });

  test("rejects a context path of two steps", () => {
    const rule: BodyRule = { scope: Scope.CONTEXT, path: encodePath([1, 0]), operator: op(Op.EQ, 1n) };
    expectErrorCode(() => PolicyCoder.encode(policyData([[rule]])), "INVALID_CONTEXT_PATH");
  });

  test("counts path depth across the loop", () => {
    const body: BodyRule[] = [
      { scope: Scope.CALLDATA, path: encodePath(Array(PolicyFormat.MAX_PATH_DEPTH).fill(0)), operator: op(Op.EQ, 1n) },
    ];
    const loop: Rule = { scope: Scope.LOOP, quantifier: LoopQuantifier.ALL, path: encodePath([0]), body };
    const descriptor = bytesToHex(DescriptorCoder.fromTypes("uint256[]"));
    expectErrorCode(() => PolicyCoder.encode(policyData([[loop]], descriptor)), "PATH_TOO_DEEP");
  });

  test("rejects a scope a rule cannot take", () => {
    const rule = { scope: Scope.LOOP + 1, path: encodePath([0]), operator: op(Op.EQ, 1n) };
    // @ts-expect-error -- the scope lies outside the union a caller from JavaScript can still pass.
    expectErrorCode(() => PolicyCoder.encode(policyData([[rule]])), "UNKNOWN_SCOPE");
  });

  test("rejects a quantifier a loop cannot take", () => {
    const loop = { scope: Scope.LOOP, quantifier: LoopQuantifier.ANY + 1, path: encodePath([0]), body: [] };
    // @ts-expect-error -- the quantifier lies outside the union a caller from JavaScript can still pass.
    expectErrorCode(() => PolicyCoder.encode(policyData([[loop]])), "UNKNOWN_QUANTIFIER");
  });

  test("rejects a selector that is not four bytes", () => {
    expectErrorCode(
      () => PolicyCoder.encode({ ...policyData([[eq(1n)]]), selector: "0xaabbcc" }),
      "MALFORMED_SELECTOR",
    );
  });
});

///////////////////////////////////////////////////////////////////////////
// Encoder operands
///////////////////////////////////////////////////////////////////////////

describe("PolicyCoder.encode operands", () => {
  test("rejects a comparison that does not apply to the target", () => {
    expectErrorCode(
      () => PolicyCoder.encode(policyData([[{ ...eq(1n), operator: op(Op.LENGTH_EQ, 1n) }]])),
      "OPERATOR_TARGET_MISMATCH",
    );
  });
});

///////////////////////////////////////////////////////////////////////////
// Encoder field widths
///////////////////////////////////////////////////////////////////////////

describe("PolicyCoder.encode field widths", () => {
  test("rejects more distinct groups than the group count holds", () => {
    expectErrorCode(() => PolicyCoder.encode(policyData(overfullGroups())), "GROUP_COUNT_OVERFLOW");
  });

  test("rejects more distinct rules than the rule count holds", () => {
    const rules = Array.from({ length: fieldMax(PolicyFormat.GROUP_RULECOUNT_SIZE) + 1 }, (_, index) =>
      eq(BigInt(index)),
    );
    expectErrorCode(() => PolicyCoder.encode(policyData([rules])), "RULE_COUNT_OVERFLOW");
  });

  test("rejects a rule larger than its size field", () => {
    const members = Array.from(
      { length: Math.floor(fieldMax(PolicyFormat.RULE_DATALENGTH_SIZE) / 32) + 1 },
      (_, index) => BigInt(index),
    );
    expectErrorCode(
      () => PolicyCoder.encode(policyData([[{ ...eq(1n), operator: inOp(Op.IN, members) }]])),
      "RULE_SIZE_OVERFLOW",
    );
  });
});

///////////////////////////////////////////////////////////////////////////
// Encoder check order
///////////////////////////////////////////////////////////////////////////

describe("PolicyCoder.encode check order", () => {
  test("an operator's framing outranks path shape", () => {
    const rule: BodyRule = { scope: Scope.CALLDATA, path: "0x000000", operator: "0x01" };
    expectErrorCode(() => PolicyCoder.encode(policyData([[rule]])), "INVALID_OPERATOR_BYTES");
  });

  test("path shape outranks a later rule's operator framing", () => {
    const rules: BodyRule[] = [
      { ...eq(1n), path: "0x000000" },
      { ...eq(2n), operator: "0x01" },
    ];
    expectErrorCode(() => PolicyCoder.encode(policyData([rules])), "MALFORMED_PATH");
  });

  test("descriptor length outranks an empty group", () => {
    const descriptor: Hex = `0x${"00".repeat(fieldMax(PolicyFormat.DESC_LENGTH_SIZE) + 1)}`;
    expectErrorCode(() => PolicyCoder.encode(policyData([[eq(1n)], []], descriptor)), "DESC_LENGTH_OVERFLOW");
  });

  test("a malformed rule outranks group count", () => {
    const groups = overfullGroups();
    groups[0] = [{ ...eq(0n), operator: "0x01" }];
    expectErrorCode(() => PolicyCoder.encode(policyData(groups)), "INVALID_OPERATOR_BYTES");
  });
});

///////////////////////////////////////////////////////////////////////////
// Encoder selector
///////////////////////////////////////////////////////////////////////////

describe("PolicyCoder.encode selector", () => {
  test("zeroes a selector beside the selectorless flag", () => {
    const blob = hexToBytes(PolicyCoder.encode({ ...policyData([[eq(1n)]]), isSelectorless: true }));
    expect(blob[0] & PolicyFormat.FLAG_NO_SELECTOR).toBe(PolicyFormat.FLAG_NO_SELECTOR);
    expect([
      ...blob.subarray(PolicyFormat.SELECTOR_OFFSET, PolicyFormat.SELECTOR_OFFSET + PolicyFormat.SELECTOR_SIZE),
    ]).toEqual([0, 0, 0, 0]);
  });
});

///////////////////////////////////////////////////////////////////////////
// Inspection
///////////////////////////////////////////////////////////////////////////

describe("PolicyCoder.inspect", () => {
  test("reads the context test and the calldata test of `context-and-calldata` field by field", () => {
    expect(PolicyCoder.inspect(storageBlob("context-and-calldata"))).toEqual({
      header: {
        value: { major: PolicyFormat.MAJOR, minor: PolicyFormat.MINOR, isSelectorless: false },
        span: { start: 0, end: 1 },
      },
      selector: { value: "0x2fbebd38", span: { start: 1, end: 5 } },
      descLength: { value: 3, span: { start: 5, end: 7 } },
      descriptor: {
        version: { value: DF.VERSION, span: { start: 7, end: 8 } },
        paramCount: { value: 1, span: { start: 8, end: 9 } },
        params: [
          {
            typeClass: "elementary",
            typeCode: TypeCode.UINT_MAX,
            isDynamic: false,
            staticSize: 32,
            span: { start: 9, end: 10 },
          },
        ],
        span: { start: 7, end: 10 },
      },
      groupCount: { value: 1, span: { start: 10, end: 11 } },
      groups: [
        {
          ruleCount: { value: 2, span: { start: 11, end: 13 } },
          groupSize: { value: 78, span: { start: 13, end: 17 } },
          rules: [
            {
              ruleSize: { value: 29, span: { start: 17, end: 19 } },
              scope: { value: Scope.CONTEXT, span: { start: 19, end: 20 } },
              pathDepth: { value: 1, span: { start: 20, end: 21 } },
              path: { value: "0x0000", span: { start: 21, end: 23 } },
              targetType: TypeCode.ADDRESS,
              opCode: { value: Op.EQ, span: { start: 23, end: 24 } },
              dataLength: { value: 20, span: { start: 24, end: 26 } },
              data: { value: `0x${"00".repeat(19)}01`, span: { start: 26, end: 46 } },
              operator: {
                opCode: Op.EQ,
                comparison: Op.EQ,
                negated: false,
                operandType: TypeCode.ADDRESS,
                source: Source.CONSTANT,
                values: [bigintToHex(1n)],
              },
              span: { start: 17, end: 46 },
            },
            {
              ruleSize: { value: 49, span: { start: 46, end: 48 } },
              scope: { value: Scope.CALLDATA, span: { start: 48, end: 49 } },
              pathDepth: { value: 1, span: { start: 49, end: 50 } },
              path: { value: "0x0000", span: { start: 50, end: 52 } },
              hint: {
                hopCount: { value: 0, span: { start: 52, end: 53 } },
                hops: [],
                targetDelta: { value: 0, span: { start: 53, end: 57 } },
                targetMeta: { value: NO_META, span: { start: 57, end: 59 } },
                typeCode: { value: TypeCode.UINT_MAX, span: { start: 59, end: 60 } },
                span: { start: 52, end: 60 },
              },
              targetType: TypeCode.UINT_MAX,
              opCode: { value: Op.EQ, span: { start: 60, end: 61 } },
              dataLength: { value: 32, span: { start: 61, end: 63 } },
              data: { value: bigintToHex(42n), span: { start: 63, end: 95 } },
              operator: {
                opCode: Op.EQ,
                comparison: Op.EQ,
                negated: false,
                operandType: TypeCode.UINT_MAX,
                source: Source.CONSTANT,
                values: [bigintToHex(42n)],
              },
              span: { start: 46, end: 95 },
            },
          ],
          span: { start: 11, end: 95 },
        },
      ],
      span: { start: 0, end: 95 },
    });
  });

  test("reads the loop rule of `loop-all` field by field", () => {
    const inspected = PolicyCoder.inspect(storageBlob("loop-all"));
    expect(inspected.groups[0].rules[0]).toEqual({
      ruleSize: { value: 73, span: { start: 21, end: 23 } },
      scope: { value: Scope.LOOP, span: { start: 23, end: 24 } },
      quantifier: { value: LoopQuantifier.ALL, span: { start: 24, end: 25 } },
      pathDepth: { value: 1, span: { start: 25, end: 26 } },
      path: { value: "0x0000", span: { start: 26, end: 28 } },
      hint: {
        hopCount: { value: 1, span: { start: 28, end: 29 } },
        hops: [
          {
            kind: "plain",
            delta: { value: 0, span: { start: 29, end: 33 } },
            index: { value: PolicyFormat.HINT_NO_INDEX, span: { start: 33, end: 35 } },
            meta: { value: NO_META, span: { start: 35, end: 37 } },
            span: { start: 29, end: 37 },
          },
        ],
        arrayDelta: { value: 0, span: { start: 37, end: 41 } },
        count: { value: 0, span: { start: 41, end: 43 } },
        meta: {
          value: { isElementDynamic: false, isDynamicArray: true, strideWords: 1 },
          span: { start: 43, end: 45 },
        },
        span: { start: 28, end: 45 },
      },
      ruleCount: { value: 1, span: { start: 45, end: 47 } },
      body: [
        {
          ruleSize: { value: 47, span: { start: 47, end: 49 } },
          scope: { value: Scope.CALLDATA, span: { start: 49, end: 50 } },
          pathDepth: { value: 0, span: { start: 50, end: 51 } },
          path: { value: "0x", span: { start: 51, end: 51 } },
          hint: {
            hopCount: { value: 0, span: { start: 51, end: 52 } },
            hops: [],
            targetDelta: { value: 0, span: { start: 52, end: 56 } },
            targetMeta: { value: NO_META, span: { start: 56, end: 58 } },
            typeCode: { value: TypeCode.UINT_MAX, span: { start: 58, end: 59 } },
            span: { start: 51, end: 59 },
          },
          targetType: TypeCode.UINT_MAX,
          opCode: { value: Op.GT, span: { start: 59, end: 60 } },
          dataLength: { value: 32, span: { start: 60, end: 62 } },
          data: { value: bigintToHex(0n), span: { start: 62, end: 94 } },
          operator: {
            opCode: Op.GT,
            comparison: Op.GT,
            negated: false,
            operandType: TypeCode.UINT_MAX,
            source: Source.CONSTANT,
            values: [bigintToHex(0n)],
          },
          span: { start: 47, end: 94 },
        },
      ],
      span: { start: 21, end: 94 },
    });
  });

  test("reads the header and the zero selector slot of a selectorless policy", () => {
    const inspected = PolicyCoder.inspect(storageBlob("selectorless"));
    expect(inspected.header.value).toEqual({
      major: PolicyFormat.MAJOR,
      minor: PolicyFormat.MINOR,
      isSelectorless: true,
    });
    expect(inspected.selector.value).toBe("0x00000000");
  });

  test("states what decode states on every accepted storage vector", () => {
    let compared = 0;
    for (const blob of acceptedBlobs) {
      let decoded: PolicyData;
      try {
        decoded = PolicyCoder.decode(blob);
      } catch (error) {
        if (!(error instanceof CallciumError)) throw error;
        expectErrorCode(() => PolicyCoder.inspect(blob), error.code);
        continue;
      }
      expect(project(PolicyCoder.inspect(blob), blob)).toEqual(decoded);
      compared++;
    }
    expect(compared).toBeGreaterThan(acceptedBlobs.length / 2);
  });

  test("tiles every accepted storage vector with the spans of its fields", () => {
    let tiled = 0;
    for (const blob of acceptedBlobs) {
      let inspected: DecodedPolicy;
      try {
        inspected = PolicyCoder.inspect(blob);
      } catch (error) {
        if (!(error instanceof CallciumError)) throw error;
        continue;
      }
      expectPolicyTiles(inspected);
      tiled++;
    }
    expect(tiled).toBeGreaterThan(acceptedBlobs.length / 2);
  });

  test("parses negated, set, length and context operators and an element hop", () => {
    const sender = ContextProperty.MSG_SENDER;
    const timestamp = ContextProperty.BLOCK_TIMESTAMP;
    const blob = PolicyBuilder.create("f(uint256[],address,uint64)")
      .add(arg(0).lengthGt(1n))
      .add(arg(0, 2).neq(5n))
      .add(arg(1).isIn(["0x0000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000002"]))
      .add(arg(1).eqCtx(sender))
      .add(arg(2).gteCtx(timestamp))
      .build();
    const tests = PolicyCoder.inspect(blob).groups[0].rules.filter((rule): rule is DecodedTest => !("body" in rule));
    const operators = tests.map((rule) => rule.operator);
    expect(operators).toContainEqual({
      opCode: Op.LENGTH_GT,
      comparison: Op.LENGTH_GT,
      negated: false,
      operandType: LENGTH_TYPE,
      source: Source.CONSTANT,
      values: [bigintToHex(1n)],
    });
    expect(operators).toContainEqual({
      opCode: Op.EQ | Op.NOT,
      comparison: Op.EQ,
      negated: true,
      operandType: TypeCode.UINT_MAX,
      source: Source.CONSTANT,
      values: [bigintToHex(5n)],
    });
    expect(operators).toContainEqual({
      opCode: Op.IN,
      comparison: Op.IN,
      negated: false,
      operandType: TypeCode.ADDRESS,
      source: Source.CONSTANT,
      values: [bigintToHex(1n), bigintToHex(2n)],
    });
    expect(operators).toContainEqual({
      opCode: Op.EQ | (Source.CONTEXT << Op.SOURCE_SHIFT),
      comparison: Op.EQ,
      negated: false,
      operandType: TypeCode.ADDRESS,
      source: Source.CONTEXT,
      contextPropertyId: sender,
    });
    // A context operand takes its property's type, not the narrower target's.
    expect(operators).toContainEqual({
      opCode: Op.GTE | (Source.CONTEXT << Op.SOURCE_SHIFT),
      comparison: Op.GTE,
      negated: false,
      operandType: TypeCode.UINT_MAX,
      source: Source.CONTEXT,
      contextPropertyId: timestamp,
    });

    const lengthTest = tests.find((rule) => rule.operator.comparison === Op.LENGTH_GT);
    expect(lengthTest?.hint?.targetMeta.value).toEqual({
      isElementDynamic: false,
      isDynamicArray: true,
      strideWords: 1,
    });
    const elementTest = tests.find((rule) => rule.operator.negated);
    expect(elementTest?.hint?.hops.map((hop) => [hop.kind, hop.index.value])).toEqual([
      ["plain", PolicyFormat.HINT_NO_INDEX],
      ["element", 2],
    ]);
  });
});

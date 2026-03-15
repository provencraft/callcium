import { describe, expect, it } from "vitest";
import descriptorVectors from "../../../../test/vectors/descriptors.json";
import policyVectors from "../../../../test/vectors/policies.json";
import type { Hex } from "../decoder";
import { DecodeError, decodeDescriptor, decodePolicy } from "../decoder";

const ANY_SPAN = expect.objectContaining({
  start: expect.any(Number),
  end: expect.any(Number),
});

///////////////////////////////////////////////////////////////////////////
//                          DESCRIPTOR CONFORMANCE
///////////////////////////////////////////////////////////////////////////

type DescriptorVector = {
  blob: string;
  description: string;
  error: string;
  id: string;
  params: Array<{
    index: number;
    isDynamic: boolean;
    path: string;
    staticSize: number;
    typeCode: number;
  }>;
  version: number;
};

const dVectors = descriptorVectors as DescriptorVector[];

describe("decodeDescriptor", () => {
  for (const vector of dVectors) {
    it(vector.description, () => {
      if (vector.error !== "") {
        try {
          decodeDescriptor(vector.blob);
          expect.fail("Expected DecodeError");
        } catch (e) {
          expect(e).toBeInstanceOf(DecodeError);
          expect((e as DecodeError).code).toBe(vector.error);
        }
        return;
      }
      const result = decodeDescriptor(vector.blob);
      expect(result.version).toBe(vector.version);
      expect(result.params).toEqual(
        vector.params.map((p) => ({
          index: p.index,
          typeCode: p.typeCode,
          isDynamic: p.isDynamic,
          staticSize: p.staticSize,
          path: p.path,
          span: ANY_SPAN,
        })),
      );
    });
  }
});

///////////////////////////////////////////////////////////////////////////
//                            POLICY CONFORMANCE
///////////////////////////////////////////////////////////////////////////

type PolicyVector = {
  blob: string;
  description: string;
  error: string;
  id: string;
  spec: {
    decoded: {
      descriptor: string;
      groups: Array<{
        constraints: Array<{
          operators: string[];
          path: string;
          scope: number;
        }>;
      }>;
      isSelectorless: boolean;
      selector: string;
    };
    encodingInput: unknown;
  };
};

// Group decoded rules by (scope, path) to compare against vector constraints.
function groupRulesIntoConstraints(
  rules: {
    scope: { value: number };
    path: { value: Hex };
    opCode: { value: number };
    data: { value: Hex };
  }[],
): { scope: number; path: Hex; operators: Hex[] }[] {
  const map = new Map<string, { scope: number; path: Hex; operators: Hex[] }>();
  const order: string[] = [];
  for (const rule of rules) {
    const key = `${rule.scope.value}:${rule.path.value}`;
    const opHex = `0x${rule.opCode.value.toString(16).padStart(2, "0")}${rule.data.value.slice(2)}` as Hex;
    const existing = map.get(key);
    if (existing) {
      existing.operators.push(opHex);
    } else {
      map.set(key, {
        scope: rule.scope.value,
        path: rule.path.value,
        operators: [opHex],
      });
      order.push(key);
    }
  }
  // biome-ignore lint/style/noNonNullAssertion: key comes from order which is populated alongside map.
  return order.map((k) => map.get(k)!);
}

describe("decodePolicy", () => {
  for (const vector of policyVectors as PolicyVector[]) {
    it(vector.description, () => {
      if (vector.error !== "") {
        try {
          decodePolicy(vector.blob);
          expect.fail("Expected DecodeError");
        } catch (e) {
          expect(e).toBeInstanceOf(DecodeError);
          expect((e as DecodeError).code).toBe(vector.error);
        }
        return;
      }
      const result = decodePolicy(vector.blob);
      const expected = vector.spec.decoded;
      expect(result.isSelectorless).toBe(expected.isSelectorless);
      expect(result.selector.value).toBe(expected.selector);
      expect(result.descriptor.raw).toBe(expected.descriptor);

      // Compare groups by reconstructing constraints from flat rules.
      expect(result.groups.length).toBe(expected.groups.length);
      for (let gi = 0; gi < expected.groups.length; gi++) {
        const constraints = groupRulesIntoConstraints(result.groups[gi].rules);
        const expectedConstraints = expected.groups[gi].constraints;
        expect(constraints.length).toBe(expectedConstraints.length);
        for (let ci = 0; ci < expectedConstraints.length; ci++) {
          expect(constraints[ci].scope).toBe(expectedConstraints[ci].scope);
          expect(constraints[ci].path).toBe(expectedConstraints[ci].path);
          expect(constraints[ci].operators).toEqual(expectedConstraints[ci].operators);
        }
      }

      // Verify span ordering.
      expect(result.span).toEqual({ start: 0, end: expect.any(Number) });
      for (const group of result.groups) {
        expect(group.span.start).toBeLessThan(group.span.end);
        for (const rule of group.rules) {
          expect(rule.span.start).toBeLessThan(rule.span.end);
        }
      }
    });
  }
});

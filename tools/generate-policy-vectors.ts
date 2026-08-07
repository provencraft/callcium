/**
 * Regenerates `spec/vectors/policies.json` from the SDK implementation.
 *
 * Valid vectors are re-encoded from their `spec.encodingInput`; error vectors are assembled or
 * corrupted programmatically so each defect sits at a known offset. Every emitted vector is
 * verified against the SDK decoder before the file is written: valid blobs must decode, error
 * blobs must raise the error their `error` name maps to.
 *
 * Run from the repo root: `bun tools/generate-policy-vectors.ts`.
 */
import { bytesToHex, hexToBytes, writeBE16, writeBE32 } from "../packages/sdk/src/bytes";
import { Descriptor } from "../packages/sdk/src/descriptor";
import { DescriptorCoder } from "../packages/sdk/src/descriptor-coder";
import { CallciumError } from "../packages/sdk/src/errors";
import { PolicyCoder } from "../packages/sdk/src/policy-coder";

import type { Constraint, Hex, PolicyData } from "../packages/sdk/src/types";

const VECTORS_PATH = new URL("../spec/vectors/policies.json", import.meta.url).pathname;

/** Selector shared by the error vectors: `foo(uint256)`-style fixtures. */
const SELECTOR: Hex = "0x2fbebd38";

///////////////////////////////////////////////////////////////////////////
// Vector schema
///////////////////////////////////////////////////////////////////////////

type VectorRule = { operator: string; path: string; scope: number };
type VectorEncodingInput = {
  descriptor: string;
  groups: { rules: VectorRule[] }[];
  isSelectorless: boolean;
  selector: string;
};

type Vector = {
  blob: string;
  description: string;
  error: string;
  errorArgs: string[];
  id: string;
  spec: {
    decoded: unknown;
    encodingInput: VectorEncodingInput;
  };
};

/** Expected SDK error code per fixture error name, mirroring the conformance suites. */
const SDK_ERROR_MAP: Record<string, string> = {
  MalformedHeader: "MALFORMED_HEADER",
  UnsupportedVersion: "UNSUPPORTED_VERSION",
  UnexpectedEnd: "UNEXPECTED_END",
  EmptyPolicy: "EMPTY_POLICY",
  EmptyGroup: "EMPTY_GROUP",
  EmptyPath: "EMPTY_PATH",
  InvalidContextPath: "INVALID_CONTEXT_PATH",
  InvalidScope: "INVALID_SCOPE",
  RuleSizeMismatch: "RULE_SIZE_MISMATCH",
  MalformedHint: "MALFORMED_HINT",
  GroupSizeMismatch: "GROUP_SIZE_MISMATCH",
  GroupTooSmall: "GROUP_SIZE_MISMATCH",
  GroupOverflow: "GROUP_OVERFLOW",
  RuleTooSmall: "RULE_SIZE_MISMATCH",
  RuleOverflow: "RULE_OVERFLOW",
  UnknownOperator: "INVALID_OPERATOR",
  UnsortedInSet: "UNSORTED_IN_SET",
  PathTooDeep: "PATH_TOO_DEEP",
  UnknownContextProperty: "INVALID_CONTEXT_PROPERTY",
};

///////////////////////////////////////////////////////////////////////////
// Assembly helpers
///////////////////////////////////////////////////////////////////////////

/** Encode a policy blob from a vector's encoding input via the SDK encoder. */
function encodeFromInput(input: VectorEncodingInput): Hex {
  const groups: Constraint[][] = input.groups.map((group) =>
    group.rules.map((rule) => ({
      scope: rule.scope,
      path: hexBody(rule.path),
      operators: [hexBody(rule.operator)],
    })),
  );
  const data: PolicyData = {
    isSelectorless: input.isSelectorless,
    selector: hexBody(input.selector),
    descriptor: hexBody(input.descriptor),
    groups,
  };
  return PolicyCoder.encode(data);
}

/** Narrow a JSON string to a Hex template value. */
function hexBody(value: string): Hex {
  return `0x${value.slice(2)}`;
}

/** Serialize one wire rule. `declaredSize` overrides the size field; `pad` appends zero bytes inside the rule span. */
function rule(fields: {
  scope: number;
  path: string;
  hint: Uint8Array;
  opCode: number;
  data: Uint8Array;
  declaredSize?: number;
  pad?: number;
}): Uint8Array {
  const pad = fields.pad ?? 0;
  const pathBytes = hexToBytes(hexBody(fields.path));
  const actualSize = 7 + pathBytes.length + fields.hint.length + fields.data.length + pad;
  const buf = new Uint8Array(actualSize);
  writeBE16(buf, 0, fields.declaredSize ?? actualSize);
  buf[2] = fields.scope;
  buf[3] = pathBytes.length / 2;
  buf.set(pathBytes, 4);
  buf.set(fields.hint, 4 + pathBytes.length);
  const opOffset = 4 + pathBytes.length + fields.hint.length;
  buf[opOffset] = fields.opCode;
  writeBE16(buf, opOffset + 1, fields.data.length);
  buf.set(fields.data, opOffset + 3);
  return buf;
}

/** Assemble a selector policy blob from a descriptor and one group of wire rules. */
function assemble(desc: Uint8Array, rules: Uint8Array[], declaredGroupSize?: number): Hex {
  const rulesSize = rules.reduce((sum, r) => sum + r.length, 0);
  const blob = new Uint8Array(7 + desc.length + 1 + 6 + rulesSize);
  let offset = 0;
  blob[offset++] = 0x02;
  blob.set(hexToBytes(SELECTOR), offset);
  offset += 4;
  writeBE16(blob, offset, desc.length);
  offset += 2;
  blob.set(desc, offset);
  offset += desc.length;
  blob[offset++] = 1;
  writeBE16(blob, offset, 1);
  writeBE32(blob, offset + 2, declaredGroupSize ?? rulesSize);
  offset += 6;
  for (const r of rules) {
    blob.set(r, offset);
    offset += r.length;
  }
  return bytesToHex(blob);
}

/** Overwrite bytes of `blob` at `byteOffset` with `replacement` hex body. */
function tamper(blob: Hex, byteOffset: number, replacement: string): Hex {
  const hexOffset = 2 + byteOffset * 2;
  return `0x${blob.slice(2, hexOffset)}${replacement}${blob.slice(hexOffset + replacement.length)}`;
}

/** Byte offset of the first rule's hint block. */
function hintOffset(blob: Hex): number {
  return PolicyCoder.inspect(blob).groups[0]!.rules[0]!.hint!.span.start;
}

/** Byte offset of the first rule. */
function ruleOffset(blob: Hex): number {
  return PolicyCoder.inspect(blob).groups[0]!.rules[0]!.span.start;
}

/** A uint256 word as a bytes32 hex string. */
function word(value: number): string {
  return value.toString(16).padStart(64, "0");
}

/** Encode a single-arg error-vector base policy: `eq(42)` on `path` against `typesCsv`. */
function basePolicy(typesCsv: string, path: string, opHex?: string): Hex {
  return encodeFromInput({
    descriptor: bytesToHex(DescriptorCoder.fromTypes(typesCsv)),
    groups: [{ rules: [{ operator: opHex ?? `0x01${word(42)}`, path, scope: 1 }] }],
    isSelectorless: false,
    selector: SELECTOR,
  });
}

/** Build an error vector, deriving `errorArgs` from the offsets the blob decodes to. */
function errorVector(id: string, description: string, error: string, blob: Hex, args: number[]): Vector {
  return {
    blob,
    description,
    error,
    errorArgs: args.map((arg) => `0x${word(arg)}`),
    id,
    spec: {
      decoded: { descriptor: "0x", groups: [], isSelectorless: false, selector: "0x00000000" },
      encodingInput: { descriptor: "0x", groups: [], isSelectorless: false, selector: "0x00000000" },
    },
  };
}

///////////////////////////////////////////////////////////////////////////
// Rebuilt error vectors
///////////////////////////////////////////////////////////////////////////

/** Error vectors whose blobs depend on the hint layout, rebuilt against the current format. */
function rebuiltErrorVectors(): Map<string, Vector> {
  const uint256Desc = DescriptorCoder.fromTypes("uint256");
  const uint256Hint = Descriptor.compileHint(uint256Desc, [0]);

  const valid = basePolicy("uint256", "0x0000");
  const validRuleOffset = ruleOffset(valid);
  const validGroupOffset = PolicyCoder.inspect(valid).groups[0]!.span.start;

  // Path [0, 1] into (bytes,uint256) compiles to one plain hop entering the tuple.
  const plainHop = basePolicy("(bytes,uint256)", "0x00000001");
  // Path [0, 1] into uint256[] compiles to an entry hop followed by an element hop.
  const elementHop = basePolicy("uint256[]", "0x00000001");
  // A quantified path carries the frame and suffix header between the hops and the target.
  const quantified = basePolicy("uint256[]", "0x0000ffff", `0x05${word(42)}`);

  const vectors = [
    errorVector(
      "unknown-opcode",
      "MUST reject: opCode=0x00 (unassigned, unknown operator)",
      "UnknownOperator",
      tamper(valid, PolicyCoder.inspect(valid).groups[0]!.rules[0]!.opCode.span.start, "00"),
      [validRuleOffset],
    ),
    errorVector(
      "eq-invalid-payload-size",
      "MUST reject: EQ operator with 20-byte payload (requires exactly 32)",
      "UnknownOperator",
      assemble(uint256Desc, [
        rule({ scope: 1, path: "0x0000", hint: uint256Hint, opCode: 0x01, data: new Uint8Array(20) }),
      ]),
      [validRuleOffset],
    ),
    errorVector(
      "in-invalid-payload-size",
      "MUST reject: IN operator with 45-byte payload (must be non-zero multiple of 32)",
      "UnknownOperator",
      assemble(uint256Desc, [
        rule({ scope: 1, path: "0x0000", hint: uint256Hint, opCode: 0x07, data: new Uint8Array(45) }),
      ]),
      [validRuleOffset],
    ),
    errorVector(
      "empty-path",
      "MUST reject: rule with pathDepth=0 (a path must have at least one step)",
      "EmptyPath",
      assemble(uint256Desc, [
        rule({ scope: 1, path: "0x", hint: uint256Hint, opCode: 0x01, data: hexToBytes(`0x${word(42)}`) }),
      ]),
      [validRuleOffset],
    ),
    errorVector(
      "path-too-deep",
      "MUST reject: rule with pathDepth=33 (exceeds MAX_PATH_DEPTH)",
      "PathTooDeep",
      assemble(uint256Desc, [
        rule({
          scope: 1,
          path: `0x${"0000".repeat(33)}`,
          hint: uint256Hint,
          opCode: 0x01,
          data: hexToBytes(`0x${word(42)}`),
        }),
      ]),
      [validRuleOffset, 33],
    ),
    errorVector(
      "rule-overflow",
      "MUST reject: declared rule size extends past the group boundary",
      "RuleOverflow",
      assemble(uint256Desc, [
        rule({
          scope: 1,
          path: "0x0000",
          hint: uint256Hint,
          opCode: 0x01,
          data: hexToBytes(`0x${word(42)}`),
          declaredSize: 60,
        }),
      ]),
      [validRuleOffset],
    ),
    errorVector(
      "rule-size-mismatch",
      "MUST reject: declared rule size exceeds the computed field layout by 2 bytes",
      "RuleSizeMismatch",
      assemble(uint256Desc, [
        rule({
          scope: 1,
          path: "0x0000",
          hint: uint256Hint,
          opCode: 0x01,
          data: hexToBytes(`0x${word(42)}`),
          declaredSize: 51,
          pad: 2,
        }),
      ]),
      [validRuleOffset],
    ),
    errorVector(
      "group-size-mismatch",
      "MUST reject: rules do not exactly fill the declared group size (2 trailing bytes)",
      "GroupSizeMismatch",
      assemble(
        uint256Desc,
        [
          rule({ scope: 1, path: "0x0000", hint: uint256Hint, opCode: 0x01, data: hexToBytes(`0x${word(42)}`) }),
          new Uint8Array(2),
        ],
        51,
      ),
      [validGroupOffset],
    ),
    errorVector(
      "unsorted-in-set",
      "MUST reject: IN operands not strictly ascending (3,1,2); the enforcer binary search relies on sorted sets",
      "UnsortedInSet",
      basePolicy("uint256", "0x0000", `0x07${word(3)}${word(1)}${word(2)}`),
      [validRuleOffset],
    ),
    errorVector(
      "hint-reserved-kind",
      "MUST reject: hint header kind 3 is reserved",
      "MalformedHint",
      tamper(quantified, hintOffset(quantified), "c1"),
      [ruleOffset(quantified)],
    ),
    errorVector(
      "hint-reserved-hop-index",
      "MUST reject: hop index 0xFFFE is reserved",
      "MalformedHint",
      tamper(plainHop, hintOffset(plainHop) + 1 + 4, "fffe"),
      [ruleOffset(plainHop)],
    ),
    errorVector(
      "hint-plain-hop-meta",
      "MUST reject: a plain hop carries a non-zero meta word",
      "MalformedHint",
      tamper(plainHop, hintOffset(plainHop) + 1 + 6, "0001"),
      [ruleOffset(plainHop)],
    ),
    errorVector(
      "hint-element-hop-delta",
      "MUST reject: an element hop carries a non-zero delta",
      "MalformedHint",
      tamper(elementHop, hintOffset(elementHop) + 1 + 8, "00000001"),
      [ruleOffset(elementHop)],
    ),
    errorVector(
      "hint-hop-meta-reserved-bits",
      "MUST reject: hop meta word carries reserved bits",
      "MalformedHint",
      tamper(elementHop, hintOffset(elementHop) + 1 + 8 + 6, "5001"),
      [ruleOffset(elementHop)],
    ),
    errorVector(
      "hint-frame-meta-reserved-bits",
      "MUST reject: quantifier frame meta word carries reserved bits",
      "MalformedHint",
      tamper(quantified, hintOffset(quantified) + 1 + 8 + 6, "5001"),
      [ruleOffset(quantified)],
    ),
    errorVector(
      "hint-suffix-reserved-bits",
      "MUST reject: suffix header carries reserved bits",
      "MalformedHint",
      tamper(quantified, hintOffset(quantified) + 1 + 8 + 8, "80"),
      [ruleOffset(quantified)],
    ),
    errorVector(
      "hint-target-meta-unused",
      "MUST reject: target meta word is non-zero for a non-array target",
      "MalformedHint",
      tamper(valid, hintOffset(valid) + 1 + 4, "0001"),
      [validRuleOffset],
    ),
  ];

  return new Map(vectors.map((vector) => [vector.id, vector]));
}

///////////////////////////////////////////////////////////////////////////
// Verification
///////////////////////////////////////////////////////////////////////////

/** Assert a vector's blob behaves as its `error` field declares under the SDK decoder. */
function verify(vector: Vector): void {
  if (vector.error === "") {
    const roundTrip = PolicyCoder.encode(PolicyCoder.decode(hexBody(vector.blob)));
    if (roundTrip !== vector.blob) {
      throw new Error(`${vector.id}: round-trip mismatch\n  blob ${vector.blob}\n  got  ${roundTrip}`);
    }
    return;
  }
  const expected = SDK_ERROR_MAP[vector.error];
  if (expected === undefined) throw new Error(`${vector.id}: no SDK mapping for error ${vector.error}`);
  try {
    PolicyCoder.inspect(hexBody(vector.blob));
  } catch (error) {
    if (error instanceof CallciumError && error.code === expected) return;
    throw new Error(`${vector.id}: expected ${expected}, got ${error instanceof CallciumError ? error.code : error}`);
  }
  throw new Error(`${vector.id}: expected ${expected}, but the blob decoded cleanly`);
}

///////////////////////////////////////////////////////////////////////////
// Main
///////////////////////////////////////////////////////////////////////////

/** Ids of retired vectors dropped from the suite. */
const RETIRED = new Set(["hint-sentinel-offset-with-type", "hint-concrete-offset-without-type"]);

const existing: Vector[] = await Bun.file(VECTORS_PATH).json();
const rebuilt = rebuiltErrorVectors();

const output: Vector[] = [];
for (const vector of existing) {
  if (RETIRED.has(vector.id)) continue;
  const replacement = rebuilt.get(vector.id);
  if (replacement !== undefined) {
    rebuilt.delete(vector.id);
    output.push(replacement);
    continue;
  }
  if (vector.error === "") {
    const blob = encodeFromInput(vector.spec.encodingInput);
    // Groups sort by hash of their rule bytes, so the expected decode order derives from the blob.
    const decodedGroups = PolicyCoder.decode(blob).groups.map((group) => ({
      constraints: group.map((constraint) => ({
        operators: constraint.operators,
        path: constraint.path,
        scope: constraint.scope,
      })),
    }));
    const decoded = { ...(vector.spec.decoded as Record<string, unknown>), groups: decodedGroups };
    output.push({ ...vector, blob, spec: { ...vector.spec, decoded } });
    continue;
  }
  output.push(vector);
}
// Vectors with no predecessor in the file append at the end.
output.push(...rebuilt.values());

for (const vector of output) verify(vector);

/** Deep-sort object keys so the emitted JSON matches the committed formatting. */
function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .toSorted(([a], [b]) => (a < b ? -1 : 1))
        .map(([k, v]) => [k, sortKeys(v)]),
    );
  }
  return value;
}

await Bun.write(VECTORS_PATH, `${JSON.stringify(sortKeys(output), null, 2)}\n`);
console.log(`Wrote ${output.length} vectors to ${VECTORS_PATH}`);

// Replays the Lean differential corpus through the SDK and writes each line with the SDK's verdict, for the Lean
// checkers: `id blob verdict` in `out/storage.txt`, `id blob encoded` in `out/encoding.txt`,
// `id blob callData context outcome` in `out/enforcement.txt`, for the corpus and its mutated-calldata lines, and
// `id blob issues` in `out/validation.txt`.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

import { findContextProperty, MAX_CONTEXT_PROPERTY_ID } from "../src/constants";
import { CallciumError } from "../src/errors";
import { PolicyCoder, validatePolicy } from "../src/policy-coder";
import { PolicyEnforcer, VIOLATION_EFFECT } from "../src/policy-enforcer";
import { PolicyValidator } from "../src/policy-validator";

import type { CallciumErrorCode } from "../src/errors";
import type { Context, Hex } from "../src/types";

const CORPUS_DIR = "../../spec/lean/corpus";
const OUT_DIR = "out";

/** The codes an integrity error throws, which the corpus spells `integrity`. */
const integrityErrors: ReadonlySet<CallciumErrorCode> = new Set<CallciumErrorCode>([
  "MALFORMED_HEADER",
  "UNSUPPORTED_VERSION",
  "UNSUPPORTED_MINOR",
]);

/**
 * The codes re-encoding refuses a policy with: a descriptor whose composite node disagrees with its children, a path
 * that does not compile, or a comparison or a constant its target's type cannot hold.
 */
const encoderRefusals: ReadonlySet<CallciumErrorCode> = new Set<CallciumErrorCode>([
  "NODE_LENGTH_MISMATCH",
  "STATIC_WORDS_MISMATCH",
  "PARAM_INDEX_OUT_OF_BOUNDS",
  "TUPLE_FIELD_OUT_OF_BOUNDS",
  "STATIC_ARRAY_INDEX_OUT_OF_BOUNDS",
  "NOT_COMPOSITE",
  "QUANTIFIER_ON_NON_ARRAY",
  "OPERATOR_TARGET_MISMATCH",
  "OUT_OF_PHYSICAL_BOUNDS",
]);

/** A corpus hex field as a hex value; malformed hex is a corpus fault. */
function hexField(field: string): Hex {
  if (!field.startsWith("0x")) throw new Error(`Field is not 0x-prefixed hex: ${field}`);
  return `0x${field.slice(2)}`;
}

/** The non-empty lines of a corpus file, each split into its fields. */
function corpusLines(name: string, fieldCount: number): string[][] {
  return readFileSync(`${CORPUS_DIR}/${name}`, "utf8")
    .split("\n")
    .filter((line) => line !== "")
    .map((line) => {
      const fields = line.split(" ");
      if (fields.length !== fieldCount) throw new Error(`Malformed ${name} line: ${line}`);
      return fields;
    });
}

/** The storage verdict on a blob. */
function storageVerdict(blob: string): "accept" | "reject" {
  try {
    validatePolicy(hexField(blob));
    return "accept";
  } catch (error) {
    // Malformed hex is a corpus fault, never a verdict.
    if (error instanceof CallciumError && error.code !== "INVALID_HEX") return "reject";
    throw error;
  }
}

/** The blob the encoder gives for the policy `blob` states; `0x` where re-encoding refuses it. */
function encoded(blob: string): Hex {
  const policy = hexField(blob);
  try {
    return PolicyCoder.encode(PolicyCoder.decode(policy));
  } catch (error) {
    if (error instanceof CallciumError && encoderRefusals.has(error.code)) return "0x";
    throw error;
  }
}

/** The context a corpus field spells: one 32-byte word per property. */
function corpusContext(field: string): Context {
  const entries = field.split(",");
  if (entries.length !== MAX_CONTEXT_PROPERTY_ID + 1) throw new Error(`Malformed context field: ${field}`);
  const context: Context = {};
  entries.forEach((entry, propertyId) => {
    const word = BigInt(hexField(entry));
    const key = findContextProperty(propertyId)!.contextKey;
    if (key === "msgSender" || key === "txOrigin") {
      // An address context value is its low 20 bytes, so a corpus word above them is a corpus fault.
      if (word >> 160n !== 0n) throw new Error(`Address context word carries high bytes: ${entry}`);
      context[key] = `0x${word.toString(16).padStart(40, "0")}`;
    } else {
      context[key] = word;
    }
  });
  return context;
}

/** The enforcement outcome as the corpus spells it: `pass`, `fail`, an abort's code, or `integrity`. */
function enforcementOutcome(blob: string, callData: string, context: string): string {
  try {
    const result = PolicyEnforcer.check(hexField(blob), hexField(callData), corpusContext(context));
    if (result.ok) return "pass";
    const last = result.violations.at(-1)!;
    return VIOLATION_EFFECT[last.code] === "abort" ? last.code : "fail";
  } catch (error) {
    if (error instanceof CallciumError && integrityErrors.has(error.code)) return "integrity";
    throw error;
  }
}

/** The issues the validator reports on a blob as the corpus spells them: `CODE@g.r[.b]` comma separated, `-` for none. */
function validationIssues(blob: string): string {
  const keys = PolicyValidator.validate(hexField(blob)).map((issue) => {
    const location = [issue.groupIndex, issue.ruleIndex, issue.bodyRuleIndex].filter((index) => index !== undefined);
    return location.length === 0 ? issue.code : `${issue.code}@${location.join(".")}`;
  });
  return keys.length === 0 ? "-" : keys.join(",");
}

const storageLines = corpusLines("storage.txt", 3).map(([id, blob]) => `${id} ${blob} ${storageVerdict(blob)}`);
const encodingLines = corpusLines("encoding.txt", 3).map(([id, blob]) => `${id} ${blob} ${encoded(blob)}`);
const replayEnforcement = ([id, blob, callData, context]: string[]) =>
  `${id} ${blob} ${callData} ${context} ${enforcementOutcome(blob, callData, context)}`;
const enforcementLines = [
  ...corpusLines("enforcement.txt", 5).map(replayEnforcement),
  ...corpusLines("enforcement-mutants.txt", 4).map(replayEnforcement),
];
const validationLines = corpusLines("validation.txt", 3).map(([id, blob]) => `${id} ${blob} ${validationIssues(blob)}`);

mkdirSync(OUT_DIR, { recursive: true });
writeFileSync(`${OUT_DIR}/storage.txt`, `${storageLines.join("\n")}\n`);
writeFileSync(`${OUT_DIR}/encoding.txt`, `${encodingLines.join("\n")}\n`);
writeFileSync(`${OUT_DIR}/enforcement.txt`, `${enforcementLines.join("\n")}\n`);
writeFileSync(`${OUT_DIR}/validation.txt`, `${validationLines.join("\n")}\n`);

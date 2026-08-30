import { bytesToHex, hexToBytes, readU16, writeBE16 } from "./bytes";
import { buildCodeMap, PolicyFormat as PF } from "./constants";
import { CallciumError } from "./errors";

import type { Hex } from "./types";

///////////////////////////////////////////////////////////////////////////
// Quantifier steps
///////////////////////////////////////////////////////////////////////////

const QUANTIFIER_TABLE = [
  { key: "ALL", code: 0xffff, label: "all" },
  { key: "ANY", code: 0xfffe, label: "any" },
] as const;

/** Reserved path step values that trigger quantified evaluation over array elements. */
export const Quantifier = buildCodeMap(QUANTIFIER_TABLE);

/** Display metadata for a quantifier step. */
export type QuantifierInfo = { label: string };

const quantifierByCode: ReadonlyMap<number, QuantifierInfo> = new Map<number, QuantifierInfo>(
  QUANTIFIER_TABLE.map((e) => [e.code, { label: e.label }]),
);

/** Check whether a path step is a quantifier (ALL or ANY). */
export function isQuantifier(step: number): boolean {
  return step >= Quantifier.ANY;
}

/**
 * Map a quantifier path step to its display label.
 * @param code - Quantifier step value.
 * @returns Display metadata for the quantifier.
 * @throws {CallciumError} If the code is not a recognised quantifier.
 */
export function lookupQuantifier(code: number): QuantifierInfo {
  const info = quantifierByCode.get(code);
  if (!info) throw new CallciumError("UNKNOWN_QUANTIFIER", `Unknown quantifier step 0x${code.toString(16)}`);
  return info;
}

///////////////////////////////////////////////////////////////////////////
// Path steps
///////////////////////////////////////////////////////////////////////////

/** Encode a sequence of uint16 path steps as a big-endian hex string. */
export function encodePath(steps: readonly number[]): Hex {
  const buffer = new Uint8Array(steps.length * 2);
  for (let i = 0; i < steps.length; i++) {
    writeBE16(buffer, i * 2, steps[i]!);
  }
  return bytesToHex(buffer);
}

/**
 * Parse a BE16-encoded hex path into an array of step values.
 * @param path - 0x-prefixed hex string containing BE16-encoded path steps.
 * @returns Array of numeric step values.
 */
export function parsePathSteps(path: Hex): number[] {
  const bytes = hexToBytes(path);
  if (bytes.length % PF.PATH_STEP_SIZE !== 0) {
    throw new CallciumError("MALFORMED_PATH", `Path byte length ${bytes.length} is not a whole number of steps`);
  }
  const steps: number[] = [];
  for (let offset = 0; offset < bytes.length; offset += PF.PATH_STEP_SIZE) {
    steps.push(readU16(bytes, offset));
  }
  return steps;
}

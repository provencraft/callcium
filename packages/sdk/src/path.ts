import { bytesToHex, hexToBytes, readU16, writeBE16 } from "./bytes";
import { buildCodeMap, formatCode, PolicyFormat as PF } from "./constants";
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
  QUANTIFIER_TABLE.map((entry) => [entry.code, { label: entry.label }]),
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
  if (!info)
    throw new CallciumError("UNKNOWN_QUANTIFIER", `Unknown quantifier step ${formatCode(code, PF.PATH_STEP_SIZE)}`);
  return info;
}

///////////////////////////////////////////////////////////////////////////
// Path steps
///////////////////////////////////////////////////////////////////////////

/**
 * Encode a sequence of uint16 path steps as a big-endian hex string.
 * @throws {CallciumError} When a step is not an integer the field holds. A wrapped step would
 * address a different argument.
 */
export function encodePath(steps: readonly number[]): Hex {
  const buffer = new Uint8Array(steps.length * PF.PATH_STEP_SIZE);
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i]!;
    if (!Number.isInteger(step) || step < 0 || step > PF.PATH_STEP_MAX) {
      throw new CallciumError("PATH_STEP_OVERFLOW", `Path step ${step} is outside the path step field`);
    }
    writeBE16(buffer, i * PF.PATH_STEP_SIZE, step);
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

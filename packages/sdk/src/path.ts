import { bytesToHex, hexToBytes, readU16, writeBE16 } from "./bytes";
import { buildCodeMap, fieldMax, PolicyFormat as PF } from "./constants";
import { CallciumError } from "./errors";

import type { Hex } from "./types";

///////////////////////////////////////////////////////////////////////////
// Quantifier steps
///////////////////////////////////////////////////////////////////////////

const QUANTIFIER_TABLE = [
  { key: "ALL", code: 0xffff },
  { key: "ANY", code: 0xfffe },
] as const;

/** Path steps that quantify over the array before them: `ALL` over every element, `ANY` over some element. */
export const Quantifier = buildCodeMap(QUANTIFIER_TABLE);

///////////////////////////////////////////////////////////////////////////
// Path steps
///////////////////////////////////////////////////////////////////////////

/**
 * Encode a sequence of uint16 path steps as a big-endian hex string.
 * @throws {CallciumError} When a step is not an integer the field can represent.
 * A wrapped step addresses another argument.
 */
export function encodePath(steps: readonly number[]): Hex {
  const buffer = new Uint8Array(steps.length * PF.PATH_STEP_SIZE);
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i]!;
    if (!Number.isInteger(step) || step < 0 || step > fieldMax(PF.PATH_STEP_SIZE)) {
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

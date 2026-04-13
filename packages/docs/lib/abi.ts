import { DescriptorCoder } from "@callcium/sdk";
import type { Abi } from "viem";

///////////////////////////////////////////////////////////////////////////
// JSON parsing
///////////////////////////////////////////////////////////////////////////

/** Parse a JSON ABI string into an Abi, or return an Error on failure. */
export function parseAbiJson(input: string): Abi | Error {
  const trimmed = input.trim();
  if (!trimmed) return new Error("Empty input.");
  try {
    const parsed = JSON.parse(trimmed);
    if (!Array.isArray(parsed)) return new Error("ABI must be a JSON array.");
    return parsed as Abi;
  } catch (e) {
    return e instanceof Error ? e : new Error("Invalid JSON.");
  }
}

///////////////////////////////////////////////////////////////////////////
// 4-byte selector lookup
///////////////////////////////////////////////////////////////////////////

/** Look up a function name by its 4-byte selector via the Sourcify API. */
export async function lookup4byte(selector: string, signal?: AbortSignal): Promise<string | null> {
  try {
    const res = await fetch(`https://api.4byte.sourcify.dev/signature-database/v1/lookup?function=${selector}`, {
      signal,
    });
    if (!res.ok) return null;
    const data = await res.json();
    const results = data?.result?.function?.[selector];
    if (!Array.isArray(results) || results.length === 0) return null;
    const sig = results[0].name;
    if (typeof sig !== "string") return null;
    const parenIndex = sig.indexOf("(");
    return parenIndex > 0 ? sig.slice(0, parenIndex) : sig;
  } catch {
    return null;
  }
}

///////////////////////////////////////////////////////////////////////////
// Descriptor → type string recovery
///////////////////////////////////////////////////////////////////////////

/** Reconstruct the parameter types string from a binary descriptor. */
export const descriptorToTypes = DescriptorCoder.toTypes;

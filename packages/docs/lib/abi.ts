import { type Abi, type AbiFunction, toFunctionSelector } from "viem";
import { formatAbiItem } from "viem/utils";

///////////////////////////////////////////////////////////////////////////
// ABI parsing
///////////////////////////////////////////////////////////////////////////

/** True when a function has no name or viem cannot hash or format it, such as without `inputs` or with an untyped input. */
function isMalformed(abiFunction: AbiFunction): boolean {
  if (!abiFunction.name) return true;
  try {
    toFunctionSelector(abiFunction);
    formatAbiItem(abiFunction);
    return false;
  } catch {
    return true;
  }
}

/** Parse the functions of a JSON ABI string, state-changing ones first, or return an Error on failure. */
export function parseAbiFunctions(input: string): AbiFunction[] | Error {
  if (!input.trim()) return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(input);
  } catch (error) {
    return error instanceof Error ? error : new Error("Invalid JSON.");
  }
  if (!Array.isArray(parsed)) return new Error("ABI must be a JSON array.");
  const functions = parsed.filter((item): item is AbiFunction => item?.type === "function");
  const malformed = functions.find(isMalformed);
  if (malformed) return new Error(`Function "${malformed.name ?? ""}" is malformed.`);
  // View and pure functions follow the state-changing ones, each in ABI order.
  return functions.toSorted((left, right) => Number(isReadOnly(left)) - Number(isReadOnly(right)));
}

function isReadOnly(abiFunction: AbiFunction): boolean {
  return abiFunction.stateMutability === "view" || abiFunction.stateMutability === "pure";
}

///////////////////////////////////////////////////////////////////////////
// 4-byte selector lookup
///////////////////////////////////////////////////////////////////////////

const identifier = /^[A-Za-z_$][\w$]*$/;

/** Look up a function name by its 4-byte selector via the Sourcify API, or null when no valid name is found. */
export async function lookup4byte(selector: string, signal?: AbortSignal): Promise<string | null> {
  try {
    const response = await fetch(`https://api.4byte.sourcify.dev/signature-database/v1/lookup?function=${selector}`, {
      signal,
    });
    if (!response.ok) return null;

    const data = await response.json();
    const results = data?.result?.function?.[selector];
    if (!Array.isArray(results) || results.length === 0) return null;

    const signature = results[0].name;
    if (typeof signature !== "string") return null;

    const parenIndex = signature.indexOf("(");
    const name = parenIndex > 0 ? signature.slice(0, parenIndex) : signature;
    return identifier.test(name) ? name : null;
  } catch {
    return null;
  }
}

///////////////////////////////////////////////////////////////////////////
// Sourcify ABI lookup
///////////////////////////////////////////////////////////////////////////

const SOURCIFY_TIMEOUT = 15_000;

type SourcifyContract = {
  abi: Abi | null;
  proxyResolution?: { isProxy: boolean; implementations: { address: string; name?: string }[] } | null;
};

/** Fetch a verified contract's ABI from Sourcify, or its implementation's for a proxy. Null when Sourcify has none. Throws when the request fails. */
export async function fetchAbi(chainId: number, address: string): Promise<Abi | null> {
  const contract = await getSourcifyContract(chainId, address);
  if (!contract?.abi) return null;
  // ponytail: first implementation only; merge them all when a proxy with several needs it.
  const implementation = contract.proxyResolution?.isProxy ? contract.proxyResolution.implementations[0] : undefined;
  // Sourcify names an implementation only when the implementation is verified.
  if (!implementation?.name) return contract.abi;
  return (await getSourcifyContract(chainId, implementation.address))?.abi ?? contract.abi;
}

async function getSourcifyContract(chainId: number, address: string): Promise<SourcifyContract | null> {
  // Sourcify rejects a mixed-case address with a wrong checksum, so the address goes lowercase.
  const response = await fetch(
    `https://sourcify.dev/server/v2/contract/${chainId}/${address.toLowerCase()}?fields=abi,proxyResolution`,
    { signal: AbortSignal.timeout(SOURCIFY_TIMEOUT) },
  );
  // Sourcify answers 404 for an address without a verified contract.
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`Sourcify returned ${response.status}.`);
  return response.json();
}

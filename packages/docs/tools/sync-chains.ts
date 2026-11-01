import { writeFile } from "node:fs/promises";
import { join } from "node:path";

const CHAINS_URL = "https://sourcify.dev/server/chains";
const OUTPUT = join(import.meta.dirname, "../lib/sourcify-chains.json");

type SourcifyChain = { chainId: number; name: string; supported: boolean };

const response = await fetch(CHAINS_URL);
if (!response.ok) throw new Error(`Sourcify returned ${response.status}`);
const chains = (await response.json()) as SourcifyChain[];

// A supported chain is one Sourcify verifies contracts on.
const supported = chains
  .filter((chain) => chain.supported)
  .map((chain) => ({ id: chain.chainId, name: chain.name.trim() }))
  .toSorted((left, right) => left.name.localeCompare(right.name, "en"));
if (supported.length === 0) throw new Error("Sourcify listed no supported chains");

await writeFile(OUTPUT, `${JSON.stringify(supported, null, 2)}\n`);
console.log(`Wrote ${supported.length} chains to ${OUTPUT}`);

// Checks the Lean model's ABI decoder against solc's: writes the decoder-fidelity corpus, then runs the Lean check on
// it. Takes the seed of Foundry's random cheatcodes, random by default, and the cases per shape, 512 by default, as its
// arguments.

import { resolve } from "node:path";
import { $ } from "bun";

const LEAN_DIR = "../../spec/lean";
const CORPUS = resolve("out/decoder-fidelity.txt");
const [SEED = String(Math.floor(Math.random() * 2 ** 32)), CASES = "512"] = Bun.argv.slice(2);

// A model that reads a length no reader read builds a value that size; the limit makes that a failed run.
const MEMORY_LIMIT_KB = 8_000_000;

console.log(`seed: ${SEED}`);
await $`bun run corpus:decoder-fidelity ${CASES}`.env({ ...process.env, FOUNDRY_FUZZ_SEED: SEED });
await $`lake build decoder-fidelity`.cwd(LEAN_DIR);
await $`sh -c ${`ulimit -v ${MEMORY_LIMIT_KB} && exec .lake/build/bin/decoder-fidelity "$0"`} ${CORPUS}`.cwd(LEAN_DIR);

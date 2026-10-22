// Runs the differential checks against the Lean model: generates the corpus, replays it in Foundry, then checks every
// Solidity verdict, outcome and issue in Lean. Takes the corpus seed as its argument, random by default; the generator
// prints it. Needs `lake` on `PATH`.

import { resolve } from "node:path";
import { $ } from "bun";

const LEAN_DIR = "../../spec/lean";
const SEED = Bun.argv[2] ?? String(Math.floor(Math.random() * 2 ** 32));
const CASES = 1000;

await $`lake build generate-corpus check-encoding check-enforcement check-storage check-validation`.cwd(LEAN_DIR);
await $`lake exe generate-corpus ${SEED} ${CASES} corpus`.cwd(LEAN_DIR);
await $`bun run corpus:mutants`.env({ ...process.env, FOUNDRY_FUZZ_SEED: SEED });
await $`forge test --match-path 'test/differential/*'`;
await $`lake exe check-storage corpus/storage.txt ${resolve("out/storage.txt")}`.cwd(LEAN_DIR);
await $`lake exe check-enforcement corpus/enforcement.txt ${resolve("out/enforcement.txt")}`.cwd(LEAN_DIR);
await $`lake exe check-encoding corpus/encoding.txt ${resolve("out/encoding.txt")}`.cwd(LEAN_DIR);
await $`lake exe check-validation corpus/validation.txt ${resolve("out/validation.txt")}`.cwd(LEAN_DIR);

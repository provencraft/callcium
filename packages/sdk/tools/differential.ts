// Runs the differential checks against the Lean model: generates the corpus, replays it through the SDK, then
// checks every SDK verdict, outcome and issue in Lean. Takes the corpus seed as its argument, random by default; the
// generator prints it. The mutated-calldata lines come from the contracts package. Needs `lake` and `forge` on `PATH`.

import { $ } from "bun";
import { resolve } from "node:path";

const LEAN_DIR = "../../spec/lean";
const SEED = Bun.argv[2] ?? String(Math.floor(Math.random() * 2 ** 32));
const CASES = 1000;

await $`lake build generate-corpus check-encoding check-enforcement check-storage check-validation`.cwd(LEAN_DIR);
await $`lake exe generate-corpus ${SEED} ${CASES} corpus`.cwd(LEAN_DIR);
await $`bun run corpus:mutants`.cwd("../contracts").env({ ...process.env, FOUNDRY_FUZZ_SEED: SEED });
await $`bun tools/replay.ts`;
await $`lake exe check-storage corpus/storage.txt ${resolve("out/storage.txt")}`.cwd(LEAN_DIR);
await $`lake exe check-enforcement corpus/enforcement.txt ${resolve("out/enforcement.txt")}`.cwd(LEAN_DIR);
await $`lake exe check-encoding corpus/encoding.txt ${resolve("out/encoding.txt")}`.cwd(LEAN_DIR);
await $`lake exe check-validation corpus/validation.txt ${resolve("out/validation.txt")}`.cwd(LEAN_DIR);

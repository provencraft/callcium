// Runs forge's mutation runner on the given arguments. The runner copies the project into `TMPDIR` and runs the tests
// there, so the copies go one level below the repo root, where `../../spec` still resolves.

import { mkdir, rm } from "node:fs/promises";
import { resolve } from "node:path";

const COPIES = resolve("../../.mutation-tmp");

// A run killed outright leaves its copies behind, so each run clears the directory first.
await rm(COPIES, { recursive: true, force: true });
await mkdir(COPIES);

const runner = Bun.spawn(["forge", "test", "--mutation-jobs", "1", "--mutate", ...Bun.argv.slice(2)], {
  env: { ...process.env, TMPDIR: COPIES },
  stdio: ["inherit", "inherit", "inherit"],
});
for (const signal of ["SIGINT", "SIGTERM"] as const) process.on(signal, () => runner.kill(signal));

const exitCode = await runner.exited;
await rm(COPIES, { recursive: true, force: true });
process.exit(exitCode);

import { mkdir, cp, rm, readdir } from "node:fs/promises";
import { existsSync } from "node:fs";

const SNAPSHOTS_DIR = "snapshots";
const BASELINE_DIR = ".snapshots_baseline";

if (!existsSync(SNAPSHOTS_DIR)) {
  console.error(`Error: ${SNAPSHOTS_DIR}/ not found. Run benchmark tests first.`);
  process.exit(1);
}

if (existsSync(BASELINE_DIR)) {
  await rm(BASELINE_DIR, { recursive: true });
}

await mkdir(BASELINE_DIR);
await cp(SNAPSHOTS_DIR, BASELINE_DIR, { recursive: true });

const files = (await readdir(BASELINE_DIR)).filter((f) => f.endsWith(".json"));
console.log(`Baseline saved: ${files.length} files copied to ${BASELINE_DIR}/`);

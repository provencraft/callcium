import { readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, basename } from "node:path";

const SNAPSHOTS_DIR = "snapshots";
const BASELINE_DIR = ".snapshots_baseline";
const SEPARATOR = "\u2500".repeat(68);

const isTTY = process.stdout.isTTY ?? false;
const green = (s: string) => (isTTY ? `\x1b[32m${s}\x1b[0m` : s);
const red = (s: string) => (isTTY ? `\x1b[31m${s}\x1b[0m` : s);
const bold = (s: string) => (isTTY ? `\x1b[1m${s}\x1b[0m` : s);
const dim = (s: string) => (isTTY ? `\x1b[2m${s}\x1b[0m` : s);

type Snapshot = Record<string, string>;

interface FileDiff {
  name: string;
  changed: { key: string; before: number; after: number; delta: number }[];
  added: { key: string; value: number }[];
  removed: { key: string; value: number }[];
  unchangedCount: number;
}

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

async function readSnapshot(path: string): Promise<Snapshot> {
  return JSON.parse(await Bun.file(path).text());
}

async function listSnapshots(dir: string): Promise<string[]> {
  if (!existsSync(dir)) return [];
  const entries = await readdir(dir);
  return entries.filter((f) => f.endsWith(".json")).sort();
}

function compareSnapshots(
  name: string,
  before: Snapshot,
  after: Snapshot,
): FileDiff {
  const changed: FileDiff["changed"] = [];
  const added: FileDiff["added"] = [];
  const removed: FileDiff["removed"] = [];
  let unchangedCount = 0;

  const allKeys = new Set([...Object.keys(before), ...Object.keys(after)]);

  for (const key of [...allKeys].sort()) {
    const inBefore = key in before;
    const inAfter = key in after;

    if (inBefore && inAfter) {
      const b = Number(before[key]);
      const a = Number(after[key]);
      if (b !== a) {
        changed.push({ key, before: b, after: a, delta: a - b });
      } else {
        unchangedCount++;
      }
    } else if (inAfter) {
      added.push({ key, value: Number(after[key]) });
    } else {
      removed.push({ key, value: Number(before[key]) });
    }
  }

  return { name, changed, added, removed, unchangedCount };
}

///////////////////////////////////////////////////////////////////////////
// Output
///////////////////////////////////////////////////////////////////////////

function printDiff(diffs: FileDiff[]) {
  console.log(bold("Gas Benchmark Comparison"));
  console.log(SEPARATOR);

  let improved = 0, regressed = 0, unchanged = 0, added = 0, removed = 0;

  for (const diff of diffs) {
    const hasChanges = diff.changed.length > 0 || diff.added.length > 0 || diff.removed.length > 0;

    console.log();
    console.log(bold(diff.name));

    if (hasChanges) {
      console.log(dim(`  ${"Benchmark".padEnd(30)}${"Before".padStart(10)}${"After".padStart(10)}${"Delta".padStart(10)}${"".padStart(8)}`));
    }

    for (const entry of diff.changed) {
      const sign = entry.delta > 0 ? "+" : "";
      const d = `${sign}${entry.delta}`.padStart(10);
      const p = (entry.before !== 0 ? `${sign}${((entry.delta / entry.before) * 100).toFixed(1)}%` : "N/A").padStart(8);
      const color = entry.delta < 0 ? green : red;
      console.log(`  ${entry.key.padEnd(30)}${String(entry.before).padStart(10)}${String(entry.after).padStart(10)}${color(d)}${color(p)}`);
      if (entry.delta < 0) improved++; else regressed++;
    }

    for (const entry of diff.added) {
      console.log(`  ${entry.key.padEnd(30)}${"".padStart(10)}${String(entry.value).padStart(10)}${green("new".padStart(10))}`);
      added++;
    }

    for (const entry of diff.removed) {
      console.log(`  ${entry.key.padEnd(30)}${String(entry.value).padStart(10)}${"".padStart(10)}${red("del".padStart(10))}`);
      removed++;
    }

    if (diff.unchangedCount > 0) {
      console.log(dim(`  (${diff.unchangedCount} unchanged)`));
    }
    unchanged += diff.unchangedCount;
  }

  console.log();
  console.log(SEPARATOR);

  const parts: string[] = [];
  if (improved > 0) parts.push(green(`${improved} improved`));
  if (regressed > 0) parts.push(red(`${regressed} regressed`));
  if (added > 0) parts.push(`${added} new`);
  if (removed > 0) parts.push(`${removed} removed`);
  parts.push(`${unchanged} unchanged`);
  console.log(`Summary: ${parts.join(", ")}`);
}

///////////////////////////////////////////////////////////////////////////
// Main
///////////////////////////////////////////////////////////////////////////

if (!existsSync(BASELINE_DIR)) {
  console.error(
    `Error: No baseline found. Run \`bun run bench:baseline\` first.`,
  );
  process.exit(1);
}

if (!existsSync(SNAPSHOTS_DIR)) {
  console.error(`Error: ${SNAPSHOTS_DIR}/ not found. Run benchmark tests first.`);
  process.exit(1);
}

const baselineFiles = await listSnapshots(BASELINE_DIR);
const currentFiles = await listSnapshots(SNAPSHOTS_DIR);
const allFiles = [...new Set([...baselineFiles, ...currentFiles])].sort();

const diffs: FileDiff[] = [];

for (const file of allFiles) {
  const name = basename(file, ".json");
  const baselinePath = join(BASELINE_DIR, file);
  const currentPath = join(SNAPSHOTS_DIR, file);

  const inBaseline = baselineFiles.includes(file);
  const inCurrent = currentFiles.includes(file);

  if (inBaseline && inCurrent) {
    const before = await readSnapshot(baselinePath);
    const after = await readSnapshot(currentPath);
    diffs.push(compareSnapshots(name, before, after));
  } else if (inCurrent) {
    const after = await readSnapshot(currentPath);
    diffs.push({
      name: `${name} (new file)`,
      changed: [],
      added: Object.entries(after).map(([key, value]) => ({
        key,
        value: Number(value),
      })),
      removed: [],
      unchangedCount: 0,
    });
  } else {
    const before = await readSnapshot(baselinePath);
    diffs.push({
      name: `${name} (removed file)`,
      changed: [],
      added: [],
      removed: Object.entries(before).map(([key, value]) => ({
        key,
        value: Number(value),
      })),
      unchangedCount: 0,
    });
  }
}

printDiff(diffs);

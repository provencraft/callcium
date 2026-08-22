import { existsSync, readFileSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { basename } from "node:path";

// Scopes a mewt campaign to the tests that exercise the target. via-ir recompiles every
// dependent test contract on each mutation, so an unscoped campaign pays for the whole
// test tree per mutant. mewt parses [[per_target]] rules but its runner ignores them, so
// the scoped command has to arrive as a --test.cmd override.
//
// The scope spans the target's transitive importers, not the target alone: a library is
// exercised through its callers' suites as much as its own, and a scope that omits them
// reports mutants as uncaught that the suite does in fact kill.

const [target, ...mewtArgs] = process.argv.slice(2);

if (!target) {
  console.error("Usage: bun tools/mutate.ts <src file> [mewt run args...]");
  process.exit(1);
}

/** The target plus every module that transitively imports it. */
function exercisedBy(contractName: string): Set<string> {
  const importers = new Map<string, Set<string>>();
  for (const file of readdirSync("src").filter((f) => f.endsWith(".sol"))) {
    const importer = basename(file, ".sol");
    const source = readFileSync(`src/${file}`, "utf8");
    for (const [, imported] of source.matchAll(/from\s+"\.\/([A-Za-z0-9_]+)\.sol"/g)) {
      importers.set(imported, (importers.get(imported) ?? new Set()).add(importer));
    }
  }

  const reached = new Set([contractName]);
  const pending = [contractName];
  while (pending.length > 0) {
    for (const importer of importers.get(pending.pop() as string) ?? []) {
      if (reached.has(importer)) continue;
      reached.add(importer);
      pending.push(importer);
    }
  }
  return reached;
}

const contractName = basename(target, ".sol");

// Vectors pin every module, so conformance is always in scope.
const testPaths = ["conformance/*"];
for (const module of exercisedBy(contractName)) {
  const unitDir = module.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
  if (existsSync(`test/unit/${unitDir}`)) testPaths.push(`unit/${unitDir}/*`);
  if (existsSync(`test/unit/${module}.t.sol`)) testPaths.push(`unit/${module}.t.sol`);
}

const testCmd = `forge test --match-path 'test/{${testPaths.join(",")}}'`;
console.log(`Target: ${target}\nTests:  ${testCmd}\n`);

const result = spawnSync("mewt", ["run", "--test.cmd", testCmd, ...mewtArgs, target], {
  stdio: "inherit",
});

process.exit(result.status ?? 1);

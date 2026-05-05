import { $ } from "bun";

const [, , packageName, bump] = Bun.argv;
const validBumps = new Set(["patch", "minor", "major"]);

if (!packageName || !bump) {
  console.error("Usage: bun tools/release-package.ts <package> <patch|minor|major>");
  process.exit(1);
}

if (!validBumps.has(bump)) {
  console.error(`Invalid version bump: ${bump}`);
  process.exit(1);
}

const packageDir = `packages/${packageName}`;
const packageJsonPath = `${packageDir}/package.json`;

if (!(await Bun.file(packageJsonPath).exists())) {
  console.error(`Package not found: ${packageJsonPath}`);
  process.exit(1);
}

const dirtyReleaseFiles = await $`git status --porcelain -- ${packageJsonPath} bun.lock`.text();
if (dirtyReleaseFiles.trim() !== "") {
  console.error(`Release files must be clean before versioning:\n${dirtyReleaseFiles}`);
  process.exit(1);
}

await $`bun pm version ${bump} --no-git-tag-version`.cwd(packageDir);

const packageJson = await Bun.file(packageJsonPath).json();
const version = packageJson.version;
const tag = `${packageName}/v${version}`;

const existingTag = await $`git tag --list ${tag}`.text();
if (existingTag.trim() !== "") {
  console.error(`Tag already exists: ${tag}`);
  process.exit(1);
}

await $`git add ${packageJsonPath} bun.lock`;
await $`git commit -m ${`Release ${packageName} v${version}`}`;
await $`git tag ${tag}`;

console.log(`Created release ${tag}`);

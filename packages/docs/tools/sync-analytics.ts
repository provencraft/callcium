import { copyFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const WEB_ENTRY = fileURLToPath(import.meta.resolve("@openpanel/web"));
const TRACKER = join(dirname(WEB_ENTRY), "src/tracker.global.js");
const OUTPUT_DIR = join(import.meta.dirname, "../public/a");

await mkdir(OUTPUT_DIR, { recursive: true });
await copyFile(TRACKER, join(OUTPUT_DIR, "script.js"));

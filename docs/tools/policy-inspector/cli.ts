import { type Hex, decodePolicy } from "@callcium/sdk";
import type { Abi } from "viem";
import { explainPolicy } from "./index";

const args = process.argv.slice(2);

if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
  console.log("Usage: bun run tools/policy-inspector/cli.ts <policy-hex> [abi.json]");
  console.log();
  console.log("  policy-hex  Hex-encoded policy blob (with or without 0x prefix)");
  console.log("  abi.json    Path to a JSON ABI file (optional)");
  process.exit(args.length === 0 ? 1 : 0);
}

const hex = args[0].startsWith("0x") ? args[0] : `0x${args[0]}`;

let abi: Abi | undefined;
if (args[1]) {
  const file = Bun.file(args[1]);
  if (!(await file.exists())) {
    console.error(`Error: ABI file not found: ${args[1]}`);
    process.exit(1);
  }
  abi = await file.json();
}

try {
  const decoded = decodePolicy(hex as Hex);
  const explained = explainPolicy(decoded, abi ? { abi } : undefined);
  console.log(JSON.stringify(explained, null, 2));
} catch (e) {
  console.error(`Error: ${e instanceof Error ? e.message : String(e)}`);
  process.exit(1);
}

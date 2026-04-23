import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

///////////////////////////////////////////////////////////////////////////
// Types
///////////////////////////////////////////////////////////////////////////

/**
 * Source-line mapping for every public-ish symbol in a Solidity file.
 * Values are FIFO queues of 1-indexed line numbers in source order —
 * overload resolution consumes them left-to-right as forge-doc headings are walked.
 */
export interface SymbolMap {
  contract?: number;
  fn: Record<string, number[]>;
  struct: Record<string, number[]>;
  err: Record<string, number[]>;
  event: Record<string, number[]>;
  modifier: Record<string, number[]>;
  constant: Record<string, number[]>;
}

interface AstNode {
  nodeType: string;
  name?: string;
  kind?: string;
  visibility?: string;
  constant?: boolean;
  abstract?: boolean;
  src?: string;
  nodes?: AstNode[];
}

function emptyMap(): SymbolMap {
  return { fn: {}, struct: {}, err: {}, event: {}, modifier: {}, constant: {} };
}

///////////////////////////////////////////////////////////////////////////
// Public API
///////////////////////////////////////////////////////////////////////////

/**
 * Build a symbol→source-line map for one Solidity file by reading the compact AST
 * emitted by `forge build` (requires `ast = true` in foundry.toml).
 * Returns an empty map if no AST artifact is available — downstream injects nothing.
 */
export async function buildSymbolMap(contractsRoot: string, contractDir: string): Promise<SymbolMap> {
  const sourcePath = join(contractsRoot, "src", contractDir);
  const artifactDir = join(contractsRoot, "out", contractDir);

  let sourceBuffer: Buffer;
  try {
    sourceBuffer = await readFile(sourcePath);
  } catch {
    console.warn(`sol-symbol-map: source not found: ${sourcePath}`);
    return emptyMap();
  }

  const ast = await loadAst(artifactDir);
  if (!ast) {
    console.warn(`sol-symbol-map: no AST artifact under ${artifactDir}`);
    return emptyMap();
  }

  const primaryFileIndex = Number.parseInt(ast.src?.split(":")[2] ?? "", 10);
  if (!Number.isFinite(primaryFileIndex)) return emptyMap();

  const lineStarts = buildLineStartOffsets(sourceBuffer);
  const isAbstractSource = (ast.nodes ?? []).some((n) => n.nodeType === "ContractDefinition" && n.abstract === true);

  const map = emptyMap();
  let earliestTopLevel: number | undefined;

  for (const node of ast.nodes ?? []) {
    const line = nodeLine(node, lineStarts, primaryFileIndex);
    if (line === null) continue;
    if (node.nodeType !== "PragmaDirective" && node.nodeType !== "ImportDirective") {
      earliestTopLevel = earliestTopLevel === undefined ? line : Math.min(earliestTopLevel, line);
    }
    classify(node, line, map, lineStarts, primaryFileIndex, isAbstractSource);
  }

  // Fall back to the first non-directive top-level line when the file has no contract definition.
  if (map.contract === undefined) map.contract = earliestTopLevel;

  return map;
}

///////////////////////////////////////////////////////////////////////////
// AST loading
///////////////////////////////////////////////////////////////////////////

async function loadAst(artifactDir: string): Promise<AstNode | null> {
  let entries: string[];
  try {
    entries = (await readdir(artifactDir)).filter((f) => f.endsWith(".json"));
  } catch {
    return null;
  }
  for (const entry of entries) {
    try {
      const raw = await readFile(join(artifactDir, entry), "utf-8");
      const artifact = JSON.parse(raw) as { ast?: AstNode };
      if (artifact.ast) return artifact.ast;
    } catch {
      // Skip malformed artifacts.
    }
  }
  return null;
}

///////////////////////////////////////////////////////////////////////////
// Classification
///////////////////////////////////////////////////////////////////////////

function classify(
  node: AstNode,
  line: number,
  map: SymbolMap,
  lineStarts: number[],
  primaryFileIndex: number,
  isAbstractSource: boolean,
): void {
  switch (node.nodeType) {
    case "ContractDefinition":
      if (node.name && (map.contract === undefined || line < map.contract)) map.contract = line;
      for (const child of node.nodes ?? []) {
        const childLine = nodeLine(child, lineStarts, primaryFileIndex);
        if (childLine !== null) classify(child, childLine, map, lineStarts, primaryFileIndex, isAbstractSource);
      }
      return;
    case "FunctionDefinition": {
      const name = node.kind === "constructor" ? "constructor" : node.name;
      // Mirror removePrivateFunctions: skip `_`-prefixed names for non-abstract sources.
      if (!name || (!isAbstractSource && name.startsWith("_"))) return;
      (map.fn[name] ??= []).push(line);
      return;
    }
    case "StructDefinition":
      if (node.name) (map.struct[node.name] ??= []).push(line);
      return;
    case "ErrorDefinition":
      if (node.name) (map.err[node.name] ??= []).push(line);
      return;
    case "EventDefinition":
      if (node.name) (map.event[node.name] ??= []).push(line);
      return;
    case "ModifierDefinition":
      if (node.name) (map.modifier[node.name] ??= []).push(line);
      return;
    case "VariableDeclaration":
      // Mirror removePrivateConstants: only keep non-private constants.
      if (node.constant === true && node.visibility !== "private" && node.name) {
        (map.constant[node.name] ??= []).push(line);
      }
      return;
  }
}

///////////////////////////////////////////////////////////////////////////
// Offset → line
///////////////////////////////////////////////////////////////////////////

function buildLineStartOffsets(buffer: Buffer): number[] {
  const offsets: number[] = [0];
  for (let i = 0; i < buffer.length; i++) {
    if (buffer[i] === 0x0a) offsets.push(i + 1);
  }
  return offsets;
}

function nodeLine(node: AstNode, lineStarts: number[], primaryFileIndex: number): number | null {
  const parts = node.src?.split(":");
  if (!parts || parts.length !== 3) return null;
  const offset = Number.parseInt(parts[0], 10);
  const fileIndex = Number.parseInt(parts[2], 10);
  // Skip nodes sourced from imports or other compilation units.
  if (!Number.isFinite(offset) || fileIndex !== primaryFileIndex) return null;

  let lo = 0;
  let hi = lineStarts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >>> 1;
    if (lineStarts[mid] <= offset) lo = mid;
    else hi = mid - 1;
  }
  return lo + 1;
}

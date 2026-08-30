import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkStringify from "remark-stringify";
import { unified } from "unified";
import type { Heading, Paragraph, PhrasingContent, Root, RootContent } from "mdast";
import { buildSymbolMap, type SymbolMap } from "./sol-symbol-map";

///////////////////////////////////////////////////////////////////////////
// Configuration
///////////////////////////////////////////////////////////////////////////

const CONTRACTS_ROOT = join(import.meta.dirname, "../../contracts");
const FORGE_DOC_ROOT = join(CONTRACTS_ROOT, ".forge-doc/src/src");
const OUTPUT_ROOT = join(import.meta.dirname, "../content/docs/solidity/reference");
const GITHUB_BLOB_BASE = "https://github.com/provencraft/callcium/blob/main/packages/contracts/src";

/** Contracts to include, in sidebar order. */
const INCLUDED_CONTRACTS = [
  "PolicyBuilder.sol",
  "Constraint.sol",
  "PolicyEnforcer.sol",
  "PolicyManager.sol",
  "PolicyValidator.sol",
  "Path.sol",
] as const;

/** Structs that are internal implementation details — skip from output. */
const INTERNAL_STRUCTS: Record<string, string[]> = {
  "PolicyManager.sol": ["PolicyManagerStorage"],
  "PolicyEnforcer.sol": ["EvalState", "RuleView", "QParams", "QLoopState"],
  "PolicyValidator.sol": ["BoundDomain", "BitmaskDomain", "SetDomain", "ConstraintContext", "ValidationState"],
};

/**
 * Assembly order per contract.
 * Each entry is a list of forge doc filenames in the order they should appear.
 * Use "*" as a glob for all matching files of that prefix.
 */
const ASSEMBLY_ORDER: Record<string, string[]> = {
  "Constraint.sol": ["struct.Constraint.md", "function.*.md", "library.Operator.md"],
};

/** Page titles (used for frontmatter). Extracted from main file if not specified. */
const PAGE_TITLES: Record<string, string> = {
  "Constraint.sol": "Constraint",
};

///////////////////////////////////////////////////////////////////////////
// Remark processor
///////////////////////////////////////////////////////////////////////////

const processor = unified().use(remarkParse).use(remarkGfm).use(remarkStringify, {
  bullet: "-",
  fences: true,
  listItemIndent: "one",
  resourceLink: true,
});

///////////////////////////////////////////////////////////////////////////
// AST helpers
///////////////////////////////////////////////////////////////////////////

/** Extract plain text from a heading node's children. */
function headingText(heading: Heading): string {
  return heading.children
    .map((c: PhrasingContent) => {
      if (c.type === "text") return c.value;
      if (c.type === "inlineCode") return c.value;
      return "";
    })
    .join("");
}

/** Check if a paragraph is a [Git Source](...) link. */
function isGitSourceParagraph(node: RootContent): boolean {
  if (node.type !== "paragraph") return false;
  return (
    node.children.length === 1 &&
    node.children[0].type === "link" &&
    (node.children[0].children[0] as { value?: string })?.value === "Git Source"
  );
}

/** Check if a paragraph is a **Title:** block. */
function isTitleBlock(node: RootContent): boolean {
  if (node.type !== "paragraph") return false;
  const first = node.children[0];
  if (first?.type !== "strong") return false;
  return first.children.length === 1 && first.children[0].type === "text" && first.children[0].value === "Title:";
}

/**
 * Extract the description paragraph — the first paragraph after the metadata
 * (title heading, Git Source, Title block) that isn't a section heading.
 */
function extractDescription(tree: Root): string {
  let pastMetadata = false;
  for (const node of tree.children) {
    if (node.type === "heading" && node.depth === 1) {
      pastMetadata = true;
      continue;
    }
    if (!pastMetadata) continue;
    if (isGitSourceParagraph(node) || isTitleBlock(node)) continue;
    if (node.type === "heading") return "";
    if (node.type === "paragraph") {
      // Serialize this paragraph's text content.
      return node.children
        .map((c: PhrasingContent) => {
          if (c.type === "text") return c.value;
          if (c.type === "inlineCode") return `\`${c.value}\``;
          if (c.type === "strong") {
            const text = c.children.map((sc: PhrasingContent) => (sc.type === "text" ? sc.value : "")).join("");
            return `**${text}**`;
          }
          return "";
        })
        .join("");
    }
  }
  return "";
}

/** Extract the title from the # heading. */
function extractTitle(tree: Root): string {
  for (const node of tree.children) {
    if (node.type === "heading" && node.depth === 1) {
      const raw = headingText(node);
      // "function arg" → "arg"
      if (raw.startsWith("function ")) return raw.slice("function ".length);
      return raw;
    }
  }
  return "Untitled";
}

///////////////////////////////////////////////////////////////////////////
// Section filtering
///////////////////////////////////////////////////////////////////////////

/**
 * Remove metadata nodes from the top of the AST:
 * - The # title heading
 * - The [Git Source](...) paragraph
 * - The **Title:** paragraph
 * - The description paragraph (first paragraph after metadata)
 */
function stripMetadata(tree: Root, description: string): void {
  let descriptionStripped = !description;
  let pastTitle = false;
  tree.children = tree.children.filter((node) => {
    if (node.type === "heading" && node.depth === 1) {
      pastTitle = true;
      return false;
    }
    if (isGitSourceParagraph(node)) return false;
    if (isTitleBlock(node)) return false;
    // Strip the first paragraph after metadata — it's the description we extracted.
    if (!descriptionStripped && pastTitle && node.type === "paragraph") {
      descriptionStripped = true;
      return false;
    }
    return true;
  });
}

/**
 * Remove every depth-3 section the predicate accepts, from its heading up to the
 * next heading of depth ≤ 3. The predicate sees the heading text and the section body.
 */
function removeSections(tree: Root, matches: (heading: string, body: RootContent[]) => boolean): void {
  const children = tree.children;
  let i = 0;
  while (i < children.length) {
    const node = children[i];
    if (node.type === "heading" && node.depth === 3) {
      let end = i + 1;
      while (end < children.length) {
        const next = children[end];
        if (next.type === "heading" && next.depth <= 3) break;
        end++;
      }
      if (matches(headingText(node), children.slice(i + 1, end))) {
        children.splice(i, end - i);
        continue;
      }
    }
    i++;
  }
}

/** Remove each named depth-2 heading whose section body is empty. */
function removeEmptySections(tree: Root, titles: string[]): void {
  const children = tree.children;
  let i = 0;
  while (i < children.length) {
    const node = children[i];
    if (node.type === "heading" && node.depth === 2 && titles.includes(headingText(node))) {
      const next = children[i + 1];
      if (!next || (next.type === "heading" && next.depth <= 2)) {
        children.splice(i, 1);
        continue;
      }
    }
    i++;
  }
}

///////////////////////////////////////////////////////////////////////////
// Source-link injection
///////////////////////////////////////////////////////////////////////////

type SymbolBucket = "function_" | "struct" | "error" | "event" | "modifier" | "constant";

const SECTION_TO_BUCKET: Record<string, SymbolBucket> = {
  Functions: "function_",
  Structs: "struct",
  Errors: "error",
  Events: "event",
  Modifiers: "modifier",
  "State Variables": "constant",
};

function gitSourceParagraph(contractDir: string, line: number): Paragraph {
  return {
    type: "paragraph",
    children: [
      {
        type: "link",
        url: `${GITHUB_BLOB_BASE}/${contractDir}#L${line}`,
        children: [{ type: "text", value: "Git Source" }],
      },
    ],
  };
}

/**
 * Walk a file's tree and insert `[Git Source]` paragraphs under each symbol heading,
 * consuming one line from the matching SymbolMap queue per heading. Handles the
 * bare-code-block case (e.g. `struct.Foo.md`) by prepending the link before the code.
 */
function injectSourceLinks(filename: string, tree: Root, contractDir: string, symbolMap: SymbolMap): void {
  const auxMatch = filename.match(/^(function|struct)\.(.+)\.md$/);
  const fallbackBucket: SymbolBucket | null = auxMatch ? (auxMatch[1] === "function" ? "function_" : "struct") : null;
  let currentBucket: SymbolBucket | null = fallbackBucket;

  const result: RootContent[] = [];
  const children = tree.children;
  let i = 0;

  if (auxMatch && children.length > 0 && children[0].type === "code") {
    const line = (symbolMap[fallbackBucket!][auxMatch[2]] ?? []).shift();
    if (line !== undefined) result.push(gitSourceParagraph(contractDir, line));
  }

  while (i < children.length) {
    const node = children[i];

    if (node.type === "heading") {
      if (node.depth === 2) {
        currentBucket = SECTION_TO_BUCKET[headingText(node)] ?? null;
      } else if (node.depth === 3) {
        const bucket = currentBucket ?? fallbackBucket;
        if (bucket) {
          const name = headingText(node)
            .replace(/\(.*\)$/, "")
            .trim();
          const line = (symbolMap[bucket][name] ?? []).shift();
          if (line !== undefined) {
            result.push(node);
            i++;
            // Land the link directly above the code block, after any description paragraphs.
            while (i < children.length && children[i].type === "paragraph") {
              result.push(children[i]);
              i++;
            }
            result.push(gitSourceParagraph(contractDir, line));
            continue;
          }
        }
      }
    }

    result.push(node);
    i++;
  }

  tree.children = result;
}

function warnUnconsumed(contractDir: string, symbolMap: SymbolMap): void {
  for (const [kind, bucket] of Object.entries(symbolMap)) {
    if (kind === "contract") continue;
    for (const [name, lines] of Object.entries(bucket as Record<string, number[]>)) {
      if (lines.length > 0) {
        console.warn(`sync-reference: ${contractDir} ${kind}:${name} — unconsumed lines [${lines.join(", ")}]`);
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////
// MDX escaping
///////////////////////////////////////////////////////////////////////////

/**
 * Re-indent Solidity struct/error/enum bodies inside code blocks.
 * forge doc strips indentation in separate struct files; we restore 4-space indent
 * for lines between the opening `{` and closing `}`.
 */
function reindentStructBodies(md: string): string {
  let inCodeBlock = false;
  // Only ever set inside a code block, and cleared when one closes.
  let inBody = false;
  const result: string[] = [];

  for (const line of md.split("\n")) {
    if (line.startsWith("```")) {
      inCodeBlock = !inCodeBlock;
      inBody = inBody && inCodeBlock;
    } else if (inCodeBlock && /^(struct|error|enum)\s+\w+.*\{/.test(line)) {
      inBody = true;
    } else if (inBody && line.startsWith("}")) {
      inBody = false;
    } else if (inBody && line.trim() && !line.startsWith("    ")) {
      result.push(`    ${line}`);
      continue;
    }
    result.push(line);
  }

  return result.join("\n");
}

/**
 * Drop remark-stringify's backslash escaping of characters that are safe here
 * (`POLICY\_STORE\_SLOT` → `POLICY_STORE_SLOT`), then escape bare `<` so MDX
 * doesn't read it as JSX. Fenced blocks and inline code spans keep their `<`.
 */
function normalizeProse(md: string): string {
  let inCodeBlock = false;
  const result: string[] = [];

  for (const line of md.split("\n")) {
    if (line.startsWith("```")) {
      inCodeBlock = !inCodeBlock;
      result.push(line);
      continue;
    }
    result.push(
      inCodeBlock
        ? line
        : line
            .replace(/\\([_~])/g, "$1")
            .split(/(`[^`]+`)/)
            .map((part, i) => (i % 2 === 1 ? part : part.replace(/</g, "&lt;")))
            .join(""),
    );
  }

  return result.join("\n");
}

/** Serialized markdown to a page body: struct bodies re-indented, prose normalized, blank runs collapsed. */
function normalizeBody(md: string): string {
  return normalizeProse(reindentStructBodies(md))
    .replace(/^\n+/, "")
    .replace(/\n{3,}/g, "\n\n");
}

///////////////////////////////////////////////////////////////////////////
// File processing
///////////////////////////////////////////////////////////////////////////

interface ProcessedFile {
  filename: string;
  title: string;
  description: string;
  tree: Root;
}

/** Read and parse a forge doc markdown file. */
async function readForgeDoc(dir: string, filename: string): Promise<ProcessedFile> {
  const content = await readFile(join(dir, filename), "utf-8");
  const tree = processor.parse(content);
  const title = extractTitle(tree);
  const description = extractDescription(tree);
  return { filename, title, description, tree };
}

/** Process a "main" file (library.* or abstract.*). */
function processMainFile(file: ProcessedFile, contractDir: string): void {
  stripMetadata(file.tree, file.description);
  // Abstract contracts expose protected internal methods as their API — don't filter.
  const hidesPrivateFunctions = !file.filename.startsWith("abstract.");
  const internalStructs = new Set(INTERNAL_STRUCTS[contractDir] ?? []);
  removeSections(
    file.tree,
    (heading, body) =>
      (hidesPrivateFunctions && heading.startsWith("_")) ||
      internalStructs.has(heading) ||
      body.some((node) => node.type === "code" && node.value.includes("private constant")),
  );
  removeEmptySections(file.tree, ["State Variables", "Structs"]);
}

/** Process an auxiliary file (struct.*, function.*). Strip metadata, keep body. */
function processAuxFile(file: ProcessedFile): void {
  stripMetadata(file.tree, file.description);
}

///////////////////////////////////////////////////////////////////////////
// Contract slug
///////////////////////////////////////////////////////////////////////////

function contractSlug(contractDir: string): string {
  return contractDir
    .replace(/\.sol$/, "")
    .replace(/([a-z])([A-Z])/g, "$1-$2")
    .toLowerCase();
}

///////////////////////////////////////////////////////////////////////////
// Assembly
///////////////////////////////////////////////////////////////////////////

/**
 * Determine the ordered list of files for a contract.
 * Uses ASSEMBLY_ORDER if defined, otherwise: main file first, then structs, then functions.
 */
function assembleOrder(files: string[], contractDir: string): string[] {
  const order = ASSEMBLY_ORDER[contractDir];
  if (order) {
    const result: string[] = [];
    for (const pattern of order) {
      if (pattern.includes("*")) {
        const prefix = pattern.split("*")[0];
        const matching = files.filter((f) => f.startsWith(prefix)).toSorted();
        result.push(...matching);
      } else {
        if (files.includes(pattern)) result.push(pattern);
      }
    }
    return result;
  }

  // Default: main file first, then structs, then functions.
  const mainFile = files.find((f) => f.startsWith("library.") || f.startsWith("abstract."));
  const structs = files.filter((f) => f.startsWith("struct.")).toSorted();
  const functions = files.filter((f) => f.startsWith("function.")).toSorted();
  const result: string[] = [];
  if (mainFile) result.push(mainFile);
  result.push(...structs, ...functions);
  return result;
}

/** Check if a file represents an internal struct that should be skipped. */
function isInternalStructFile(filename: string, contractDir: string): boolean {
  if (!filename.startsWith("struct.")) return false;
  const internalNames = INTERNAL_STRUCTS[contractDir] ?? [];
  const structName = filename.replace(/^struct\./, "").replace(/\.md$/, "");
  return internalNames.includes(structName);
}

/** Check if a file is a "main" file (library or abstract). */
function isMainFile(filename: string): boolean {
  return filename.startsWith("library.") || filename.startsWith("abstract.");
}

///////////////////////////////////////////////////////////////////////////
// Page rendering
///////////////////////////////////////////////////////////////////////////

/** A contract's forge doc output to a rendered MDX page, or null when forge doc produced no directory for it. */
async function renderContractPage(contractDir: string): Promise<string | null> {
  const srcDir = join(FORGE_DOC_ROOT, contractDir);

  let allFiles: string[];
  try {
    allFiles = (await readdir(srcDir)).filter((f) => f.endsWith(".md"));
  } catch {
    console.warn(`Warning: ${srcDir} not found, skipping ${contractDir}`);
    return null;
  }

  const files = allFiles.filter((f) => !isInternalStructFile(f, contractDir));
  const ordered = assembleOrder(files, contractDir);

  // Load source-line map from the solc AST artifact; drop internal structs
  // so they don't linger as unused queue entries after assembly.
  const symbolMap = await buildSymbolMap(CONTRACTS_ROOT, contractDir);
  for (const name of INTERNAL_STRUCTS[contractDir] ?? []) delete symbolMap.struct[name];

  const parsed: ProcessedFile[] = [];
  for (const filename of ordered) {
    parsed.push(await readForgeDoc(srcDir, filename));
  }

  // Strip metadata, filter sections, inject source links.
  for (const file of parsed) {
    if (isMainFile(file.filename)) {
      processMainFile(file, contractDir);
    } else {
      processAuxFile(file);
    }
    injectSourceLinks(file.filename, file.tree, contractDir, symbolMap);
  }

  warnUnconsumed(contractDir, symbolMap);

  // Assemble the final AST by concatenating all processed trees. The contract-level
  // Git Source link sits at the top so it renders directly under the frontmatter
  // description, matching the SDK layout.
  const assembledChildren: RootContent[] = [];
  if (symbolMap.contract !== undefined) {
    assembledChildren.push(gitSourceParagraph(contractDir, symbolMap.contract));
  }
  for (const file of parsed) {
    assembledChildren.push(...file.tree.children);
  }
  const assembledTree: Root = { type: "root", children: assembledChildren };

  // Title and description come from the main file, falling back to the first file.
  const mainFile = parsed.find((file) => isMainFile(file.filename)) ?? parsed[0];
  const title = PAGE_TITLES[contractDir] ?? mainFile.title;
  const description = mainFile.description;

  const frontmatter = [
    "---",
    `title: "${title}"`,
    description ? `description: "${description.replace(/"/g, '\\"')}"` : null,
    "---",
  ]
    .filter(Boolean)
    .join("\n");

  return `${frontmatter}\n\n${normalizeBody(processor.stringify(assembledTree))}`;
}

///////////////////////////////////////////////////////////////////////////
// Main
///////////////////////////////////////////////////////////////////////////

async function main() {
  await rm(OUTPUT_ROOT, { recursive: true, force: true });
  await mkdir(OUTPUT_ROOT, { recursive: true });

  let totalPages = 0;

  for (const contractDir of INCLUDED_CONTRACTS) {
    const mdx = await renderContractPage(contractDir);
    if (mdx === null) continue;
    await writeFile(join(OUTPUT_ROOT, `${contractSlug(contractDir)}.mdx`), mdx);
    totalPages++;
  }

  const meta = {
    title: "API",
    pages: INCLUDED_CONTRACTS.map(contractSlug),
  };
  await writeFile(join(OUTPUT_ROOT, "meta.json"), `${JSON.stringify(meta, null, 2)}\n`);

  console.log(`Generated ${totalPages} reference pages.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

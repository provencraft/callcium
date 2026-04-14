import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkStringify from "remark-stringify";
import { unified } from "unified";
import type { Heading, PhrasingContent, Root, RootContent } from "mdast";

///////////////////////////////////////////////////////////////////////////
// Configuration
///////////////////////////////////////////////////////////////////////////

const FORGE_DOC_DIR = join(import.meta.dirname, "../../contracts/.forge-doc");
const FORGE_DOC_ROOT = join(FORGE_DOC_DIR, "src/src");
const OUTPUT_ROOT = join(import.meta.dirname, "../content/docs/reference");

/** Contracts to include, in sidebar order. */
const INCLUDED_CONTRACTS = [
  "PolicyBuilder.sol",
  "Constraint.sol",
  "PolicyEnforcer.sol",
  "PolicyManager.sol",
  "PolicyValidator.sol",
  "Path.sol",
];

/** Structs that are internal implementation details — skip from output. */
const INTERNAL_STRUCTS: Record<string, string[]> = {
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

const processor = unified().use(remarkParse).use(remarkGfm);
const serializer = unified().use(remarkParse).use(remarkGfm).use(remarkStringify, {
  bullet: "-",
  fences: true,
  listItemIndent: "one",
  resourceLink: true,
});

function parse(md: string): Root {
  return processor.parse(md);
}

function stringify(tree: Root): string {
  return serializer.stringify(tree);
}

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
    if (
      !descriptionStripped &&
      pastTitle &&
      node.type === "paragraph" &&
      !isGitSourceParagraph(node) &&
      !isTitleBlock(node)
    ) {
      descriptionStripped = true;
      return false;
    }
    return true;
  });
}

/**
 * Remove private function sections (### _functionName) from the AST.
 * Removes the heading and all content until the next heading of depth ≤ 3.
 */
function removePrivateFunctions(tree: Root): void {
  const children = tree.children;
  let i = 0;
  while (i < children.length) {
    const node = children[i];
    if (node.type === "heading" && node.depth === 3) {
      const text = headingText(node);
      if (text.startsWith("_")) {
        // Find end of section.
        let end = i + 1;
        while (end < children.length) {
          const next = children[end];
          if (next.type === "heading" && next.depth <= 3) break;
          end++;
        }
        children.splice(i, end - i);
        continue;
      }
    }
    i++;
  }
}

/**
 * Remove private constant sections from the AST.
 * These appear as ### ConstantName within ## State Variables,
 * with a code block containing "private constant".
 * If all constants are removed, the ## State Variables heading is also removed.
 */
function removePrivateConstants(tree: Root): void {
  const children = tree.children;
  let i = 0;
  while (i < children.length) {
    const node = children[i];
    if (node.type === "heading" && node.depth === 3) {
      // Find end of section.
      let end = i + 1;
      while (end < children.length) {
        const next = children[end];
        if (next.type === "heading" && next.depth <= 3) break;
        end++;
      }
      // Check if any code block in this section contains "private constant".
      const isPrivate = children
        .slice(i, end)
        .some((n) => n.type === "code" && (n as { value: string }).value.includes("private constant"));
      if (isPrivate) {
        children.splice(i, end - i);
        continue;
      }
    }
    i++;
  }

  // If ## State Variables section is now empty, remove it.
  i = 0;
  while (i < children.length) {
    const node = children[i];
    if (node.type === "heading" && node.depth === 2 && headingText(node) === "State Variables") {
      const next = children[i + 1];
      if (!next || (next.type === "heading" && next.depth <= 2)) {
        children.splice(i, 1);
        continue;
      }
    }
    i++;
  }
}

/**
 * Remove internal struct sections from the AST.
 * These appear as ### StructName within ## Structs.
 * If all structs in a ## Structs section are internal, remove the entire section.
 */
function removeInternalStructs(tree: Root, internalNames: string[]): void {
  if (internalNames.length === 0) return;
  const nameSet = new Set(internalNames);
  const children = tree.children;

  // First pass: remove individual ### StructName sections.
  let i = 0;
  while (i < children.length) {
    const node = children[i];
    if (node.type === "heading" && node.depth === 3) {
      const text = headingText(node);
      if (nameSet.has(text)) {
        let end = i + 1;
        while (end < children.length) {
          const next = children[end];
          if (next.type === "heading" && next.depth <= 3) break;
          end++;
        }
        children.splice(i, end - i);
        continue;
      }
    }
    i++;
  }

  // Second pass: if ## Structs section is now empty, remove it.
  i = 0;
  while (i < children.length) {
    const node = children[i];
    if (node.type === "heading" && node.depth === 2 && headingText(node) === "Structs") {
      // Check if next node is another ## heading (or EOF) — meaning section is empty.
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
// MDX escaping
///////////////////////////////////////////////////////////////////////////

/**
 * Re-indent Solidity struct/error/enum bodies inside code blocks.
 * forge doc strips indentation in separate struct files; we restore 4-space indent
 * for lines between the opening `{` and closing `}`.
 */
function reindentStructBodies(md: string): string {
  const lines = md.split("\n");
  let inCodeBlock = false;
  let inBody = false;
  const result: string[] = [];

  for (const line of lines) {
    if (line.startsWith("```")) {
      inCodeBlock = !inCodeBlock;
      if (!inCodeBlock) inBody = false;
      result.push(line);
      continue;
    }

    if (!inCodeBlock) {
      result.push(line);
      continue;
    }

    // Detect struct/error/enum opening line.
    if (/^(struct|error|enum)\s+\w+.*\{/.test(line)) {
      inBody = true;
      result.push(line);
      continue;
    }

    // Detect closing brace.
    if (inBody && line.startsWith("}")) {
      inBody = false;
      result.push(line);
      continue;
    }

    // Indent body lines that aren't already indented.
    if (inBody && line.trim() && !line.startsWith("    ")) {
      result.push(`    ${line}`);
      continue;
    }

    result.push(line);
  }

  return result.join("\n");
}

/**
 * Undo remark-stringify's backslash escaping of characters that are safe in our context.
 * E.g., `POLICY\_STORE\_SLOT` → `POLICY_STORE_SLOT`, `\~bytes32` → `~bytes32`.
 * Only applies outside code blocks (code blocks are not escaped by remark-stringify).
 */
function unescapeRemarkArtifacts(md: string): string {
  const lines = md.split("\n");
  let inCodeBlock = false;
  const result: string[] = [];

  for (const line of lines) {
    if (line.startsWith("```")) {
      inCodeBlock = !inCodeBlock;
      result.push(line);
      continue;
    }
    if (inCodeBlock) {
      result.push(line);
      continue;
    }
    // Remove backslash escapes for underscores and tildes outside code blocks.
    result.push(line.replace(/\\([_~])/g, "$1"));
  }

  return result.join("\n");
}

/**
 * Escape bare `<` in prose so MDX doesn't interpret them as JSX.
 * Preserves code blocks (``` ... ```) and inline code (` ... `).
 */
function escapeForMdx(md: string): string {
  const lines = md.split("\n");
  let inCodeBlock = false;
  const result: string[] = [];

  for (const line of lines) {
    if (line.startsWith("```")) {
      inCodeBlock = !inCodeBlock;
      result.push(line);
      continue;
    }
    if (inCodeBlock) {
      result.push(line);
      continue;
    }
    // Split by inline code spans and only escape outside them.
    const parts = line.split(/(`[^`]+`)/);
    const escaped = parts
      .map((part, i) => {
        if (i % 2 === 1) return part;
        return part.replace(/</g, "&lt;");
      })
      .join("");
    result.push(escaped);
  }

  return result.join("\n");
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
  const tree = parse(content);
  const title = extractTitle(tree);
  const description = extractDescription(tree);
  return { filename, title, description, tree };
}

/** Process a "main" file (library.* or abstract.*). */
function processMainFile(file: ProcessedFile, contractDir: string): void {
  stripMetadata(file.tree, file.description);
  // Abstract contracts expose protected internal methods as their API — don't filter.
  if (!file.filename.startsWith("abstract.")) {
    removePrivateFunctions(file.tree);
  }
  removePrivateConstants(file.tree);
  const internalStructs = INTERNAL_STRUCTS[contractDir] ?? [];
  removeInternalStructs(file.tree, internalStructs);
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
// Main
///////////////////////////////////////////////////////////////////////////

async function main() {
  await rm(OUTPUT_ROOT, { recursive: true, force: true });
  await mkdir(OUTPUT_ROOT, { recursive: true });

  let totalPages = 0;

  for (const contractDir of INCLUDED_CONTRACTS) {
    const srcDir = join(FORGE_DOC_ROOT, contractDir);
    const slug = contractSlug(contractDir);

    let allFiles: string[];
    try {
      allFiles = (await readdir(srcDir)).filter((f) => f.endsWith(".md"));
    } catch {
      console.warn(`Warning: ${srcDir} not found, skipping ${contractDir}`);
      continue;
    }

    // Filter out internal struct files.
    const files = allFiles.filter((f) => !isInternalStructFile(f, contractDir));

    // Determine assembly order.
    const ordered = assembleOrder(files, contractDir);

    // Read and parse all files.
    const parsed = new Map<string, ProcessedFile>();
    for (const filename of ordered) {
      parsed.set(filename, await readForgeDoc(srcDir, filename));
    }

    // Process files.
    for (const [filename, file] of parsed) {
      if (isMainFile(filename)) {
        processMainFile(file, contractDir);
      } else {
        processAuxFile(file);
      }
    }

    // Determine title and description.
    // Use the first main file, or the custom title, or the first file.
    const mainFilename = ordered.find(isMainFile);
    // oxlint-disable-next-line typescript/no-non-null-assertion -- ordered is non-empty and all entries are keys in parsed.
    const firstFile = parsed.get(ordered[0])!;
    // oxlint-disable-next-line typescript/no-non-null-assertion -- mainFilename is a key in parsed by construction.
    const mainFile = mainFilename ? parsed.get(mainFilename)! : firstFile;

    const pageTitle = PAGE_TITLES[contractDir] ?? mainFile.title;
    const pageDescription = mainFile.description;

    // Assemble the final AST by concatenating all processed trees.
    const assembledChildren: RootContent[] = [];
    for (const filename of ordered) {
      // oxlint-disable-next-line typescript/no-non-null-assertion -- filename is a key in parsed by construction.
      const file = parsed.get(filename)!;
      assembledChildren.push(...file.tree.children);
    }

    const assembledTree: Root = { type: "root", children: assembledChildren };

    // Serialize.
    let body = stringify(assembledTree);

    // Re-indent struct bodies that forge doc output without indentation.
    body = reindentStructBodies(body);

    // Undo remark-stringify's backslash escaping of underscores and tildes.
    body = unescapeRemarkArtifacts(body);

    // Escape for MDX.
    body = escapeForMdx(body);

    // Clean up leading/trailing whitespace.
    body = body.replace(/^\n+/, "").replace(/\n{3,}/g, "\n\n");

    // Build frontmatter.
    const frontmatter = [
      "---",
      `title: "${pageTitle}"`,
      pageDescription ? `description: "${pageDescription.replace(/"/g, '\\"')}"` : null,
      "---",
    ]
      .filter(Boolean)
      .join("\n");

    const mdx = `${frontmatter}\n\n${body}`;

    await writeFile(join(OUTPUT_ROOT, `${slug}.mdx`), mdx);
    totalPages++;
  }

  // Write meta.json.
  const meta = {
    title: "Reference",
    pages: INCLUDED_CONTRACTS.map(contractSlug),
  };
  await writeFile(join(OUTPUT_ROOT, "meta.json"), `${JSON.stringify(meta, null, 2)}\n`);

  console.log(`Generated ${totalPages} reference pages.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

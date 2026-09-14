import { toString } from "mdast-util-to-string";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkStringify from "remark-stringify";
import { unified } from "unified";
import { visit } from "unist-util-visit";
import type { Paragraph, Root, RootContent } from "mdast";
import { buildSymbolMap, type SymbolMap } from "./sol-symbol-map";

///////////////////////////////////////////////////////////////////////////
// Configuration
///////////////////////////////////////////////////////////////////////////

const CONTRACTS_ROOT = join(import.meta.dirname, "../../contracts");
const FORGE_DOC_ROOT = join(CONTRACTS_ROOT, ".forge-doc/src/pages/src");
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
  "PolicyBuilder.sol": ["PolicyDraft"],
  "PolicyManager.sol": ["PolicyManagerStorage"],
  "PolicyEnforcer.sol": ["EvalState", "RuleView", "QParams", "QLoopState"],
  "PolicyValidator.sol": ["BoundDomain", "BitmaskDomain", "SetDomain", "ConstraintContext", "ValidationState"],
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

///////////////////////////////////////////////////////////////////////////
// Section filtering
///////////////////////////////////////////////////////////////////////////

/**
 * Remove the `#` title heading, every `[Git Source](...)` and `**Title:**` paragraph, and the
 * description paragraph. The description is the first paragraph after the title; a heading reached
 * first means there is none.
 */
export function takeMetadata(tree: Root): void {
  let pastTitle = false;
  let resolved = false;
  tree.children = tree.children.filter((node) => {
    if (node.type === "heading" && node.depth === 1) {
      pastTitle = true;
      return false;
    }
    if (isGitSourceParagraph(node) || isTitleBlock(node)) return false;
    if (pastTitle && !resolved) {
      if (node.type === "paragraph") {
        resolved = true;
        return false;
      }
      if (node.type === "heading") resolved = true;
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
      if (matches(toString(node), children.slice(i + 1, end))) {
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
    if (node.type === "heading" && node.depth === 2 && titles.includes(toString(node))) {
      const next = children[i + 1];
      if (!next || (next.type === "heading" && next.depth <= 2)) {
        children.splice(i, 1);
        continue;
      }
    }
    i++;
  }
}

/** Heading anchors and the `<i>` wrapper forge doc puts around a dev note. */
const markupNoise = /^(?:<a id="[^"]*"><\/a>|<\/?i>)$/;

/**
 * Drop forge doc's markup scaffolding, which MDX would otherwise render as JSX. Neither `a` nor `i`
 * is a block-level tag, so each arrives wrapped in a paragraph of its own, not as a bare html node.
 */
function stripMarkup(tree: Root): void {
  tree.children = tree.children.filter((node) => {
    if (node.type === "html") return !markupNoise.test(node.value.trim());
    if (node.type !== "paragraph" || !node.children.every((child) => child.type === "html")) return true;
    return !markupNoise.test(
      node.children
        .map((child) => (child.type === "html" ? child.value : ""))
        .join("")
        .trim(),
    );
  });
}

/**
 * Drop a parameter or return table whose description column is empty, along with the label above
 * it. Such a table repeats the declaration beside it and states nothing more.
 */
export function stripEmptyTables(tree: Root): void {
  for (let i = tree.children.length - 1; i >= 0; i--) {
    const node = tree.children[i];
    if (node.type !== "table") continue;
    const described = node.children.slice(1).some((row) => toString(row.children[2] ?? row).trim() !== "");
    if (described) continue;
    const label = tree.children[i - 1];
    const start = label?.type === "paragraph" && label.children[0]?.type === "strong" ? i - 1 : i;
    tree.children.splice(start, i - start + 1);
    i = start;
  }
}

/** Undo the entity escaping forge doc applies inside code, where nothing unescapes it. */
function decodeCodeEntities(tree: Root): void {
  visit(tree, ["inlineCode", "code"], (node) => {
    if (node.type !== "inlineCode" && node.type !== "code") return;
    node.value = node.value.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  });
}

/**
 * Strip the nesting indentation a member's declaration carries into its code block. forge doc
 * dedents the opening line only, leaving every continuation one level in.
 */
export function dedentMemberCode(tree: Root): void {
  for (const node of tree.children) {
    if (node.type !== "code") continue;
    const [opening, ...rest] = node.value.split("\n");
    if (rest.length === 0) continue;
    node.value = [opening, ...rest.map((line) => line.replace(/^ {4}/, ""))].join("\n");
  }
}

/** Render the name column of a parameter or return table as code, matching the type beside it. */
function codifyTableNames(tree: Root): void {
  for (const node of tree.children) {
    if (node.type !== "table") continue;
    for (const row of node.children.slice(1)) {
      const cell = row.children[0];
      if (cell?.children.length === 1 && cell.children[0].type === "text") {
        cell.children = [{ type: "inlineCode", value: cell.children[0].value }];
      }
    }
  }
}

/** The parameter type list of a Solidity declaration, as an overload heading spells it. */
export function signatureTypes(code: string): string {
  const open = code.indexOf("(");
  if (open === -1) return "";
  let depth = 0;
  let close = -1;
  for (let i = open; i < code.length; i++) {
    if (code[i] === "(") depth++;
    else if (code[i] === ")" && --depth === 0) {
      close = i;
      break;
    }
  }
  if (close === -1) return "";
  const params = code.slice(open + 1, close).trim();
  if (params === "") return "";
  return params
    .split(",")
    .map((param) => param.trim().split(/\s+/)[0])
    .join(", ");
}

/**
 * A free-function file carries one declaration per heading. A lone declaration reads from its code
 * block alone, so its heading goes; overloads keep theirs, told apart by parameter types.
 */
function reconcileFreeFunctionHeadings(tree: Root): void {
  const headings = tree.children.filter((node) => node.type === "heading" && node.depth === 3);
  if (headings.length === 0) return;
  if (headings.length === 1) {
    // The heading and the description under it repeat the file's own, which the metadata pass
    // already took, so the code block carries the declaration alone.
    const start = tree.children.indexOf(headings[0]);
    let end = start + 1;
    while (end < tree.children.length && tree.children[end].type === "paragraph") end++;
    tree.children.splice(start, end - start);
    return;
  }

  for (let i = 0; i < tree.children.length; i++) {
    const node = tree.children[i];
    if (node.type !== "heading" || node.depth !== 3) continue;
    const name = toString(node);
    const rest = tree.children.slice(i + 1);
    const stop = rest.findIndex((next) => next.type === "heading");
    const code = rest.slice(0, stop === -1 ? rest.length : stop).find((next) => next.type === "code");
    if (code?.type === "code") node.children = [{ type: "text", value: `${name}(${signatureTypes(code.value)})` }];
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
  Constants: "constant",
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
  const auxMatch = filename.match(/^(function|struct)\.(.+)\.mdx$/);
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
        currentBucket = SECTION_TO_BUCKET[toString(node)] ?? null;
      } else if (node.depth === 3) {
        const bucket = currentBucket ?? fallbackBucket;
        if (bucket) {
          const name = toString(node)
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

/** Serialized markdown to a page body: prose normalized, blank runs collapsed. */
function normalizeBody(md: string): string {
  return normalizeProse(md)
    .replace(/^\n+/, "")
    .replace(/\n{3,}/g, "\n\n");
}

///////////////////////////////////////////////////////////////////////////
// File processing
///////////////////////////////////////////////////////////////////////////

/** A quoted scalar from forge doc's page frontmatter, which carries only `title` and `description`. */
function frontmatterField(frontmatter: string | undefined, field: string): string | undefined {
  return frontmatter?.match(new RegExp(`^${field}: "(.*)"$`, "m"))?.[1];
}

interface ProcessedFile {
  filename: string;
  title: string;
  description: string;
  tree: Root;
}

/**
 * Read a forge doc page and lift its title and description out of the tree, or null when forge doc
 * published no page for the symbol. Its own frontmatter goes; the assembled page carries ours.
 */
async function readForgeDoc(dir: string, filename: string): Promise<ProcessedFile | null> {
  let content: string;
  try {
    content = await readFile(join(dir, filename), "utf-8");
  } catch {
    return null;
  }
  const frontmatter = content.match(/^---\n([\s\S]*?)\n---\n/);
  const tree = processor.parse(content.slice(frontmatter?.[0].length ?? 0));
  const title = frontmatterField(frontmatter?.[1], "title") ?? "Untitled";
  const description = frontmatterField(frontmatter?.[1], "description") ?? "";
  takeMetadata(tree);
  stripMarkup(tree);
  stripEmptyTables(tree);
  codifyTableNames(tree);
  decodeCodeEntities(tree);
  if (filename.startsWith("function.")) reconcileFreeFunctionHeadings(tree);
  return { filename, title, description, tree };
}

/** Filter the sections a "main" file (library.* or abstract.*) does not publish. */
function processMainFile(file: ProcessedFile, internalStructs: ReadonlySet<string>): void {
  // Abstract contracts expose protected internal methods as their API — don't filter.
  const hidesPrivateFunctions = !file.filename.startsWith("abstract.");
  removeSections(
    file.tree,
    (heading, body) =>
      (hidesPrivateFunctions && heading.startsWith("_")) ||
      internalStructs.has(heading) ||
      body.some((node) => node.type === "code" && node.value.includes("private constant")),
  );
  removeEmptySections(file.tree, ["Constants", "Structs"]);
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

/** Page files for a contract, in the order the source declares them. */
function orderedFiles(symbolMap: SymbolMap, internalStructs: ReadonlySet<string>): string[] {
  return symbolMap.topLevel
    .filter((symbol) => !(symbol.kind === "struct" && internalStructs.has(symbol.name)))
    .map((symbol) => `${symbol.kind}.${symbol.name}.mdx`);
}

/** Check if a file is a "main" file (library or abstract). */
function isMainFile(filename: string): boolean {
  return filename.startsWith("library.") || filename.startsWith("abstract.");
}

///////////////////////////////////////////////////////////////////////////
// Page rendering
///////////////////////////////////////////////////////////////////////////

/** A contract's forge doc output to a rendered MDX page, or null when forge doc published none. */
async function renderContractPage(contractDir: string): Promise<string | null> {
  const symbolMap = await buildSymbolMap(CONTRACTS_ROOT, contractDir);

  // Internal structs are excluded from two places: their own page files, and the main file's
  // sections. Dropping them from the symbol map keeps their source lines out of the link queues.
  const internalStructs = new Set(INTERNAL_STRUCTS[contractDir] ?? []);
  for (const name of internalStructs) delete symbolMap.struct[name];

  const parsed: ProcessedFile[] = [];
  for (const filename of orderedFiles(symbolMap, internalStructs)) {
    const file = await readForgeDoc(FORGE_DOC_ROOT, filename);
    if (file) parsed.push(file);
    else console.warn(`sync-reference: ${contractDir} declares ${filename}, which forge doc did not publish`);
  }
  if (parsed.length === 0) {
    console.warn(`Warning: forge doc published no page for ${contractDir}, skipping`);
    return null;
  }

  // Filter sections and inject source links.
  for (const file of parsed) {
    if (isMainFile(file.filename)) {
      processMainFile(file, internalStructs);
      dedentMemberCode(file.tree);
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
  // Every page is rendered before the output is touched, so a run that cannot read forge doc
  // leaves the published pages standing instead of emptying the directory.
  const pages = new Map<string, string>();
  for (const contractDir of INCLUDED_CONTRACTS) {
    const mdx = await renderContractPage(contractDir);
    if (mdx !== null) pages.set(contractSlug(contractDir), mdx);
  }

  if (pages.size < INCLUDED_CONTRACTS.length) {
    const missing = INCLUDED_CONTRACTS.filter((c) => !pages.has(contractSlug(c)));
    throw new Error(`sync-reference: no forge doc output for ${missing.join(", ")}; run \`forge doc\` first`);
  }

  await rm(OUTPUT_ROOT, { recursive: true, force: true });
  await mkdir(OUTPUT_ROOT, { recursive: true });

  for (const [slug, mdx] of pages) {
    await writeFile(join(OUTPUT_ROOT, `${slug}.mdx`), mdx);
  }

  const meta = {
    title: "API",
    pages: INCLUDED_CONTRACTS.map(contractSlug),
  };
  await writeFile(join(OUTPUT_ROOT, "meta.json"), `${JSON.stringify(meta, null, 2)}\n`);

  console.log(`Generated ${pages.size} reference pages.`);
}

if (import.meta.main) {
  await main();
}

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkStringify from "remark-stringify";
import { unified } from "unified";
import { remove } from "unist-util-remove";
import type { Heading, Root } from "mdast";

///////////////////////////////////////////////////////////////////////////
// Configuration
///////////////////////////////////////////////////////////////////////////

const SPEC_DIR = join(import.meta.dirname, "../../../spec");
const OUTPUT_DIR = join(import.meta.dirname, "../content/docs/(protocol)/specifications");

type SpecMeta = { title: string; description: string };

const SPECS: Record<string, SpecMeta> = {
  "descriptor-v2": {
    title: "Descriptor",
    description: "Binary format for describing ABI types in Callcium.",
  },
  "policy-v2": {
    title: "Policy",
    description: "Binary encoding format for onchain calldata policies.",
  },
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
// Page rendering
///////////////////////////////////////////////////////////////////////////

/** Remove the first h1 heading from the tree (title goes into frontmatter). */
function stripH1(tree: Root): void {
  let found = false;
  remove(tree, (node) => {
    if (!found && node.type === "heading" && (node as Heading).depth === 1) {
      found = true;
      return true;
    }
    return false;
  });
}

/** Escape `{` and `}` in prose while leaving fenced code blocks untouched. */
function escapeBracesOutsideCodeBlocks(text: string): string {
  return text.replace(/(```[\s\S]*?```)|([{}])/g, (_match, codeBlock, brace) => {
    if (codeBlock) return codeBlock;
    return `\\${brace}`;
  });
}

/** Spec markdown source to a rendered MDX page. */
function renderPage(source: string, { title, description }: SpecMeta): string {
  const tree = processor.parse(source);
  stripH1(tree);
  const frontmatter = ["---", `title: ${title}`, `description: ${description}`, "---", ""].join("\n");
  return frontmatter + escapeBracesOutsideCodeBlocks(processor.stringify(tree));
}

///////////////////////////////////////////////////////////////////////////
// Overview table
///////////////////////////////////////////////////////////////////////////

/** Spec version from its Document Control section. */
function specVersion(markdown: string): string {
  const match = markdown.match(/^- Version: (\d+\.\d+)/m);
  if (!match) throw new Error("Document Control section has no Version entry");
  return `v${match[1]}`;
}

/** Patch the Version column of the specs overview table to match each spec's own version. */
function syncIndexVersions(indexMd: string, versions: Record<string, string>): string {
  let result = indexMd;
  for (const [slug, version] of Object.entries(versions)) {
    const row = new RegExp(`(\\[[^\\]]+\\]\\(/docs/specifications/${slug}\\)[^|]*\\|\\s*)v\\d+\\.\\d+(\\s*\\|)`);
    result = result.replace(row, `$1${version}$2`);
  }
  return result;
}

///////////////////////////////////////////////////////////////////////////
// Main
///////////////////////////////////////////////////////////////////////////

async function main() {
  await mkdir(OUTPUT_DIR, { recursive: true });

  const versions: Record<string, string> = {};

  for (const [slug, meta] of Object.entries(SPECS)) {
    const source = await readFile(join(SPEC_DIR, `${slug}.md`), "utf-8");
    versions[slug] = specVersion(source);
    await writeFile(join(OUTPUT_DIR, `${slug}.mdx`), renderPage(source, meta));
  }

  const indexPath = join(OUTPUT_DIR, "index.mdx");
  await writeFile(indexPath, syncIndexVersions(await readFile(indexPath, "utf-8"), versions));

  // Sidebar order follows the SPECS declaration order.
  const pages = Object.keys(SPECS);
  await writeFile(join(OUTPUT_DIR, "meta.json"), `${JSON.stringify({ title: "Specifications", pages }, null, 2)}\n`);

  console.log(`Synced ${pages.length} spec pages.`);
}

void main();

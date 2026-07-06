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
  "descriptor-v1": {
    title: "Descriptor",
    description: "Binary format for describing ABI types in Callcium.",
  },
  "policy-v1": {
    title: "Policy",
    description: "Binary encoding format for onchain calldata policies.",
  },
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

///////////////////////////////////////////////////////////////////////////
// Main
///////////////////////////////////////////////////////////////////////////

async function main() {
  await mkdir(OUTPUT_DIR, { recursive: true });

  for (const [slug, { title, description }] of Object.entries(SPECS)) {
    const tree = parse(await readFile(join(SPEC_DIR, `${slug}.md`), "utf-8"));
    stripH1(tree);

    const frontmatter = [
      "---",
      `title: ${title}`,
      ...(description ? [`description: ${description}`] : []),
      "---",
      "",
    ].join("\n");

    // Escape curly braces outside fenced code blocks for MDX compatibility.
    const md = escapeBracesOutsideCodeBlocks(stringify(tree));
    await writeFile(join(OUTPUT_DIR, `${slug}.mdx`), frontmatter + md);
  }

  // Sidebar order follows the SPECS declaration order.
  const pages = Object.keys(SPECS);
  const meta = { title: "Specifications", pages };
  await writeFile(join(OUTPUT_DIR, "meta.json"), `${JSON.stringify(meta, null, 2)}\n`);

  console.log(`Synced ${pages.length} spec pages.`);
}

void main();

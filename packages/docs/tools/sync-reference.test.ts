import remarkParse from "remark-parse";
import { unified } from "unified";
import { describe, expect, it } from "vitest";
import type { Root } from "mdast";
import { takeMetadata } from "./sync-reference";

function parse(markdown: string): Root {
  return unified().use(remarkParse).parse(markdown);
}

describe("takeMetadata", () => {
  it("lifts the description out of a forge doc prologue and strips the prologue", () => {
    const tree = parse(
      [
        "# PolicyEnforcer",
        "",
        "[Git Source](https://example.com/PolicyEnforcer.sol)",
        "",
        "**Title:**",
        "",
        "Enforces that `callData` complies with a `policy`.",
        "",
        "## Functions",
      ].join("\n"),
    );

    // Inline-code markers survive — the description lands in frontmatter verbatim.
    expect(takeMetadata(tree)).toBe("Enforces that `callData` complies with a `policy`.");
    expect(tree.children).toHaveLength(1);
    expect(tree.children[0]).toMatchObject({ type: "heading", depth: 2 });
  });

  it("reports no description when a section heading follows the title", () => {
    const tree = parse("# Path\n\n## Functions\n\nProse under the first section.");

    expect(takeMetadata(tree)).toBe("");
    expect(tree.children.map((node) => node.type)).toEqual(["heading", "paragraph"]);
  });

  it("removes Git Source paragraphs below the prologue", () => {
    const tree = parse(
      [
        "# Path",
        "",
        "Encodes descriptor paths.",
        "",
        "### encode",
        "",
        "[Git Source](https://example.com/Path.sol)",
        "",
        "```solidity",
        "function encode() internal;",
        "```",
      ].join("\n"),
    );

    expect(takeMetadata(tree)).toBe("Encodes descriptor paths.");
    expect(tree.children.map((node) => node.type)).toEqual(["heading", "code"]);
  });
});

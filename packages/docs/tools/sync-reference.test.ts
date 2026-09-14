import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import { unified } from "unified";
import { describe, expect, it } from "vitest";
import type { Root } from "mdast";
import { dedentMemberCode, signatureTypes, stripEmptyTables, takeMetadata } from "./sync-reference";

function parse(markdown: string): Root {
  return unified().use(remarkParse).use(remarkGfm).parse(markdown);
}

describe("takeMetadata", () => {
  it("strips the title, source link and description of a forge doc prologue", () => {
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

    takeMetadata(tree);
    expect(tree.children).toHaveLength(1);
    expect(tree.children[0]).toMatchObject({ type: "heading", depth: 2 });
  });

  it("keeps prose a section heading introduces", () => {
    const tree = parse("# Path\n\n## Functions\n\nProse under the first section.");

    takeMetadata(tree);
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

    takeMetadata(tree);
    expect(tree.children.map((node) => node.type)).toEqual(["heading", "code"]);
  });
});

describe("signatureTypes", () => {
  it("reads the parameter types an overload is told apart by", () => {
    expect(signatureTypes("function arg(uint16 p0, uint16 p1) pure returns (Constraint memory);")).toBe(
      "uint16, uint16",
    );
  });

  it("reads a data location as part of neither the type nor the name", () => {
    expect(signatureTypes("function arg(bytes memory path) pure returns (Constraint memory);")).toBe("bytes");
  });

  it("reports no types for a declaration that takes none", () => {
    expect(signatureTypes("function msgSender() pure returns (Constraint memory);")).toBe("");
  });
});

describe("stripEmptyTables", () => {
  it("keeps a table whose descriptions say something and drops one that says nothing", () => {
    const tree = parse(
      [
        "**Parameters**",
        "",
        "| Name | Type | Description |",
        "| ---- | ---- | ----------- |",
        "| data | `uint8` | The value. |",
        "",
        "**Returns**",
        "",
        "| Name | Type | Description |",
        "| ---- | ---- | ----------- |",
        "| out | `uint8` | |",
      ].join("\n"),
    );

    stripEmptyTables(tree);
    expect(tree.children.map((node) => node.type)).toEqual(["paragraph", "table"]);
  });
});

describe("dedentMemberCode", () => {
  it("removes the nesting a member's continuation lines carry", () => {
    const tree = parse(
      [
        "```solidity",
        "function store(bytes memory policy)",
        "        internal",
        "        returns (bytes32);",
        "```",
      ].join("\n"),
    );

    dedentMemberCode(tree);
    expect(tree.children[0]).toMatchObject({
      value: "function store(bytes memory policy)\n    internal\n    returns (bytes32);",
    });
  });
});

import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  ASSEMBLY_MAP,
  buildIndex,
  formatCoverageError,
  readPublicExports,
  renderFunctionSignature,
  renderPage,
  validateCoverage,
} from "./sync-sdk-reference";

describe("validateCoverage", () => {
  it("passes when exports and map are identical", () => {
    const exports = collectMappedNames(ASSEMBLY_MAP);
    const result = validateCoverage(exports, ASSEMBLY_MAP);
    expect(result.missing).toEqual([]);
    expect(result.stale).toEqual([]);
  });

  it("reports exports missing from the map", () => {
    const mapped = collectMappedNames(ASSEMBLY_MAP);
    const exports = [...mapped, "NewExport"];
    const result = validateCoverage(exports, ASSEMBLY_MAP);
    expect(result.missing).toEqual(["NewExport"]);
    expect(result.stale).toEqual([]);
  });

  it("reports map entries with no matching export", () => {
    const mapped = collectMappedNames(ASSEMBLY_MAP);
    const exports = mapped.filter((n) => n !== "PolicyBuilder");
    const result = validateCoverage(exports, ASSEMBLY_MAP);
    expect(result.missing).toEqual([]);
    expect(result.stale).toEqual(["PolicyBuilder"]);
  });
});

describe("readPublicExports", () => {
  it("extracts top-level exported names from TypeDoc JSON", () => {
    const dir = mkdtempSync(join(tmpdir(), "sync-sdk-ref-"));
    const jsonPath = join(dir, "api.json");
    writeFileSync(
      jsonPath,
      JSON.stringify({
        children: [
          { name: "PolicyBuilder", kind: 128 },
          { name: "arg", kind: 64 },
          { name: "Hex", kind: 2097152 },
        ],
      }),
    );
    try {
      const names = readPublicExports(jsonPath);
      expect(names).toEqual(["Hex", "PolicyBuilder", "arg"]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("formatCoverageError", () => {
  it("produces an actionable error with both drift kinds", () => {
    const report = { missing: ["NewExport"], stale: ["OldExport"] };
    const msg = formatCoverageError(report, "tools/sync-sdk-reference.ts");
    expect(msg).toContain("NewExport");
    expect(msg).toContain("missing");
    expect(msg).toContain("OldExport");
    expect(msg).toContain("stale");
    expect(msg).toContain("tools/sync-sdk-reference.ts");
    expect(msg).toContain("@internal");
  });
});

describe("buildIndex", () => {
  it("maps top-level reflections by name", () => {
    const api = {
      children: [
        { id: 1, name: "PolicyBuilder", kind: 128 },
        { id: 2, name: "arg", kind: 64 },
      ],
    };
    const idx = buildIndex(api);
    expect(idx.get("PolicyBuilder")?.kind).toBe(128);
    expect(idx.get("arg")?.kind).toBe(64);
    expect(idx.size).toBe(2);
  });
});

describe("renderFunctionSignature", () => {
  it("produces a TypeScript signature line from a reflection signature", () => {
    const sig = {
      name: "arg",
      parameters: [
        { name: "index", type: { type: "intrinsic", name: "number" } },
        { name: "field", type: { type: "intrinsic", name: "number" }, flags: { isOptional: true } },
      ],
      type: { type: "reference", name: "ConstraintBuilder" },
    };
    expect(renderFunctionSignature(sig)).toBe("function arg(index: number, field?: number): ConstraintBuilder;");
  });
});

describe("renderPage (integration)", () => {
  it("emits frontmatter and a Functions section for helpers", () => {
    const api = {
      children: [
        {
          id: 1,
          name: "arg",
          kind: 64,
          comment: { summary: [{ kind: "text", text: "Select an argument." }] },
          signatures: [
            {
              name: "arg",
              parameters: [{ name: "i", type: { type: "intrinsic", name: "number" } }],
              type: { type: "reference", name: "ConstraintBuilder" },
              comment: { summary: [{ kind: "text", text: "Select an argument." }] },
            },
          ],
        },
      ],
    };
    const index = buildIndex(api);
    const mdx = renderPage(
      "constraint",
      {
        title: "Constraint",
        description: "Constraint helpers.",
        sections: { primary: [], helpers: ["arg"], types: [] },
      },
      index,
    );
    expect(mdx).toContain('title: "Constraint"');
    expect(mdx).toContain('description: "Constraint helpers."');
    expect(mdx).toContain("## Functions");
    expect(mdx).toContain("### arg");
    expect(mdx).toContain("Select an argument.");
    expect(mdx).toContain("function arg(i: number): ConstraintBuilder;");
  });

  it("renders a class in types section as a class, not AutoTypeTable", () => {
    const api = {
      children: [
        {
          id: 1,
          name: "CallciumError",
          kind: 128,
          comment: { summary: [{ kind: "text", text: "Base SDK error." }] },
          children: [],
        },
      ],
    };
    const mdx = renderPage(
      "errors",
      {
        title: "Errors",
        description: "SDK error classes.",
        sections: { primary: [], helpers: [], types: ["CallciumError"] },
        autoTypeTable: true,
        autoTypeTableSource: "errors.ts",
      },
      buildIndex(api),
    );
    expect(mdx).toContain("## CallciumError");
    expect(mdx).not.toMatch(/<auto-type-table[^>]*name="CallciumError"/);
  });

  it("emits AutoTypeTable for a type alias when the page enables it", () => {
    const api = {
      children: [{ id: 1, name: "Issue", kind: 2097152, comment: { summary: [{ kind: "text", text: "A finding." }] } }],
    };
    const mdx = renderPage(
      "types",
      {
        title: "Types",
        description: "Public types.",
        sections: { primary: [], helpers: [], types: ["Issue"] },
        autoTypeTable: true,
        autoTypeTableSource: "types.ts",
      },
      buildIndex(api),
    );
    expect(mdx).toMatch(/<auto-type-table[^>]*name="Issue"/);
  });
});

function collectMappedNames(map: typeof ASSEMBLY_MAP): string[] {
  const names = new Set<string>();
  for (const page of Object.values(map)) {
    for (const group of Object.values(page.sections)) {
      for (const name of group) names.add(name);
    }
  }
  return [...names].toSorted();
}

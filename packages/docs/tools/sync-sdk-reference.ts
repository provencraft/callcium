import { existsSync, readFileSync } from "node:fs";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { join, relative } from "node:path";

///////////////////////////////////////////////////////////////////////////
// Configuration
///////////////////////////////////////////////////////////////////////////

const TYPEDOC_DIR = join(import.meta.dirname, "../../sdk/.typedoc");
const TYPEDOC_JSON = join(TYPEDOC_DIR, "api.json");
const OUTPUT_ROOT = join(import.meta.dirname, "../content/docs/sdk/reference");
const SDK_SRC_REL = relative(OUTPUT_ROOT, join(import.meta.dirname, "../../sdk/src"));

type SectionKey = "primary" | "helpers" | "types";

interface PageSpec {
  title: string;
  description: string;
  sections: Record<SectionKey, string[]>;
  /** Pages that render types via AutoTypeTable instead of inline signatures. */
  autoTypeTable?: boolean;
  /** Source module file used by AutoTypeTable (relative to packages/sdk/src). */
  autoTypeTableSource?: string;
}

/**
 * Every export name here must be a top-level export from the SDK barrel
 * (packages/sdk/src/index.ts). The barrel is the canonical public API surface.
 */
export const ASSEMBLY_MAP: Record<string, PageSpec> = {
  "policy-builder": {
    title: "PolicyBuilder",
    description: "Fluent builder for Callcium policies.",
    sections: { primary: ["PolicyBuilder"], helpers: [], types: [] },
  },
  constraint: {
    title: "Constraint",
    description: "Constraint helpers and builder types.",
    sections: {
      primary: [],
      helpers: ["arg", "msgSender", "msgValue", "blockTimestamp", "blockNumber", "chainId", "txOrigin"],
      types: ["ConstraintBuilder", "ScalarValue"],
    },
  },
  "policy-validator": {
    title: "PolicyValidator",
    description: "Static validation of policies against their declared signatures.",
    sections: { primary: ["PolicyValidator"], helpers: ["isOpAllowed"], types: [] },
  },
  "policy-enforcer": {
    title: "PolicyEnforcer",
    description: "Off-chain policy enforcement against ABI-encoded data.",
    sections: { primary: ["PolicyEnforcer"], helpers: [], types: [] },
  },
  "policy-coder": {
    title: "PolicyCoder",
    description: "Encode and decode binary policies.",
    sections: { primary: ["PolicyCoder"], helpers: ["parsePathSteps"], types: [] },
  },
  descriptor: {
    title: "Descriptor",
    description: "ABI descriptor model and coder.",
    sections: { primary: ["Descriptor", "DescriptorCoder"], helpers: [], types: ["TypeInfo"] },
  },
  bytes: {
    title: "Bytes",
    description: "Byte and hex utilities.",
    sections: { primary: [], helpers: ["toAddress", "hexToBytes", "bytesToHex"], types: [] },
  },
  constants: {
    title: "Constants",
    description: "Protocol constants, enums, and lookup helpers.",
    sections: {
      primary: [],
      helpers: [
        "lookupOp",
        "lookupScope",
        "lookupContextProperty",
        "lookupQuantifier",
        "lookupTypeCode",
        "isQuantifier",
      ],
      types: [
        "Op",
        "TypeCode",
        "Quantifier",
        "Scope",
        "ContextProperty",
        "Limits",
        "Operands",
        "OpInfo",
        "ScopeInfo",
        "ContextPropertyInfo",
        "QuantifierInfo",
        "TypeCodeInfo",
        "TypeClassInfo",
        "TypeClass",
      ],
    },
  },
  types: {
    title: "Types",
    description: "Core TypeScript types exported by the SDK.",
    sections: {
      primary: [],
      helpers: [],
      types: [
        "Hex",
        "Address",
        "Span",
        "Field",
        "PolicyData",
        "Constraint",
        "DecodedPolicy",
        "DecodedGroup",
        "DecodedRule",
        "DecodedParam",
        "Issue",
        "IssueSeverity",
        "IssueCategory",
        "Context",
        "EnforceResult",
        "Violation",
        "ViolationCode",
      ],
    },
    autoTypeTable: true,
    autoTypeTableSource: "types.ts",
  },
  errors: {
    title: "Errors",
    description: "Error classes thrown by the SDK.",
    sections: {
      primary: ["CallciumError", "PolicyViolationError"],
      helpers: [],
      types: ["CallciumErrorCode"],
    },
    autoTypeTable: true,
    autoTypeTableSource: "errors.ts",
  },
};

///////////////////////////////////////////////////////////////////////////
// Coverage validation
///////////////////////////////////////////////////////////////////////////

export interface CoverageReport {
  missing: string[];
  stale: string[];
}

export function validateCoverage(publicExports: readonly string[], map: Record<string, PageSpec>): CoverageReport {
  const mapped = new Set<string>();
  for (const page of Object.values(map)) {
    for (const group of Object.values(page.sections)) {
      for (const name of group) mapped.add(name);
    }
  }
  const exportSet = new Set(publicExports);

  const missing = [...exportSet].filter((name) => !mapped.has(name)).toSorted();
  const stale = [...mapped].filter((name) => !exportSet.has(name)).toSorted();
  return { missing, stale };
}

///////////////////////////////////////////////////////////////////////////
// TypeDoc JSON reader
///////////////////////////////////////////////////////////////////////////

interface TypeDocChild {
  name: string;
  kind: number;
  flags?: { isExternal?: boolean };
}

export function readPublicExports(apiJsonPath: string): string[] {
  if (!existsSync(apiJsonPath)) {
    throw new Error(`TypeDoc JSON not found at ${apiJsonPath}. Run typedoc first.`);
  }
  const raw = JSON.parse(readFileSync(apiJsonPath, "utf8")) as {
    children?: TypeDocChild[];
  };
  const children = raw.children ?? [];
  const names = children.filter((child) => !child.flags?.isExternal).map((child) => child.name);
  return [...new Set(names)].toSorted();
}

///////////////////////////////////////////////////////////////////////////
// Error reporting
///////////////////////////////////////////////////////////////////////////

export function formatCoverageError(report: CoverageReport, mapSource: string): string {
  const lines: string[] = [];
  if (report.missing.length > 0) {
    lines.push(`Unmapped public SDK exports (${report.missing.length}):`);
    for (const name of report.missing) {
      lines.push(`  - ${name}    [missing: not in ASSEMBLY_MAP]`);
    }
  }
  if (report.stale.length > 0) {
    lines.push(`Stale assembly entries (${report.stale.length}):`);
    for (const name of report.stale) {
      lines.push(`  - ${name}    [stale: mapped but not exported or @internal]`);
    }
  }
  lines.push("");
  lines.push(`Edit ASSEMBLY_MAP in ${mapSource} to add missing entries or remove stale ones.`);
  lines.push(`To intentionally omit an export from docs, mark it with @internal in the source TSDoc.`);
  return lines.join("\n");
}

///////////////////////////////////////////////////////////////////////////
// TypeDoc JSON model — index + helpers
///////////////////////////////////////////////////////////////////////////

interface TypeDocComment {
  summary?: Array<{ kind: string; text: string }>;
  blockTags?: Array<{ tag: string; content: Array<{ kind: string; text: string }> }>;
}

interface TypeDocType {
  type: string;
  name?: string;
  element?: TypeDocType;
  elementType?: TypeDocType;
  typeArguments?: TypeDocType[];
  value?: string | number;
  types?: TypeDocType[];
  declaration?: TypeDocReflection;
}

interface TypeDocParam {
  name: string;
  type?: TypeDocType;
  flags?: { isOptional?: boolean; isRest?: boolean };
  comment?: TypeDocComment;
}

interface TypeDocSignature {
  name: string;
  parameters?: TypeDocParam[];
  type?: TypeDocType;
  comment?: TypeDocComment;
}

interface TypeDocReflection {
  id: number;
  name: string;
  kind: number;
  comment?: TypeDocComment;
  signatures?: TypeDocSignature[];
  children?: TypeDocReflection[];
  type?: TypeDocType;
  sources?: Array<{ fileName: string; line: number; url?: string }>;
  flags?: { isOptional?: boolean; isReadonly?: boolean };
}

interface TypeDocRoot {
  children?: TypeDocReflection[];
}

export function buildIndex(root: TypeDocRoot): Map<string, TypeDocReflection> {
  const idx = new Map<string, TypeDocReflection>();
  for (const child of root.children ?? []) {
    idx.set(child.name, child);
  }
  return idx;
}

function summaryText(comment: TypeDocComment | undefined): string {
  if (!comment?.summary) return "";
  return comment.summary
    .map((part) => part.text)
    .join("")
    .trim();
}

/** Escape bare `<` in prose so MDX doesn't parse it as a JSX tag. */
function escapeForMdx(text: string): string {
  return text.replace(/</g, "&lt;");
}

/** Quote a string for YAML frontmatter — handles embedded quotes. */
function yamlString(value: string): string {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

/** Build a "Git Source" link from a reflection's first source entry. */
function sourceLink(ref: TypeDocReflection): string | null {
  const source = ref.sources?.[0];
  if (!source?.url) return null;
  return `[Git Source](${source.url})`;
}

function renderType(t: TypeDocType | undefined): string {
  if (!t) return "unknown";
  switch (t.type) {
    case "intrinsic":
    case "reference":
      return t.name ?? "unknown";
    case "literal":
      return JSON.stringify(t.value);
    case "array":
      return `${renderType(t.elementType)}[]`;
    case "union":
      return (t.types ?? []).map(renderType).join(" | ");
    case "intersection":
      return (t.types ?? []).map(renderType).join(" & ");
    case "reflection":
      return "object";
    default:
      return t.name ?? t.type;
  }
}

export function renderFunctionSignature(sig: TypeDocSignature): string {
  const params = (sig.parameters ?? [])
    .map((p) => {
      const optional = p.flags?.isOptional ? "?" : "";
      const rest = p.flags?.isRest ? "..." : "";
      return `${rest}${p.name}${optional}: ${renderType(p.type)}`;
    })
    .join(", ");
  return `function ${sig.name}(${params}): ${renderType(sig.type)};`;
}

///////////////////////////////////////////////////////////////////////////
// Page renderer
///////////////////////////////////////////////////////////////////////////

const KIND = {
  Class: 128,
  Function: 64,
  Interface: 256,
  TypeAlias: 2097152,
  Variable: 32,
  Method: 2048,
  Enumeration: 8,
  Property: 1024,
} as const;

function renderParamTable(params: TypeDocParam[]): string {
  const lines = ["**Parameters**", "", "| Name | Type | Description |", "| --- | --- | --- |"];
  for (const p of params) {
    const desc = escapeForMdx(summaryText(p.comment) || "-");
    lines.push(`| \`${p.name}\` | \`${renderType(p.type)}\` | ${desc} |`);
  }
  lines.push("");
  return lines.join("\n");
}

function renderReturns(sig: TypeDocSignature): string {
  const desc = sig.comment?.blockTags?.find((tag) => tag.tag === "@returns");
  const descText = desc ? escapeForMdx(desc.content.map((c) => c.text).join("")) : "";
  return ["**Returns**", "", `\`${renderType(sig.type)}\`${descText ? ` — ${descText}` : ""}`, ""].join("\n");
}

function renderFunction(ref: TypeDocReflection): string {
  const parts: string[] = [];
  parts.push(`### ${ref.name}`);
  parts.push("");
  const sig = ref.signatures?.[0];
  if (!sig) {
    parts.push(escapeForMdx(summaryText(ref.comment)));
    parts.push("");
    return parts.join("\n");
  }
  parts.push(escapeForMdx(summaryText(sig.comment) || summaryText(ref.comment)));
  parts.push("");
  const src = sourceLink(ref);
  if (src) {
    parts.push(src);
    parts.push("");
  }
  parts.push("```ts");
  parts.push(renderFunctionSignature(sig));
  parts.push("```");
  parts.push("");
  if (sig.parameters && sig.parameters.length > 0) {
    parts.push(renderParamTable(sig.parameters));
  }
  if (sig.type) {
    parts.push(renderReturns(sig));
  }
  return parts.join("\n");
}

function renderClass(ref: TypeDocReflection): string {
  const parts: string[] = [];
  parts.push(`## ${ref.name}`);
  parts.push("");
  parts.push(escapeForMdx(summaryText(ref.comment)));
  parts.push("");
  const src = sourceLink(ref);
  if (src) {
    parts.push(src);
    parts.push("");
  }
  const methods = (ref.children ?? []).filter((c) => c.kind === KIND.Method);
  if (methods.length === 0) return parts.join("\n");
  parts.push("### Methods");
  parts.push("");
  for (const method of methods) {
    parts.push(renderFunction(method));
  }
  return parts.join("\n");
}

function renderTypeHeading(ref: TypeDocReflection): string {
  const parts: string[] = [];
  parts.push(`### ${ref.name}`);
  parts.push("");
  parts.push(escapeForMdx(summaryText(ref.comment)));
  parts.push("");
  const src = sourceLink(ref);
  if (src) {
    parts.push(src);
    parts.push("");
  }
  return parts.join("\n");
}

function isNamespaceVariable(ref: TypeDocReflection): boolean {
  if (ref.kind !== KIND.Variable) return false;
  const decl = ref.type?.declaration;
  if (!decl || !decl.children) return false;
  return decl.children.some((c) => c.type?.type === "reflection" && (c.type.declaration?.signatures?.length ?? 0) > 0);
}

function renderNamespaceVariable(ref: TypeDocReflection): string {
  const parts: string[] = [];
  parts.push(`## ${ref.name}`);
  parts.push("");
  parts.push(escapeForMdx(summaryText(ref.comment)));
  parts.push("");
  const src = sourceLink(ref);
  if (src) {
    parts.push(src);
    parts.push("");
  }

  const props = ref.type?.declaration?.children ?? [];
  const methods = props.filter(
    (p) => p.type?.type === "reflection" && (p.type.declaration?.signatures?.length ?? 0) > 0,
  );
  if (methods.length === 0) return parts.join("\n");

  parts.push("### Methods");
  parts.push("");
  for (const prop of methods) {
    const sigs = prop.type!.declaration!.signatures!;
    // Rename anonymous signatures (e.g. "__type") to the owning property name
    // so both the heading and the `function X(...)` line agree.
    const namedSigs = sigs.map((sig) => ({ ...sig, name: prop.name }));
    const pseudoFunc: TypeDocReflection = {
      id: prop.id,
      name: prop.name,
      kind: KIND.Function,
      comment: prop.comment ?? sigs[0]?.comment,
      signatures: namedSigs,
    };
    parts.push(renderFunction(pseudoFunc));
  }
  return parts.join("\n");
}

function renderSymbol(ref: TypeDocReflection, autoTypeTablePath: string | undefined): string {
  if (ref.kind === KIND.Class) return renderClass(ref);
  if (ref.kind === KIND.Function) return renderFunction(ref);
  if (isNamespaceVariable(ref)) return renderNamespaceVariable(ref);
  const heading = renderTypeHeading(ref);
  if (autoTypeTablePath && (ref.kind === KIND.TypeAlias || ref.kind === KIND.Interface)) {
    return `${heading}<auto-type-table path="${autoTypeTablePath}" name="${ref.name}" />\n`;
  }
  return heading;
}

export function renderPage(slug: string, spec: PageSpec, index: Map<string, TypeDocReflection>): string {
  const lookup = (name: string): TypeDocReflection => {
    const ref = index.get(name);
    if (!ref) {
      throw new Error(
        `Export "${name}" is in ASSEMBLY_MAP for page "${slug}" but not in TypeDoc JSON. Ensure it is exported from src/index.ts and not marked @internal.`,
      );
    }
    return ref;
  };

  const autoTypeTablePath =
    spec.autoTypeTable && spec.autoTypeTableSource ? join(SDK_SRC_REL, spec.autoTypeTableSource) : undefined;

  const parts = ["---", `title: ${yamlString(spec.title)}`, `description: ${yamlString(spec.description)}`, "---", ""];

  for (const name of spec.sections.primary) {
    parts.push(renderSymbol(lookup(name), autoTypeTablePath));
  }

  if (spec.sections.helpers.length > 0) {
    parts.push("## Functions", "");
    for (const name of spec.sections.helpers) {
      parts.push(renderSymbol(lookup(name), autoTypeTablePath));
    }
  }

  if (spec.sections.types.length > 0) {
    parts.push("## Types", "");
    for (const name of spec.sections.types) {
      parts.push(renderSymbol(lookup(name), autoTypeTablePath));
    }
  }

  return parts.join("\n");
}

///////////////////////////////////////////////////////////////////////////
// Main
///////////////////////////////////////////////////////////////////////////

async function main(): Promise<void> {
  if (!existsSync(TYPEDOC_JSON)) {
    throw new Error(`TypeDoc JSON not found at ${TYPEDOC_JSON}. Run: bun run --cwd ../sdk typedoc`);
  }
  const apiRoot = JSON.parse(readFileSync(TYPEDOC_JSON, "utf8")) as TypeDocRoot;
  const index = buildIndex(apiRoot);

  const publicExports = [...index.keys()].toSorted();
  const report = validateCoverage(publicExports, ASSEMBLY_MAP);
  if (report.missing.length > 0 || report.stale.length > 0) {
    console.error(formatCoverageError(report, "tools/sync-sdk-reference.ts"));
    process.exit(1);
  }

  if (existsSync(OUTPUT_ROOT)) {
    const { readdir } = await import("node:fs/promises");
    for (const entry of await readdir(OUTPUT_ROOT)) {
      await rm(join(OUTPUT_ROOT, entry), { recursive: true, force: true });
    }
  } else {
    await mkdir(OUTPUT_ROOT, { recursive: true });
  }

  for (const [slug, spec] of Object.entries(ASSEMBLY_MAP)) {
    const mdx = renderPage(slug, spec, index);
    const outPath = join(OUTPUT_ROOT, `${slug}.mdx`);
    await writeFile(outPath, mdx);
    console.log(`  wrote ${relative(process.cwd(), outPath)}`);
  }

  // Generate meta.json from ASSEMBLY_MAP to prevent drift when pages are added or removed.
  const meta = {
    title: "API",
    pages: Object.keys(ASSEMBLY_MAP),
  };
  await writeFile(join(OUTPUT_ROOT, "meta.json"), `${JSON.stringify(meta, null, 2)}\n`);
}

if (import.meta.main) {
  await main();
}

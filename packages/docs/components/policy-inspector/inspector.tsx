"use client";

import { type DecodedPolicy, type Hex, lookupScope, parsePathSteps, PolicyCoder, type Span } from "@callcium/sdk";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "fumadocs-ui/components/ui/collapsible";
import { ChevronDown, ArrowRight } from "lucide-react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { memo, useCallback, useEffect, useMemo, useState } from "react";
import type { Abi } from "viem";
import { PillToggle } from "@/components/ui/pill-toggle";
import { lookup4byte, parseAbiJson } from "@/lib/abi";
import { formatError } from "@/lib/format-error";
import { useDebounce } from "@/lib/use-debounce";
import { cn } from "@/lib/utils";
import { type ExplainedPolicy, type ExplainedRule, explainPolicy, flattenGroup } from "@/tools/policy-inspector";

const plural = (n: number) => (n === 1 ? "" : "s");

///////////////////////////////////////////////////////////////////////////
// Decode logic
///////////////////////////////////////////////////////////////////////////

type DecodeResult =
  | {
      ok: true;
      decoded: DecodedPolicy;
      explained: ExplainedPolicy;
      hex: string;
    }
  | { ok: false; error: string };

function tryDecode(hex: string, abi: Abi | undefined): DecodeResult | null {
  const trimmed = hex.trim();
  if (!trimmed) return null;

  const normalized = trimmed.startsWith("0x") ? trimmed : `0x${trimmed}`;
  if (!/^0x[0-9a-fA-F]+$/.test(normalized)) {
    return { ok: false, error: "Invalid hex string." };
  }

  try {
    const decoded = PolicyCoder.inspect(normalized as Hex);
    const explained = explainPolicy(decoded, abi ? { abi } : undefined);
    return { ok: true, decoded, explained, hex: normalized };
  } catch (e) {
    return { ok: false, error: formatError(e) };
  }
}

///////////////////////////////////////////////////////////////////////////
// Main component
///////////////////////////////////////////////////////////////////////////

export function Inspector() {
  const searchParams = useSearchParams();
  const [hexInput, setHexInput] = useState("");
  const [abiInput, setAbiInput] = useState("");
  const [abiOpen, setAbiOpen] = useState(false);
  const [lookedUpName, setLookedUpName] = useState<string | null>(null);
  const [lookingUp, setLookingUp] = useState(false);
  const [inspectMode, setInspectMode] = useState(false);

  useEffect(() => {
    const policyHex = searchParams.get("policy");
    if (policyHex) setHexInput(policyHex);
  }, [searchParams]);

  const debouncedHex = useDebounce(hexInput, 300);
  const abi = useMemo(() => {
    const parsed = parseAbiJson(abiInput);
    return parsed instanceof Error ? undefined : parsed;
  }, [abiInput]);

  const result = useMemo(() => tryDecode(debouncedHex, abi), [debouncedHex, abi]);

  // 4byte lookup when we have a selector without an ABI-resolved name.
  const lookupSelector =
    result?.ok && !result.explained.functionName && !result.explained.isSelectorless ? result.explained.selector : null;

  useEffect(() => {
    setLookedUpName(null);
    setLookingUp(false);
    if (!lookupSelector) return;

    const controller = new AbortController();
    setLookingUp(true);
    void lookup4byte(lookupSelector, controller.signal).then((name) => {
      if (!controller.signal.aborted) {
        setLookedUpName(name);
        setLookingUp(false);
      }
    });
    return () => controller.abort();
  }, [lookupSelector]);

  const resolvedName = result?.ok && result.explained.functionName ? result.explained.functionName : lookedUpName;

  const handlePaste = useCallback((e: React.ClipboardEvent<HTMLTextAreaElement>) => {
    const pasted = e.clipboardData.getData("text");
    if (pasted.trim()) {
      setHexInput(pasted);
      e.preventDefault();
    }
  }, []);

  return (
    <div className="space-y-4">
      {/* Policy blob input */}
      <div>
        <div className="mb-1.5 flex items-center justify-between">
          <label htmlFor="policy-hex" className="text-sm font-medium text-fd-foreground">
            Policy Blob
          </label>
          {result?.ok && (
            <Link
              href={`/policy-enforcer?policy=${encodeURIComponent(debouncedHex)}`}
              className="text-sm text-fd-muted-foreground hover:text-fd-foreground transition-colors"
            >
              Enforcer <ArrowRight className="inline size-3" />
            </Link>
          )}
        </div>
        <textarea
          id="policy-hex"
          className={cn(
            "w-full rounded-lg border bg-fd-card px-3 py-2 font-mono text-sm",
            "placeholder:text-fd-muted-foreground/50",
            "focus:outline-none focus:ring-2 focus:ring-inset focus:ring-fd-ring",
            "resize-y",
            result && !result.ok ? "border-red-500/50" : "border-fd-border",
          )}
          rows={3}
          placeholder="0x01095ea7b3..."
          value={hexInput}
          onChange={(e) => setHexInput(e.target.value)}
          onPaste={handlePaste}
          spellCheck={false}
          autoComplete="off"
        />
      </div>

      {/* ABI input (collapsible) */}
      <Collapsible open={abiOpen} onOpenChange={setAbiOpen}>
        <CollapsibleTrigger className="flex items-center gap-1.5 text-sm text-fd-muted-foreground transition-colors hover:text-fd-foreground">
          <ChevronDown className={cn("size-4 transition-transform", abiOpen && "rotate-180")} />
          ABI (optional)
        </CollapsibleTrigger>
        <CollapsibleContent>
          <textarea
            className={cn(
              "mt-2 w-full rounded-lg border border-fd-border bg-fd-card px-3 py-2 font-mono text-sm",
              "placeholder:text-fd-muted-foreground/50",
              "focus:outline-none focus:ring-2 focus:ring-inset focus:ring-fd-ring",
              "resize-y",
            )}
            rows={4}
            placeholder='[{"type":"function","name":"approve",...}]'
            value={abiInput}
            onChange={(e) => setAbiInput(e.target.value)}
            spellCheck={false}
          />
        </CollapsibleContent>
      </Collapsible>

      {/* Error */}
      {result && !result.ok && (
        <div className="rounded-lg border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-700 dark:text-red-300">
          {result.error}
        </div>
      )}

      {/* Loading indicator for 4byte lookup */}
      {lookingUp && <div className="text-xs text-fd-muted-foreground">Looking up function name…</div>}

      {/* Output */}
      {result?.ok && (
        <div>
          <PillToggle
            className="mb-3"
            value={inspectMode ? "inspect" : "summary"}
            options={[
              { value: "summary", label: "Summary" },
              { value: "inspect", label: "Inspect" },
            ]}
            onChange={(v) => setInspectMode(v === "inspect")}
          />

          {inspectMode ? (
            <InspectView decoded={result.decoded} explained={result.explained} hex={result.hex} />
          ) : (
            <SummaryView policy={result.explained} functionName={resolvedName} />
          )}
        </div>
      )}
    </div>
  );
}

///////////////////////////////////////////////////////////////////////////
// Summary view
///////////////////////////////////////////////////////////////////////////

function formatOperands(rule: ExplainedRule): string {
  const op = rule.operator;
  if (op === "in" || op === "not in") return `{${rule.operands.join(", ")}}`;
  if (op.includes("between")) return `[${rule.operands.join(", ")}]`;
  return rule.operands.join(", ");
}

function SummaryView({ policy, functionName }: { policy: ExplainedPolicy; functionName: string | null }) {
  const displayName = functionName ?? policy.functionName ?? policy.selector;
  const params = policy.params.map((p) => (p.name ? `${p.type} ${p.name}` : p.type)).join(", ");

  const groupClauses = policy.groups.map(flattenGroup);

  return (
    <div className="space-y-3">
      {/* Signature */}
      <div className="rounded-lg border border-fd-border bg-fd-card px-4 py-3 font-mono text-sm">
        {policy.isSelectorless ? (
          <span className="text-fd-muted-foreground">No Selector</span>
        ) : (
          <>
            <code className="font-semibold text-fd-foreground">
              {displayName}({params})
            </code>
            {(functionName || policy.functionName) && (
              <code className="ml-3 text-fd-muted-foreground">{policy.selector}</code>
            )}
          </>
        )}
      </div>

      {groupClauses.length === 1 ? (
        <div className="rounded-lg border border-fd-border bg-fd-card px-4 py-3 font-mono text-sm space-y-0.5">
          {groupClauses[0].map(({ constraint, rule }, ri) => (
            // oxlint-disable-next-line react/no-array-index-key
            <div key={ri} className="flex flex-wrap items-baseline gap-1.5">
              <span className="text-fd-foreground">{constraint.pathLabel}</span>
              <span className="text-fd-muted-foreground">{rule.operator}</span>
              <span className="break-all text-fd-foreground">{formatOperands(rule)}</span>
              <span className="text-fd-muted-foreground">: {constraint.targetType}</span>
            </div>
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-[auto_1fr] gap-x-2">
          {groupClauses.map((clause, gi) => (
            // oxlint-disable-next-line react/no-array-index-key
            <div key={gi} className="contents">
              {/* OR gap row */}
              {gi > 0 && (
                <>
                  <div className="relative flex h-5 items-center">
                    <div className="absolute inset-y-0 left-px w-px bg-fd-muted-foreground/40" />
                    <span className="relative z-10 -translate-x-[calc(50%-1px)] bg-fd-background px-1 text-xs font-semibold text-fd-info-foreground">
                      OR
                    </span>
                  </div>
                  <div />
                </>
              )}
              {/* Bracket tick cell */}
              <div className="relative flex items-center">
                <div
                  className={cn(
                    "absolute left-px w-px bg-fd-muted-foreground/40",
                    gi === 0 && "top-1/2 bottom-0",
                    gi === groupClauses.length - 1 && "top-0 bottom-1/2",
                    gi > 0 && gi < groupClauses.length - 1 && "inset-y-0",
                  )}
                />
                <div className="h-px w-3 bg-fd-muted-foreground/40" />
              </div>
              {/* Card cell */}
              <div className="rounded-lg border border-fd-border bg-fd-card px-4 py-3 font-mono text-sm space-y-0.5">
                {clause.map(({ constraint, rule }, ri) => (
                  // oxlint-disable-next-line react/no-array-index-key
                  <div key={ri} className="flex flex-wrap items-baseline gap-1.5">
                    <span className="text-fd-foreground">{constraint.pathLabel}</span>
                    <span className="text-fd-muted-foreground">{rule.operator}</span>
                    <span className="break-all text-fd-foreground">{formatOperands(rule)}</span>
                    <span className="text-fd-muted-foreground">: {constraint.targetType}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

///////////////////////////////////////////////////////////////////////////
// Inspect view
///////////////////////////////////////////////////////////////////////////

type TreeNode = {
  label: string;
  value: string;
  hex: string;
  span: Span;
  children?: TreeNode[];
};

function buildTree(decoded: DecodedPolicy, explained: ExplainedPolicy, rawHex: string): TreeNode[] {
  const cleanHex = rawHex.startsWith("0x") ? rawHex.slice(2) : rawHex;
  const sliceHex = (span: Span) => {
    const raw = cleanHex.slice(span.start * 2, span.end * 2);
    return raw.match(/.{2}/g)?.join(" ") ?? "";
  };
  const node = (label: string, value: string, span: Span, children?: TreeNode[]): TreeNode => ({
    label,
    value,
    hex: sliceHex(span),
    span,
    children,
  });

  // Header.
  const headerBits: string[] = [`v${decoded.version}`];
  if (decoded.isSelectorless) headerBits.push("selectorless");

  // Selector.
  const selectorLabel = decoded.isSelectorless ? "zeroed" : decoded.selector.value;

  // Descriptor.
  const desc = decoded.descriptor;
  const paramCount = explained.params.length;
  const descChildren: TreeNode[] = [
    node("Desc Header", `v${desc.header.value.version}, ${paramCount} param${plural(paramCount)}`, desc.header.span),
  ];
  for (let i = 0; i < desc.params.length; i++) {
    const dp = desc.params[i];
    const ep = explained.params[i];
    const typeLabel = ep?.type ?? `param(${i})`;
    const nameLabel = ep?.name ? ` ${ep.name}` : "";
    descChildren.push(node(`Param [${i}]`, `${typeLabel}${nameLabel}`, dp.span));
  }

  const nodes: TreeNode[] = [
    node("Header", headerBits.join(", "), decoded.header.span),
    node(
      "Selector",
      explained.functionName ? `${selectorLabel} (${explained.functionName})` : selectorLabel,
      decoded.selector.span,
    ),
    node("Desc Length", String(decoded.descLength.value), decoded.descLength.span),
    node("Descriptor", `${paramCount} param${plural(paramCount)}`, desc.span, descChildren),
    node("Group Count", String(decoded.groupCount.value), decoded.groupCount.span),
  ];

  // Groups.
  // Flatten explained constraints+rules for display alignment with decoded rules.
  for (let gi = 0; gi < decoded.groups.length; gi++) {
    const decodedGroup = decoded.groups[gi];
    const explainedGroup = explained.groups[gi];

    let explainedRuleIndex = 0;
    const explainedRules = explainedGroup ? flattenGroup(explainedGroup) : [];

    const ruleNodes: TreeNode[] = [];
    for (let ri = 0; ri < decodedGroup.rules.length; ri++) {
      const decodedRule = decodedGroup.rules[ri];
      const info = explainedRules[explainedRuleIndex];
      explainedRuleIndex++;

      const summary = info
        ? `${info.constraint.pathLabel} ${info.rule.operator} ${formatOperands(info.rule)} : ${info.constraint.targetType}`
        : "";
      const opDisplay = info?.rule.operator ?? `0x${decodedRule.opCode.value.toString(16).padStart(2, "0")}`;
      const dataValue = info ? `${formatOperands(info.rule)} : ${info.constraint.targetType}` : decodedRule.data.value;

      ruleNodes.push({
        ...node(`Rule ${ri + 1}`, summary, decodedRule.span, [
          node("Rule Size", String(decodedRule.ruleSize.value), decodedRule.ruleSize.span),
          node("Scope", lookupScope(decodedRule.scope.value).label, decodedRule.scope.span),
          node("Path Depth", String(decodedRule.pathDepth.value), decodedRule.pathDepth.span),
          node("Path", `[${parsePathSteps(decodedRule.path.value).join(", ")}]`, decodedRule.path.span),
          node("OpCode", opDisplay, decodedRule.opCode.span),
          node("Data Length", String(decodedRule.dataLength.value), decodedRule.dataLength.span),
          node("Data", dataValue, decodedRule.data.span),
        ]),
        hex: "",
      });
    }

    // Group header spans (ruleCount + groupSize) for the parent hex display.
    const groupHeaderSpan: Span = {
      start: decodedGroup.ruleCount.span.start,
      end: decodedGroup.groupSize.span.end,
    };

    nodes.push({
      ...node(
        `Group ${gi + 1}`,
        `${decodedGroup.ruleCount.value} rule${plural(decodedGroup.ruleCount.value)}, ${decodedGroup.groupSize.value} byte${plural(decodedGroup.groupSize.value)}`,
        decodedGroup.span,
        [
          node("Rule Count", String(decodedGroup.ruleCount.value), decodedGroup.ruleCount.span),
          node("Group Size", String(decodedGroup.groupSize.value), decodedGroup.groupSize.span),
          ...ruleNodes,
        ],
      ),
      hex: sliceHex(groupHeaderSpan),
    });
  }

  return nodes;
}

// Map each byte index to its deepest owning span for hover interaction.
function buildByteToSpan(nodes: TreeNode[], totalBytes: number): (Span | null)[] {
  const map: (Span | null)[] = Array.from<Span | null>({ length: totalBytes }).fill(null);
  // Walk all nodes depth-first; deeper nodes overwrite shallower ones.
  function walk(node: TreeNode) {
    for (let i = node.span.start; i < node.span.end && i < totalBytes; i++) {
      map[i] = node.span;
    }
    if (node.children) {
      for (const child of node.children) walk(child);
    }
  }
  for (const n of nodes) walk(n);
  return map;
}

function HexDump({
  hex,
  tree,
  hovered,
  onHover,
}: {
  hex: string;
  tree: TreeNode[];
  hovered: Span | null;
  onHover: (span: Span | null) => void;
}) {
  const cleanHex = hex.startsWith("0x") ? hex.slice(2) : hex;
  const totalBytes = cleanHex.length / 2;

  const byteToSpan = useMemo(() => buildByteToSpan(tree, totalBytes), [tree, totalBytes]);

  // Event delegation: resolve byte index from data attribute.
  const handleMouseMove = useCallback(
    (e: React.MouseEvent) => {
      const idx = Number((e.target as HTMLElement).dataset.idx);
      if (!Number.isNaN(idx)) {
        const span = byteToSpan[idx];
        if (span) onHover(span);
      }
    },
    [byteToSpan, onHover],
  );
  const handleMouseLeave = useCallback(() => onHover(null), [onHover]);

  return (
    <div className="rounded-t-lg border-b border-fd-border bg-fd-muted/30 px-4 py-3">
      {/* oxlint-disable-next-line jsx-a11y/no-static-element-interactions -- hex dump uses event delegation for hover. */}
      <div
        className="flex flex-wrap gap-x-0.5 gap-y-0.5 font-mono text-xs leading-relaxed"
        onMouseMove={handleMouseMove}
        onMouseLeave={handleMouseLeave}
      >
        {Array.from({ length: totalBytes }, (_, byteIndex) => {
          const byteHex = cleanHex.slice(byteIndex * 2, byteIndex * 2 + 2);
          const isHighlighted = hovered && byteIndex >= hovered.start && byteIndex < hovered.end;
          const isCovered = byteToSpan[byteIndex] !== null;

          return (
            <span
              key={byteIndex}
              data-idx={byteIndex}
              className={cn(
                "rounded-sm px-0.5 cursor-default",
                isHighlighted
                  ? "bg-fd-info text-fd-info-foreground ring-1 ring-fd-info-foreground/30"
                  : isCovered
                    ? "text-fd-foreground"
                    : "text-fd-muted-foreground/50",
              )}
            >
              {byteHex}
            </span>
          );
        })}
      </div>
    </div>
  );
}

function InspectView({ decoded, explained, hex }: { decoded: DecodedPolicy; explained: ExplainedPolicy; hex: string }) {
  const tree = useMemo(() => buildTree(decoded, explained, hex), [decoded, explained, hex]);
  const [hovered, setHovered] = useState<Span | null>(null);

  return (
    <div className="rounded-lg border border-fd-border bg-fd-card">
      <HexDump hex={hex} tree={tree} hovered={hovered} onHover={setHovered} />
      <div className="font-mono text-xs">
        <div
          className="flex items-baseline gap-2 border-b border-fd-border px-3 py-1 text-fd-muted-foreground/60"
          style={{ paddingLeft: "12px" }}
        >
          <span className="w-3 shrink-0" />
          <span className="w-24 shrink-0">Field</span>
          <span className="min-w-0 flex-1">Value</span>
          <span className="shrink-0">Hex</span>
          <span className="w-16 shrink-0 text-right">Offset</span>
        </div>
        {tree.map((node, i) => (
          // oxlint-disable-next-line react/no-array-index-key
          <TreeRow key={i} node={node} depth={0} hovered={hovered} onHover={setHovered} />
        ))}
      </div>
    </div>
  );
}

const TreeRow = memo(function TreeRow({
  node,
  depth,
  hovered,
  onHover,
}: {
  node: TreeNode;
  depth: number;
  hovered: Span | null;
  onHover: (span: Span | null) => void;
}) {
  const [expanded, setExpanded] = useState(depth < 2);
  const hasChildren = node.children && node.children.length > 0;
  const isHovered = hovered && hovered.start === node.span.start && hovered.end === node.span.end;

  const displayHex = node.hex.length > 48 ? `${node.hex.slice(0, 24)} … ${node.hex.slice(-18)}` : node.hex;

  return (
    <>
      {/* oxlint-disable-next-line jsx-a11y/no-static-element-interactions -- role is set conditionally when hasChildren is true. */}
      <div
        role={hasChildren ? "button" : undefined}
        tabIndex={hasChildren ? 0 : undefined}
        className={cn(
          "group flex items-baseline gap-2 border-b border-fd-border/30 px-3 py-1.5",
          isHovered && "is-hovered bg-fd-info",
          hasChildren && "cursor-pointer",
        )}
        style={{ paddingLeft: `${depth * 16 + 12}px` }}
        onMouseEnter={() => onHover(node.span)}
        onMouseLeave={() => onHover(null)}
        onClick={() => hasChildren && setExpanded(!expanded)}
        onKeyDown={(e) => {
          if (hasChildren && (e.key === "Enter" || e.key === " ")) {
            e.preventDefault();
            setExpanded(!expanded);
          }
        }}
      >
        <span className="w-3 shrink-0 text-fd-muted-foreground/50">{hasChildren ? (expanded ? "▼" : "▶") : ""}</span>
        <span className="w-24 shrink-0 text-fd-muted-foreground">{node.label}</span>
        <span className="min-w-0 flex-1 truncate text-fd-foreground group-[.is-hovered]:text-fd-info-foreground">
          {node.value}
        </span>
        {displayHex && (
          <span className="shrink-0 text-fd-muted-foreground/60 group-[.is-hovered]:text-fd-info-foreground">
            {displayHex}
          </span>
        )}

        <span className="w-16 shrink-0 text-right text-fd-muted-foreground/40 group-[.is-hovered]:text-fd-info-foreground">
          {node.span.start === node.span.end - 1 ? `${node.span.start}` : `${node.span.start}–${node.span.end - 1}`}
        </span>
      </div>

      {hasChildren &&
        expanded &&
        node.children?.map((child, i) => (
          // oxlint-disable-next-line react/no-array-index-key
          <TreeRow key={i} node={child} depth={depth + 1} hovered={hovered} onHover={onHover} />
        ))}
    </>
  );
});

"use client";

import {
  CallciumError,
  DescriptorFormat as DF,
  type Hex,
  lookupTypeCode,
  type PolicyData,
  parsePathSteps,
  PolicyCoder,
  PolicyFormat as PF,
  type Span,
} from "@callcium/sdk";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "fumadocs-ui/components/ui/collapsible";
import { ChevronDown } from "lucide-react";
import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Abi } from "viem";
import { EXAMPLES, type PolicyExample } from "./examples";
import { useDebounce } from "./use-debounce";
import { cn } from "@/lib/utils";
import {
  type ExplainedConstraint,
  type ExplainedPolicy,
  type ExplainedRule,
  explainPolicy,
} from "@/tools/policy-inspector";

const s = (n: number) => (n === 1 ? "" : "s");

///////////////////////////////////////////////////////////////////////////
//                           DECODE LOGIC
///////////////////////////////////////////////////////////////////////////

type DecodeResult =
  | {
      ok: true;
      policy: PolicyData;
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
    const policy = PolicyCoder.decode(normalized as Hex);
    const explained = explainPolicy(policy, abi ? { abi } : undefined);
    return { ok: true, policy, explained, hex: normalized };
  } catch (e) {
    if (e instanceof CallciumError) {
      return { ok: false, error: `${e.code}: ${e.message}` };
    }
    return {
      ok: false,
      error: e instanceof Error ? e.message : "Unknown error.",
    };
  }
}

function parseAbi(json: string): Abi | undefined {
  if (!json.trim()) return undefined;
  try {
    const parsed = JSON.parse(json);
    if (!Array.isArray(parsed)) return undefined;
    return parsed as Abi;
  } catch {
    return undefined;
  }
}

async function lookup4byte(selector: string, signal?: AbortSignal): Promise<string | null> {
  try {
    const res = await fetch(`https://api.4byte.sourcify.dev/signature-database/v1/lookup?function=${selector}`, {
      signal,
    });
    if (!res.ok) return null;
    const data = await res.json();
    const results = data?.result?.function?.[selector];
    if (!Array.isArray(results) || results.length === 0) return null;
    const sig = results[0].name;
    if (typeof sig !== "string") return null;
    const parenIndex = sig.indexOf("(");
    return parenIndex > 0 ? sig.slice(0, parenIndex) : sig;
  } catch {
    return null;
  }
}

///////////////////////////////////////////////////////////////////////////
//                           MAIN COMPONENT
///////////////////////////////////////////////////////////////////////////

export function Inspector() {
  const [hexInput, setHexInput] = useState("");
  const [abiInput, setAbiInput] = useState("");
  const [abiOpen, setAbiOpen] = useState(false);
  const [lookedUpName, setLookedUpName] = useState<string | null>(null);
  const [lookingUp, setLookingUp] = useState(false);
  const [inspectMode, setInspectMode] = useState(false);
  const [activeExample, setActiveExample] = useState<PolicyExample | null>(null);
  const [exampleDropdownOpen, setExampleDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const debouncedHex = useDebounce(hexInput, 300);
  const abi = useMemo(() => (activeExample?.abi ? activeExample.abi : parseAbi(abiInput)), [activeExample, abiInput]);

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

  const selectExample = useCallback((example: PolicyExample) => {
    setActiveExample(example);
    setHexInput(example.blob);
    if (example.abi) {
      setAbiInput(JSON.stringify(example.abi, null, 2));
      setAbiOpen(true);
    } else {
      setAbiInput("");
      setAbiOpen(false);
    }
    setExampleDropdownOpen(false);
  }, []);

  const clearExample = useCallback(() => {
    setActiveExample(null);
    setHexInput("");
    setAbiInput("");
    setAbiOpen(false);
  }, []);

  // Close dropdown on outside click.
  useEffect(() => {
    if (!exampleDropdownOpen) return;
    function handleClick(e: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setExampleDropdownOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [exampleDropdownOpen]);

  return (
    <div className="space-y-4">
      {/* Policy blob input */}
      <div>
        <div className="mb-1.5 flex items-center justify-between">
          <label htmlFor="policy-hex" className="text-sm font-medium text-fd-foreground">
            Policy Blob
          </label>
          {/* Examples dropdown */}
          <div ref={dropdownRef} className="relative">
            <button
              type="button"
              className="flex items-center gap-1 text-sm text-fd-muted-foreground hover:text-fd-foreground transition-colors"
              onClick={() => setExampleDropdownOpen(!exampleDropdownOpen)}
            >
              Examples
              <ChevronDown className={cn("size-3.5 transition-transform", exampleDropdownOpen && "rotate-180")} />
            </button>
            {exampleDropdownOpen && (
              <div className="absolute right-0 z-10 mt-1 w-48 rounded-lg border border-fd-border bg-fd-popover py-1 shadow-md">
                {EXAMPLES.map((example) => (
                  <button
                    key={example.name}
                    type="button"
                    className={cn(
                      "w-full px-3 py-1.5 text-left text-sm transition-colors",
                      "hover:bg-fd-accent hover:text-fd-accent-foreground",
                      activeExample?.name === example.name ? "text-fd-primary font-medium" : "text-fd-muted-foreground",
                    )}
                    onClick={() => selectExample(example)}
                  >
                    {example.name}
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Example banner */}
        {activeExample && (
          <div className="mb-1.5 flex items-center justify-between rounded-lg bg-fd-info px-3 py-2 text-sm text-fd-info-foreground ring-1 ring-fd-info-foreground/30">
            <span>
              <span className="font-semibold">Example:</span>{" "}
              <span className="text-fd-foreground">{activeExample.name}</span>
            </span>
            <button
              type="button"
              className="font-semibold transition-colors hover:text-fd-foreground"
              onClick={clearExample}
            >
              Clear
            </button>
          </div>
        )}

        <textarea
          id="policy-hex"
          className={cn(
            "w-full rounded-lg border bg-fd-card px-3 py-2 font-mono text-sm",
            "placeholder:text-fd-muted-foreground/50",
            "focus:outline-none focus:ring-2 focus:ring-inset focus:ring-fd-ring",
            "resize-y",
            activeExample && "cursor-default opacity-70",
            result && !result.ok ? "border-red-500/50" : "border-fd-border",
          )}
          rows={3}
          placeholder="0x01095ea7b3..."
          value={hexInput}
          onChange={(e) => setHexInput(e.target.value)}
          onPaste={handlePaste}
          readOnly={!!activeExample}
          spellCheck={false}
          autoComplete="off"
        />
      </div>

      {/* ABI input (collapsible) */}
      <Collapsible open={abiOpen} onOpenChange={activeExample ? undefined : setAbiOpen}>
        <CollapsibleTrigger
          className={cn(
            "flex items-center gap-1.5 text-sm text-fd-muted-foreground transition-colors",
            activeExample ? "cursor-default" : "hover:text-fd-foreground",
          )}
          disabled={!!activeExample}
        >
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
              activeExample && "cursor-default opacity-70",
            )}
            rows={4}
            placeholder='[{"type":"function","name":"approve",...}]'
            value={abiInput}
            onChange={(e) => setAbiInput(e.target.value)}
            readOnly={!!activeExample}
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
          <div className="mb-3 flex items-center gap-2">
            {(["Summary", "Inspect"] as const).map((label) => {
              const active = label === "Inspect" ? inspectMode : !inspectMode;
              return (
                <button
                  key={label}
                  type="button"
                  className={cn(
                    "rounded-md px-2.5 py-1 text-xs font-medium transition-colors",
                    active
                      ? "bg-fd-primary text-fd-primary-foreground"
                      : "text-fd-muted-foreground hover:text-fd-foreground",
                  )}
                  onClick={() => setInspectMode(label === "Inspect")}
                >
                  {label}
                </button>
              );
            })}
          </div>
          {inspectMode ? (
            <InspectView policy={result.policy} explained={result.explained} hex={result.hex} />
          ) : (
            <SummaryView policy={result.explained} functionName={resolvedName} />
          )}
        </div>
      )}
    </div>
  );
}

///////////////////////////////////////////////////////////////////////////
//                          SUMMARY VIEW
///////////////////////////////////////////////////////////////////////////

function formatOperands(rule: ExplainedRule): string {
  const op = rule.operator;
  if (op === "in" || op === "not in") return `{${rule.operands.join(", ")}}`;
  if (op.includes("between")) return `[${rule.operands.join(", ")}]`;
  return rule.operands.join(", ");
}

function SummaryView({ policy, functionName }: { policy: ExplainedPolicy; functionName: string | null }) {
  const fnName = functionName ?? policy.functionName ?? policy.selector;
  const params = policy.params.map((p) => (p.name ? `${p.type} ${p.name}` : p.type)).join(", ");

  const groupClauses: {
    constraint: ExplainedConstraint;
    rule: ExplainedRule;
  }[][] = policy.groups.map((group) =>
    group.constraints.flatMap((constraint) => constraint.rules.map((rule) => ({ constraint, rule }))),
  );

  return (
    <div className="space-y-3">
      {/* Signature */}
      <div className="rounded-lg border border-fd-border bg-fd-card px-4 py-3 font-mono text-sm">
        {policy.isSelectorless ? (
          <span className="text-fd-muted-foreground">No Selector</span>
        ) : (
          <>
            <code className="font-semibold text-fd-foreground">
              {fnName}({params})
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
                    <div className="absolute inset-y-0 left-[1px] w-px bg-fd-muted-foreground/40" />
                    <span className="relative z-10 -translate-x-[calc(50%-1px)] bg-fd-background px-1 text-[10px] font-semibold text-fd-info-foreground">
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
                    "absolute left-[1px] w-px bg-fd-muted-foreground/40",
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
//                          INSPECT VIEW
///////////////////////////////////////////////////////////////////////////

type TreeNode = {
  label: string;
  value: string;
  hex: string;
  span: Span;
  children?: TreeNode[];
};

function readU16(hex: string, byteOffset: number): number {
  return parseInt(hex.slice(byteOffset * 2, byteOffset * 2 + 4), 16);
}

function readU32(hex: string, byteOffset: number): number {
  return parseInt(hex.slice(byteOffset * 2, byteOffset * 2 + 8), 16);
}

function buildTree(policy: PolicyData, explained: ExplainedPolicy, rawHex: string): TreeNode[] {
  const cleanHex = rawHex.startsWith("0x") ? rawHex.slice(2) : rawHex;
  const sliceHex = (span: Span) => {
    const raw = cleanHex.slice(span.start * 2, span.end * 2);
    return raw.match(/.{2}/g)?.join(" ") ?? "";
  };

  const nodes: TreeNode[] = [];
  const headerByte = parseInt(cleanHex.slice(0, 2), 16);
  const version = headerByte & PF.VERSION_MASK;

  // Header.
  const headerSpan: Span = { start: 0, end: PF.HEADER_SIZE };
  const headerBits: string[] = [`v${version}`];
  if (policy.isSelectorless) headerBits.push("selectorless");
  nodes.push({
    label: "Header",
    value: headerBits.join(", "),
    hex: sliceHex(headerSpan),
    span: headerSpan,
  });

  // Selector.
  const selectorSpan: Span = { start: PF.SELECTOR_OFFSET, end: PF.SELECTOR_OFFSET + PF.SELECTOR_SIZE };
  const selectorLabel = policy.isSelectorless ? "zeroed" : policy.selector;
  const fnName = explained.functionName;
  nodes.push({
    label: "Selector",
    value: fnName ? `${selectorLabel} (${fnName})` : selectorLabel,
    hex: sliceHex(selectorSpan),
    span: selectorSpan,
  });

  // Descriptor length.
  const descLengthSpan: Span = { start: PF.DESC_LENGTH_OFFSET, end: PF.DESC_LENGTH_OFFSET + PF.DESC_LENGTH_SIZE };
  const descLength = readU16(cleanHex, PF.DESC_LENGTH_OFFSET);
  nodes.push({
    label: "Desc Length",
    value: String(descLength),
    hex: sliceHex(descLengthSpan),
    span: descLengthSpan,
  });

  // Descriptor.
  const descStart = PF.DESC_OFFSET;
  const descEnd = descStart + descLength;
  const descSpan: Span = { start: descStart, end: descEnd };
  // Descriptor header is the first 2 bytes (version + paramCount).
  const descHeaderEnd = descStart + 2;
  const descHeaderSpan: Span = { start: descStart, end: descHeaderEnd };
  const paramCount = explained.params.length;

  const descChildren: TreeNode[] = [
    {
      label: "Desc Header",
      value: `v${version}, ${paramCount} param${s(paramCount)}`,
      hex: sliceHex(descHeaderSpan),
      span: descHeaderSpan,
    },
  ];

  // Walk descriptor param nodes to derive individual param spans.
  let paramOffset = descHeaderEnd;
  for (let i = 0; i < paramCount; i++) {
    const ep = explained.params[i];
    const paramNodeEnd = skipDescNode(cleanHex, paramOffset);
    const paramSpan: Span = { start: paramOffset, end: paramNodeEnd };
    const typeLabel = ep?.type ?? `param(${i})`;
    const nameLabel = ep?.name ? ` ${ep.name}` : "";
    descChildren.push({
      label: `Param [${i}]`,
      value: `${typeLabel}${nameLabel}`,
      hex: sliceHex(paramSpan),
      span: paramSpan,
    });
    paramOffset = paramNodeEnd;
  }

  nodes.push({
    label: "Descriptor",
    value: `${paramCount} param${s(paramCount)}`,
    hex: sliceHex(descSpan),
    span: descSpan,
    children: descChildren,
  });

  // Group count.
  const groupCountStart = descEnd;
  const groupCountSpan: Span = { start: groupCountStart, end: groupCountStart + PF.GROUP_COUNT_SIZE };
  const groupCount = parseInt(cleanHex.slice(groupCountStart * 2, groupCountStart * 2 + 2), 16);
  nodes.push({
    label: "Group Count",
    value: String(groupCount),
    hex: sliceHex(groupCountSpan),
    span: groupCountSpan,
  });

  // Groups — walk the raw bytes to derive rule-level spans.
  let groupOffset = groupCountStart + PF.GROUP_COUNT_SIZE;
  for (let gi = 0; gi < groupCount; gi++) {
    const ruleCount = readU16(cleanHex, groupOffset);
    const groupBodySize = readU32(cleanHex, groupOffset + PF.GROUP_RULECOUNT_SIZE);
    const groupBodyStart = groupOffset + PF.GROUP_HEADER_SIZE;
    const groupEnd = groupBodyStart + groupBodySize;
    const groupSpan: Span = { start: groupOffset, end: groupEnd };

    const ruleCountSpan: Span = { start: groupOffset, end: groupOffset + PF.GROUP_RULECOUNT_SIZE };
    const groupSizeSpan: Span = {
      start: groupOffset + PF.GROUP_RULECOUNT_SIZE,
      end: groupOffset + PF.GROUP_HEADER_SIZE,
    };

    // Build explained rule summaries for display.
    const eg = explained.groups[gi];
    let explainedRuleIndex = 0;
    const explainedRules: { constraint: ExplainedConstraint; rule: ExplainedRule }[] = [];
    if (eg) {
      for (const c of eg.constraints) {
        for (const r of c.rules) {
          explainedRules.push({ constraint: c, rule: r });
        }
      }
    }

    const ruleNodes: TreeNode[] = [];
    let ruleOffset = groupBodyStart;
    for (let ri = 0; ri < ruleCount; ri++) {
      const ruleSize = readU16(cleanHex, ruleOffset);
      const ruleEnd = ruleOffset + ruleSize;
      const ruleSpan: Span = { start: ruleOffset, end: ruleEnd };

      const scopeOffset = ruleOffset + PF.RULE_SCOPE_OFFSET;
      const scopeValue = parseInt(cleanHex.slice(scopeOffset * 2, scopeOffset * 2 + 2), 16);
      const depthOffset = ruleOffset + PF.RULE_DEPTH_OFFSET;
      const depthValue = parseInt(cleanHex.slice(depthOffset * 2, depthOffset * 2 + 2), 16);
      const pathStart = ruleOffset + PF.RULE_PATH_OFFSET;
      const pathLength = depthValue * PF.PATH_STEP_SIZE;
      const pathEnd = pathStart + pathLength;
      const pathHex: Hex = `0x${cleanHex.slice(pathStart * 2, pathEnd * 2)}`;
      const opCodeOffset = pathEnd;
      const opCodeValue = parseInt(cleanHex.slice(opCodeOffset * 2, opCodeOffset * 2 + 2), 16);
      const dataLengthOffset = opCodeOffset + PF.RULE_OPCODE_SIZE;
      const dataStart = dataLengthOffset + PF.RULE_DATALENGTH_SIZE;
      const dataLength = readU16(cleanHex, dataLengthOffset);

      const info = explainedRules[explainedRuleIndex];
      explainedRuleIndex++;
      const summary = info
        ? `${info.constraint.pathLabel} ${info.rule.operator} ${formatOperands(info.rule)} : ${info.constraint.targetType}`
        : "";
      const opDisplay = info?.rule.operator ?? `0x${opCodeValue.toString(16).padStart(2, "0")}`;
      const dataValue = info
        ? `${formatOperands(info.rule)} : ${info.constraint.targetType}`
        : `0x${cleanHex.slice(dataStart * 2, (dataStart + dataLength) * 2)}`;

      ruleNodes.push({
        label: `Rule ${ri + 1}`,
        value: summary,
        hex: "",
        span: ruleSpan,
        children: [
          {
            label: "Rule Size",
            value: String(ruleSize),
            hex: sliceHex({ start: ruleOffset, end: ruleOffset + PF.RULE_SIZE_SIZE }),
            span: { start: ruleOffset, end: ruleOffset + PF.RULE_SIZE_SIZE },
          },
          {
            label: "Scope",
            value: scopeValue === 0 ? "context" : "calldata",
            hex: sliceHex({ start: scopeOffset, end: scopeOffset + 1 }),
            span: { start: scopeOffset, end: scopeOffset + 1 },
          },
          {
            label: "Path Depth",
            value: String(depthValue),
            hex: sliceHex({ start: depthOffset, end: depthOffset + 1 }),
            span: { start: depthOffset, end: depthOffset + 1 },
          },
          {
            label: "Path",
            value: `[${parsePathSteps(pathHex).join(", ")}]`,
            hex: sliceHex({ start: pathStart, end: pathEnd }),
            span: { start: pathStart, end: pathEnd },
          },
          {
            label: "OpCode",
            value: opDisplay,
            hex: sliceHex({ start: opCodeOffset, end: opCodeOffset + PF.RULE_OPCODE_SIZE }),
            span: { start: opCodeOffset, end: opCodeOffset + PF.RULE_OPCODE_SIZE },
          },
          {
            label: "Data Length",
            value: String(dataLength),
            hex: sliceHex({ start: dataLengthOffset, end: dataLengthOffset + PF.RULE_DATALENGTH_SIZE }),
            span: { start: dataLengthOffset, end: dataLengthOffset + PF.RULE_DATALENGTH_SIZE },
          },
          {
            label: "Data",
            value: dataValue,
            hex: sliceHex({ start: dataStart, end: dataStart + dataLength }),
            span: { start: dataStart, end: dataStart + dataLength },
          },
        ],
      });

      ruleOffset = ruleEnd;
    }

    nodes.push({
      label: `Group ${gi + 1}`,
      value: `${ruleCount} rule${s(ruleCount)}, ${groupBodySize} byte${s(groupBodySize)}`,
      hex: sliceHex({ start: ruleCountSpan.start, end: groupSizeSpan.end }),
      span: groupSpan,
      children: [
        {
          label: "Rule Count",
          value: String(ruleCount),
          hex: sliceHex(ruleCountSpan),
          span: ruleCountSpan,
        },
        {
          label: "Group Size",
          value: String(groupBodySize),
          hex: sliceHex(groupSizeSpan),
          span: groupSizeSpan,
        },
        ...ruleNodes,
      ],
    });

    groupOffset = groupEnd;
  }

  return nodes;
}

function skipDescNode(hex: string, byteOffset: number): number {
  const typeCode = parseInt(hex.slice(byteOffset * 2, byteOffset * 2 + 2), 16);
  if (lookupTypeCode(typeCode).typeClass === "elementary") return byteOffset + DF.TYPECODE_SIZE;
  const meta = parseInt(
    hex.slice((byteOffset + DF.TYPECODE_SIZE) * 2, (byteOffset + DF.TYPECODE_SIZE + DF.COMPOSITE_META_SIZE) * 2),
    16,
  );
  return byteOffset + (meta & DF.META_NODE_LENGTH_MASK);
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

function InspectView({ policy, explained, hex }: { policy: PolicyData; explained: ExplainedPolicy; hex: string }) {
  const tree = useMemo(() => buildTree(policy, explained, hex), [policy, explained, hex]);
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

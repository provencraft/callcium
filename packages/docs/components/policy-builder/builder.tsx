"use client";

import { PolicyCoder, TypeCode, hexToBytes, lookupQuantifier, Quantifier } from "@callcium/sdk";
import { ChevronDown, Copy, Check, Plus, Trash2, ArrowRight, AlertTriangle, Info as InfoIcon } from "lucide-react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatAbiItem } from "viem/utils";
import type { Hex, Issue, ScalarValue, TypeInfo } from "@callcium/sdk";
import type { AbiFunction } from "viem";
import { EXAMPLES, type BuilderExample } from "./examples";
import { ErrorBox } from "@/components/ui/error-box";
import { MonoInput } from "@/components/ui/mono-input";
import { MonoTextarea } from "@/components/ui/mono-textarea";
import { PillToggle } from "@/components/ui/pill-toggle";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { lookup4byte, descriptorToTypes } from "@/lib/abi";
import { parseAbiJson } from "@/lib/abi";
import { CONTEXT_PROPERTY_COUNT, contextPropertyType, formatPath } from "@/lib/format-path";
import { useDebounce } from "@/lib/use-debounce";
import { cn } from "@/lib/utils";
import {
  createSession,
  addConstraint,
  removeConstraint,
  addGroup,
  removeGroup,
  getOperatorOptions,
  getOperatorLabel,
  type BuilderSession,
  type ConstraintConfig,
  type ConstraintInput,
  type OperatorRule,
  type ParamNode,
} from "@/tools/policy-builder";

// Both context properties are 32-byte elementary types despite address being 20 bytes on-chain.
const CTX_ADDRESS: TypeInfo = { typeCode: TypeCode.ADDRESS, isDynamic: false, staticSize: 32 };
const CTX_UINT256: TypeInfo = { typeCode: TypeCode.UINT_MAX, isDynamic: false, staticSize: 32 };

///////////////////////////////////////////////////////////////////////////
// Quantifier options
///////////////////////////////////////////////////////////////////////////

const QUANTIFIER_OPTIONS = [
  {
    value: Quantifier.ALL_OR_EMPTY,
    label: lookupQuantifier(Quantifier.ALL_OR_EMPTY).label,
    desc: "all elements must pass\nempty array → pass",
  },
  {
    value: Quantifier.ALL,
    label: lookupQuantifier(Quantifier.ALL).label,
    desc: "all elements must pass\nempty array → fail",
  },
  {
    value: Quantifier.ANY,
    label: lookupQuantifier(Quantifier.ANY).label,
    desc: "at least one must pass\nempty array → fail",
  },
];

///////////////////////////////////////////////////////////////////////////
// Main component
///////////////////////////////////////////////////////////////////////////

export function Builder() {
  const searchParams = useSearchParams();
  const [session, setSession] = useState<BuilderSession | null>(null);
  const [signatureInput, setSignatureInput] = useState("");
  const [isSelectorless, setIsSelectorless] = useState(false);
  const [copied, setCopied] = useState(false);
  const [activeExample, setActiveExample] = useState<BuilderExample | null>(null);
  const [exampleDropdownOpen, setExampleDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const [inputMode, setInputMode] = useState<"signature" | "abi">("signature");
  const [abiInput, setAbiInput] = useState("");
  const [selectedFnSig, setSelectedFnSig] = useState("");

  const abiFunctions = useMemo<AbiFunction[] | Error>(() => {
    if (!abiInput.trim()) return [];
    const parsed = parseAbiJson(abiInput);
    if (parsed instanceof Error) return parsed;
    return parsed.filter((item): item is AbiFunction => item?.type === "function");
  }, [abiInput]);

  const debouncedSignature = useDebounce(signatureInput, 300);

  useEffect(() => {
    const sig = debouncedSignature.trim();
    if (!sig || activeExample) return;
    const s = createSession(sig, { selectorless: isSelectorless });
    setSession(s);
  }, [debouncedSignature, isSelectorless, activeExample]);

  // Load from query param on mount — replay pattern.
  useEffect(() => {
    const policyHex = searchParams.get("policy");
    if (!policyHex) return;
    try {
      const decoded = PolicyCoder.decode(policyHex as Hex);
      const desc = hexToBytes(decoded.descriptor);
      const types = descriptorToTypes(desc);
      if (decoded.isSelectorless) {
        setSignatureInput(types);
        setIsSelectorless(true);
        setSession(createSession(types, { selectorless: true }));
      } else {
        // Use types immediately, then look up the function name async.
        const fallbackSig = `unknown(${types})`;
        setSignatureInput(fallbackSig);
        setSession(createSession(fallbackSig));
        void lookup4byte(decoded.selector).then((name) => {
          if (name) {
            const sig = `${name}(${types})`;
            setSignatureInput(sig);
            setSession(createSession(sig));
          }
        });
      }
    } catch {
      // Invalid hex — ignore.
    }
  }, [searchParams]);

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

  const handleSelectExample = useCallback((example: BuilderExample) => {
    setActiveExample(example);
    setSignatureInput(example.signature);
    setIsSelectorless(example.selectorless ?? false);
    let s = createSession(example.signature, { selectorless: example.selectorless });
    for (const { groupIndex, config } of example.constraints) {
      while (s.groups.length <= groupIndex) {
        s = addGroup(s);
      }
      s = addConstraint(s, groupIndex, config);
    }
    setSession(s);
    setExampleDropdownOpen(false);
  }, []);

  const handleClear = useCallback(() => {
    setActiveExample(null);
    setSignatureInput("");
    setIsSelectorless(false);
    setSession(null);
  }, []);

  const handleCopy = useCallback(() => {
    if (!session?.hex) return;
    void navigator.clipboard.writeText(session.hex);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }, [session?.hex]);

  const handleAddConstraint = useCallback(
    (groupIndex: number, config: ConstraintInput) => {
      if (!session) return;
      setSession(addConstraint(session, groupIndex, config));
    },
    [session],
  );

  const handleRemoveConstraint = useCallback(
    (groupIndex: number, constraintIndex: number) => {
      if (!session) return;
      setSession(removeConstraint(session, groupIndex, constraintIndex));
    },
    [session],
  );

  const handleAddGroup = useCallback(() => {
    if (!session) return;
    setSession(addGroup(session));
  }, [session]);

  const handleRemoveGroup = useCallback(
    (groupIndex: number) => {
      if (!session) return;
      setSession(removeGroup(session, groupIndex));
    },
    [session],
  );

  return (
    <div className="space-y-4">
      {/* Signature input */}
      <div>
        <div className="mb-2 flex items-center justify-between">
          <PillToggle
            value={inputMode}
            options={[
              { value: "signature", label: "Signature" },
              { value: "abi", label: "ABI" },
            ]}
            onChange={setInputMode}
          />

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
                    onClick={() => handleSelectExample(example)}
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
          <div className="mb-2 flex items-center justify-between rounded-lg bg-fd-info px-3 py-2 text-sm text-fd-info-foreground ring-1 ring-fd-info-foreground/30">
            <span>
              <span className="font-semibold">Example:</span>{" "}
              <span className="text-fd-foreground">{activeExample.name}</span>
            </span>
            <button
              type="button"
              className="font-semibold transition-colors hover:text-fd-foreground"
              onClick={handleClear}
            >
              Clear
            </button>
          </div>
        )}

        {inputMode === "signature" ? (
          <div className="space-y-2">
            <label className="flex items-center gap-1.5 text-sm text-fd-muted-foreground">
              <input
                type="checkbox"
                checked={isSelectorless}
                onChange={(e) => setIsSelectorless(e.target.checked)}
                className="rounded"
                disabled={!!activeExample}
              />
              Selectorless
            </label>

            <MonoInput
              id="signature-input"
              className={cn(activeExample && "cursor-default opacity-70", session?.error && "border-red-500/50")}
              placeholder={isSelectorless ? "address,uint256" : "transfer(address to, uint256 amount)"}
              value={signatureInput}
              onChange={(e) => setSignatureInput(e.target.value)}
              readOnly={!!activeExample}
            />
          </div>
        ) : (
          <div className="space-y-2">
            <MonoTextarea
              rows={4}
              placeholder='[{"type":"function","name":"approve","inputs":[...]}]'
              value={abiInput}
              onChange={(e) => setAbiInput(e.target.value)}
            />

            {Array.isArray(abiFunctions) && abiFunctions.length > 0 && (
              <Select
                value={selectedFnSig}
                onValueChange={(sig) => {
                  setSelectedFnSig(sig);
                  setActiveExample(null);
                  setIsSelectorless(false);
                  setSignatureInput(sig);
                }}
              >
                <SelectTrigger className="w-full font-mono">
                  <SelectValue placeholder="Select function" />
                </SelectTrigger>
                <SelectContent>
                  {abiFunctions.map((fn) => {
                    const sig = formatAbiItem(fn, { includeName: true });
                    return (
                      <SelectItem key={sig} value={sig} className="font-mono">
                        {sig}
                      </SelectItem>
                    );
                  })}
                </SelectContent>
              </Select>
            )}

            {abiInput.trim() && (
              <>
                {abiFunctions instanceof Error && <ErrorBox>Invalid ABI: {abiFunctions.message}</ErrorBox>}
                {Array.isArray(abiFunctions) && abiFunctions.length === 0 && (
                  <ErrorBox>No functions found in ABI.</ErrorBox>
                )}
              </>
            )}
          </div>
        )}

        {session?.error && <ErrorBox className="mt-1.5">{session.error}</ErrorBox>}
      </div>

      {/* Parameter tree + constraint management */}
      {session && !session.error && (
        <>
          {/* Constraint groups */}
          {session.groups.map((group, gi) => (
            <div key={group.id}>
              {gi > 0 && (
                <div className="flex items-center gap-2 py-2">
                  <div className="h-px flex-1 bg-fd-border" />
                  <span className="text-xs font-semibold text-fd-info-foreground">OR</span>
                  <div className="h-px flex-1 bg-fd-border" />
                </div>
              )}
              <div className="rounded-lg border border-fd-border bg-fd-card">
                <div className="flex items-center justify-between border-b border-fd-border px-3 py-2">
                  <span className="text-sm font-medium text-fd-foreground">
                    Group {gi + 1}
                    {group.constraints.length > 0 && (
                      <span className="ml-1 text-fd-muted-foreground">
                        ({group.constraints.length} constraint{group.constraints.length !== 1 ? "s" : ""})
                      </span>
                    )}
                  </span>
                  {session.groups.length > 1 && (
                    <button
                      type="button"
                      className="text-fd-muted-foreground hover:text-red-500 transition-colors"
                      onClick={() => handleRemoveGroup(gi)}
                    >
                      <Trash2 className="size-3.5" />
                    </button>
                  )}
                </div>

                {group.constraints.map((config, ci) => {
                  const rowIssues = session.issues.filter((i) => i.groupIndex === gi && i.constraintIndex === ci);
                  return (
                    <ConstraintRow
                      key={config.id}
                      config={config}
                      issues={rowIssues}
                      params={session.params}
                      onRemove={() => handleRemoveConstraint(gi, ci)}
                    />
                  );
                })}

                {/* Add constraint form */}
                <AddConstraintForm
                  session={session}
                  groupIndex={gi}
                  onAdd={(config) => handleAddConstraint(gi, config)}
                />
              </div>
            </div>
          ))}

          {/* Add group button */}
          <button
            type="button"
            className="flex items-center gap-1.5 text-sm text-fd-muted-foreground hover:text-fd-foreground transition-colors"
            onClick={handleAddGroup}
          >
            <Plus className="size-3.5" />
            Add OR group
          </button>

          {/* Validation issues */}
          {session.errors.length > 0 && (
            <div className="space-y-1">
              {session.errors.map((error, i) => (
                // oxlint-disable-next-line react/no-array-index-key
                <ErrorBox key={i}>{error}</ErrorBox>
              ))}
            </div>
          )}

          {/* Output */}
          {session.hex && (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-fd-foreground">Policy Blob</span>
                <div className="flex items-center gap-3">
                  <Link
                    href={`/policy-inspector?policy=${encodeURIComponent(session.hex)}`}
                    className="text-sm text-fd-muted-foreground hover:text-fd-foreground transition-colors"
                  >
                    Inspector <ArrowRight className="inline size-3" />
                  </Link>
                  <Link
                    href={`/policy-enforcer?policy=${encodeURIComponent(session.hex)}`}
                    className="text-sm text-fd-muted-foreground hover:text-fd-foreground transition-colors"
                  >
                    Enforcer <ArrowRight className="inline size-3" />
                  </Link>
                </div>
              </div>
              <div className="relative">
                <MonoTextarea className="resize-none pr-9" rows={3} value={session.hex} readOnly />
                <button
                  type="button"
                  className="absolute top-2 right-3 rounded-md p-1 text-fd-muted-foreground hover:text-fd-foreground transition-colors"
                  onClick={handleCopy}
                >
                  {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
                </button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}

function pathKey(path: number[]): string {
  return JSON.stringify(path);
}

function isLeafNode(node: ParamNode): boolean {
  return !node.children && !node.element;
}

/** Resolve the Solidity type string for a constraint's target. */
function resolveTargetType(config: ConstraintConfig, params: ParamNode[]): string | null {
  if (config.scope === "context") {
    return config.contextProperty ? contextPropertyType(config.contextProperty) : null;
  }
  if (!config.path || config.path.length === 0) return null;
  let node: ParamNode | undefined = params[config.path[0]];
  for (let i = 1; i < config.path.length && node; i++) {
    if (node.children) node = node.children[config.path[i]];
    else if (node.element) node = node.element;
    else return null;
  }
  return node?.type ?? null;
}

///////////////////////////////////////////////////////////////////////////
// Constraint row (displays an existing constraint)
///////////////////////////////////////////////////////////////////////////

function ConstraintRow({
  config,
  issues,
  params,
  onRemove,
}: {
  config: ConstraintConfig;
  issues: Issue[];
  params: ParamNode[];
  onRemove: () => void;
}) {
  const label = formatPath({
    scope: config.scope,
    path: config.path,
    quantifier: config.quantifier,
    contextProperty: config.contextProperty,
    params,
  });

  const targetType = resolveTargetType(config, params);
  const isSingleRule = config.rules.length === 1;

  return (
    <div className="border-b border-fd-border/30 px-3 py-2">
      <div className="flex items-center justify-between text-sm">
        <div className="flex items-baseline gap-1.5 font-mono">
          <span className="text-fd-foreground">{label}</span>
          {isSingleRule ? (
            <>
              <span className="text-fd-muted-foreground">{getOperatorLabel(config.rules[0].operator)}</span>
              <span className="text-fd-foreground break-all">
                {config.rules[0].values.map((v) => String(v)).join(", ")}
              </span>
              {targetType && <span className="text-fd-muted-foreground">: {targetType}</span>}
            </>
          ) : (
            targetType && <span className="text-fd-muted-foreground">: {targetType}</span>
          )}
        </div>
        <button
          type="button"
          className="text-fd-muted-foreground hover:text-red-500 transition-colors"
          onClick={onRemove}
        >
          <Trash2 className="size-3.5" />
        </button>
      </div>
      {!isSingleRule &&
        config.rules.map((rule, ri) => (
          <div
            // oxlint-disable-next-line react/no-array-index-key
            key={ri}
            className="ml-4 flex items-baseline gap-1.5 font-mono text-sm"
          >
            <span className="min-w-[2ch] text-fd-muted-foreground">{getOperatorLabel(rule.operator)}</span>
            <span className="text-fd-foreground break-all">{rule.values.map((v) => String(v)).join(", ")}</span>
          </div>
        ))}
      {issues.map((issue, i) => (
        <div
          // oxlint-disable-next-line react/no-array-index-key
          key={i}
          className={cn(
            "mt-0.5 flex items-start gap-1.5 text-xs",
            issue.severity === "error" && "text-red-700 dark:text-red-300",
            issue.severity === "warning" && "text-fd-secondary-foreground",
            issue.severity === "info" && "text-fd-info-foreground",
          )}
        >
          {issue.severity === "warning" ? (
            <AlertTriangle className="mt-0.5 size-3 shrink-0" />
          ) : (
            <InfoIcon className="mt-0.5 size-3 shrink-0" />
          )}
          <span>{issue.message}</span>
        </div>
      ))}
    </div>
  );
}

///////////////////////////////////////////////////////////////////////////
// Add constraint form (inline within a group)
///////////////////////////////////////////////////////////////////////////

/** Strip error codes and hex paths from structural error messages. */
function humanizeError(error: string): string {
  // "DUPLICATE_PATH: Duplicate path 0x0001 in the same group." → "Duplicate path in the same group."
  const stripped = error.replace(/^[A-Z_]+:\s*/, "");
  return stripped
    .replace(/\s*0x[0-9a-fA-F]+\s*/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function parseStaticArrayLength(type: string): number | null {
  const match = type.match(/\[(\d+)]$/);
  return match ? Number(match[1]) : null;
}

function parseConstraintValues(operator: string, valueInput: string, typeInfo: TypeInfo | null): ScalarValue[] | null {
  try {
    if (operator === "isIn" || operator === "notIn") {
      const parts = valueInput
        .split(",")
        .map((v) => v.trim())
        .filter(Boolean);
      if (parts.length === 0) return null;
      return parts.map((v) => (v.startsWith("0x") ? v : BigInt(v)));
    }
    if (operator === "between" || operator === "lengthBetween") {
      const parts = valueInput.split(",").map((v) => v.trim());
      if (parts.length < 2 || !parts[0] || !parts[1]) return null;
      return [BigInt(parts[0]), BigInt(parts[1])];
    }
    if (typeInfo?.typeCode === TypeCode.ADDRESS) {
      const trimmed = valueInput.trim();
      return trimmed ? [trimmed] : null;
    }
    if (typeInfo?.typeCode === TypeCode.BOOL) {
      const trimmed = valueInput.trim().toLowerCase();
      return trimmed === "true" || trimmed === "false" ? [trimmed === "true"] : null;
    }
    const trimmed = valueInput.trim();
    if (!trimmed) return null;
    return [BigInt(trimmed)];
  } catch {
    return null;
  }
}

/** Return a placeholder string for the value input based on operator and type. */
function valuePlaceholder(operator: string, typeInfo: TypeInfo | null): string | undefined {
  if (operator === "isIn" || operator === "notIn") return "value1,value2,...";
  if (operator === "between" || operator === "lengthBetween") return "min,max";
  if (typeInfo?.typeCode === TypeCode.ADDRESS) return "0x...";
  if (typeInfo?.typeCode === TypeCode.BOOL) return "true / false";
  return undefined;
}

/** Assemble the full rules list from committed rules plus the in-progress draft (if valid). */
function resolveRules(
  rules: OperatorRule[],
  operator: string,
  valueInput: string,
  typeInfo: TypeInfo | null,
): OperatorRule[] {
  const result = [...rules];
  if (operator) {
    const values = parseConstraintValues(operator, valueInput, typeInfo);
    if (values) result.push({ operator, values });
  }
  return result;
}

function AddConstraintForm({
  session,
  groupIndex,
  onAdd,
}: {
  session: BuilderSession;
  groupIndex: number;
  onAdd: (config: ConstraintInput) => void;
}) {
  const [scope, setScope] = useState<"calldata" | "context">("calldata");
  const [selectedParam, setSelectedParam] = useState<number | null>(null);
  const [selectedField, setSelectedField] = useState<number[]>([]);
  const [contextProperty, setContextProperty] = useState<ConstraintConfig["contextProperty"] | "">("");
  const [operator, setOperator] = useState("");
  const [valueInput, setValueInput] = useState("");
  const [quantifier, setQuantifier] = useState<number | undefined>(undefined);
  const [arrayMode, setArrayMode] = useState<"quantified" | "index">("quantified");
  const [arrayIndex, setArrayIndex] = useState("");
  const [postArrayField, setPostArrayField] = useState<number[]>([]);
  const [expanded, setExpanded] = useState(false);
  const [rules, setRules] = useState<OperatorRule[]>([]);

  const group = session.groups[groupIndex];

  const usedContextProps = useMemo(() => {
    const used = new Set<string>();
    for (const c of group.constraints) {
      if (c.scope === "context" && c.contextProperty) used.add(c.contextProperty);
    }
    return used;
  }, [group]);

  const usedCalldataPaths = useMemo(() => {
    const used = new Set<string>();
    for (const c of group.constraints) {
      if (c.scope === "calldata" && c.path) used.add(pathKey(c.path));
    }
    return used;
  }, [group]);

  const hasAvailableContext = usedContextProps.size < CONTEXT_PROPERTY_COUNT;
  const hasAvailableCalldata = useMemo(() => {
    function hasUnusedLeaf(nodes: ParamNode[], prefix: number[], used: Set<string>): boolean {
      for (const node of nodes) {
        const path = [...prefix, node.index];
        if (node.children) {
          if (hasUnusedLeaf(node.children, path, used)) return true;
        } else if (!used.has(pathKey(path))) {
          return true;
        }
      }
      return false;
    }
    return hasUnusedLeaf(session.params, [], usedCalldataPaths);
  }, [session.params, usedCalldataPaths]);

  const arrayNode = useMemo(() => {
    if (scope !== "calldata" || selectedParam === null) return null;
    let node: ParamNode = session.params[selectedParam];
    for (const fieldIndex of selectedField) {
      if (node.children) node = node.children[fieldIndex];
      else if (node.element) node = node.element;
      if (!node) return null;
    }
    return node.element ? node : null;
  }, [scope, selectedParam, selectedField, session.params]);

  const staticArrayLength = useMemo(() => (arrayNode ? parseStaticArrayLength(arrayNode.type) : null), [arrayNode]);

  const resolvedElement = useMemo(() => {
    if (!arrayNode) return null;
    if (arrayMode === "quantified" && quantifier === undefined) return null;
    if (arrayMode === "index" && !/^\d+$/.test(arrayIndex)) return null;
    return arrayNode.element;
  }, [arrayNode, arrayMode, quantifier, arrayIndex]);

  const targetTypeInfo = useMemo<TypeInfo | null>(() => {
    if (scope === "context") {
      if (!contextProperty) return null;
      return contextProperty === "msgSender" || contextProperty === "txOrigin" ? CTX_ADDRESS : CTX_UINT256;
    }
    if (selectedParam === null || !session.params[selectedParam]) return null;
    let node: ParamNode = session.params[selectedParam];
    for (const fieldIndex of selectedField) {
      if (node.children) {
        node = node.children[fieldIndex];
      } else if (node.element) {
        node = node.element;
      }
      if (!node) return null;
    }
    // When array access targets elements (quantified or indexed), resolve through element and post-array fields.
    if (node.element) {
      const hasArrayAccess =
        (arrayMode === "quantified" && quantifier !== undefined) || (arrayMode === "index" && /^\d+$/.test(arrayIndex));
      if (hasArrayAccess) {
        let resolved: ParamNode = node.element;
        // If element is a tuple, require field selection before resolving.
        if (resolved.children && postArrayField.length === 0) return null;
        for (const fieldIndex of postArrayField) {
          if (resolved.children) {
            resolved = resolved.children[fieldIndex];
          } else {
            break;
          }
          if (!resolved) return null;
        }
        return resolved.typeInfo;
      }
      // Array selected but no access mode chosen yet — don't resolve.
      return null;
    }
    return node.typeInfo;
  }, [
    scope,
    selectedParam,
    selectedField,
    contextProperty,
    quantifier,
    arrayMode,
    arrayIndex,
    postArrayField,
    session.params,
  ]);

  const operatorOptions = useMemo(() => {
    if (!targetTypeInfo) return [];
    const all = getOperatorOptions(targetTypeInfo);
    const usedOps = new Set(rules.map((r) => r.operator));
    return all.filter((op) => !usedOps.has(op.value));
  }, [targetTypeInfo, rules]);

  const debouncedValue = useDebounce(valueInput, 300);
  const validIndex = /^\d+$/.test(arrayIndex);

  const indexValid =
    !arrayNode ||
    arrayMode === "quantified" ||
    (validIndex && (staticArrayLength === null || Number(arrayIndex) < staticArrayLength));

  const constraintPath = useMemo(() => {
    if (selectedParam === null) return [];
    const base = [selectedParam, ...selectedField];
    if (arrayNode && arrayMode === "index" && validIndex) {
      base.push(Number(arrayIndex));
    }
    base.push(...postArrayField);
    return base;
  }, [selectedParam, selectedField, arrayNode, arrayMode, validIndex, arrayIndex, postArrayField]);

  const previewResult = useMemo<{ errors: string[]; issues: Issue[] } | null>(() => {
    const candidateRules = resolveRules(rules, operator, debouncedValue, targetTypeInfo);
    if (candidateRules.length === 0) return null;

    const path = constraintPath;
    const config: ConstraintInput = {
      scope,
      ...(scope === "calldata" ? { path } : contextProperty ? { contextProperty } : {}),
      rules: candidateRules,
      ...(arrayMode === "quantified" && quantifier !== undefined ? { quantifier } : {}),
    };

    const preview = addConstraint(session, groupIndex, config);
    const draftIndex = session.groups[groupIndex].constraints.length;
    return {
      errors: preview.errors,
      issues: preview.issues.filter((i) => i.groupIndex === groupIndex && i.constraintIndex === draftIndex),
    };
  }, [
    scope,
    constraintPath,
    contextProperty,
    operator,
    debouncedValue,
    quantifier,
    arrayMode,
    targetTypeInfo,
    rules,
    session,
    groupIndex,
  ]);

  const hasValidDraft = operator !== "" && parseConstraintValues(operator, valueInput, targetTypeInfo) !== null;
  const canAdd =
    indexValid &&
    (rules.length > 0 || hasValidDraft) &&
    previewResult !== null &&
    previewResult.errors.length === 0 &&
    !previewResult.issues.some((i) => i.severity === "error");

  const handleAddOperator = useCallback(() => {
    const values = parseConstraintValues(operator, valueInput, targetTypeInfo);
    if (!values || !operator) return;
    setRules((prev) => [...prev, { operator, values }]);
    setOperator("");
    setValueInput("");
  }, [operator, valueInput, targetTypeInfo]);

  const handleSubmit = useCallback(() => {
    if (!canAdd) return;
    const finalRules = resolveRules(rules, operator, valueInput, targetTypeInfo);
    if (finalRules.length === 0) return;

    const path = constraintPath;
    const config: ConstraintInput = {
      scope,
      ...(scope === "calldata" ? { path } : contextProperty ? { contextProperty } : {}),
      rules: finalRules,
      ...(arrayMode === "quantified" && quantifier !== undefined ? { quantifier } : {}),
    };

    onAdd(config);
    setRules([]);
    setOperator("");
    setValueInput("");
    setExpanded(false);
  }, [
    scope,
    constraintPath,
    contextProperty,
    operator,
    valueInput,
    quantifier,
    arrayMode,
    targetTypeInfo,
    rules,
    canAdd,
    onAdd,
  ]);

  if (!expanded) {
    if (!hasAvailableCalldata && !hasAvailableContext) return null;
    return (
      <button
        type="button"
        className="flex w-full items-center gap-1.5 px-3 py-2 text-sm text-fd-muted-foreground hover:text-fd-foreground transition-colors"
        onClick={() => {
          if (hasAvailableCalldata) setScope("calldata");
          else setScope("context");
          setExpanded(true);
        }}
      >
        <Plus className="size-3.5" />
        Add constraint
      </button>
    );
  }

  return (
    <div className="border-t border-fd-border/30 px-3 py-2 space-y-2">
      {/* First row: path controls + first operator/value inline. */}
      <div className="flex flex-wrap items-end gap-2">
        {/* Path controls */}
        <div className="flex flex-col items-start gap-1">
          <PillToggle
            value={scope}
            options={[
              { value: "calldata", label: "calldata" },
              { value: "context", label: "context" },
            ]}
            onChange={setScope}
            disabled={rules.length > 0 || !hasAvailableCalldata || !hasAvailableContext}
          />
          {scope === "calldata" ? (
            <Select
              value={selectedParam !== null ? String(selectedParam) : ""}
              onValueChange={(v) => {
                setSelectedParam(v ? Number(v) : null);
                setSelectedField([]);
                setOperator("");
                setArrayIndex("");
                setQuantifier(undefined);
                setPostArrayField([]);
              }}
              disabled={rules.length > 0}
            >
              <SelectTrigger className="w-64 shrink-0">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {session.params.map((p, i) => {
                  if (isLeafNode(p) && usedCalldataPaths.has(pathKey([i]))) return null;
                  return (
                    // oxlint-disable-next-line react/no-array-index-key
                    <SelectItem key={i} value={String(i)}>
                      {p.name ? `${p.name}: ${p.type}` : `arg(${i}): ${p.type}`}
                    </SelectItem>
                  );
                })}
              </SelectContent>
            </Select>
          ) : (
            <Select
              value={contextProperty}
              onValueChange={(v) => {
                setContextProperty(v as ConstraintConfig["contextProperty"]);
                setOperator("");
              }}
              disabled={rules.length > 0}
            >
              <SelectTrigger className="w-64 shrink-0">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {!usedContextProps.has("msgSender") && <SelectItem value="msgSender">msg.sender</SelectItem>}
                {!usedContextProps.has("msgValue") && <SelectItem value="msgValue">msg.value</SelectItem>}
                {!usedContextProps.has("blockTimestamp") && (
                  <SelectItem value="blockTimestamp">block.timestamp</SelectItem>
                )}
                {!usedContextProps.has("blockNumber") && <SelectItem value="blockNumber">block.number</SelectItem>}
                {!usedContextProps.has("chainId") && <SelectItem value="chainId">chain.id</SelectItem>}
                {!usedContextProps.has("txOrigin") && <SelectItem value="txOrigin">tx.origin</SelectItem>}
              </SelectContent>
            </Select>
          )}
        </div>

        {/* Tuple field selection (inline) — hidden when path is locked. */}
        {scope === "calldata" &&
          selectedParam !== null &&
          session.params[selectedParam]?.children &&
          !arrayNode &&
          rules.length === 0 && (
            <FieldSelector
              node={session.params[selectedParam]}
              selectedPath={selectedField}
              onSelect={setSelectedField}
              usedPaths={usedCalldataPaths}
              pathPrefix={[selectedParam]}
            />
          )}

        {/* Array access — toggle stacked above its input */}
        {scope === "calldata" && arrayNode && (
          <div className="flex flex-col items-start gap-1">
            <PillToggle
              value={arrayMode}
              options={[
                { value: "quantified", label: "quantified" },
                { value: "index", label: "index" },
              ]}
              onChange={(mode) => {
                setArrayMode(mode);
                setPostArrayField([]);
              }}
              disabled={rules.length > 0}
            />
            {arrayMode === "quantified" ? (
              <Select
                value={quantifier !== undefined ? String(quantifier) : ""}
                onValueChange={(v) => setQuantifier(v ? Number(v) : undefined)}
                disabled={rules.length > 0}
              >
                <SelectTrigger className="w-42">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {QUANTIFIER_OPTIONS.map((q) => (
                    <SelectItem key={q.value} value={String(q.value)} description={q.desc}>
                      {q.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            ) : (
              <MonoInput
                inputMode="numeric"
                className="w-32"
                placeholder={staticArrayLength !== null ? `0\u2013${staticArrayLength - 1}` : undefined}
                value={arrayIndex}
                onChange={(e) => setArrayIndex(e.target.value)}
                disabled={rules.length > 0}
              />
            )}
          </div>
        )}

        {/* Post-array tuple field (inline) — hidden when path is locked. */}
        {resolvedElement?.children && rules.length === 0 && (
          <FieldSelector
            node={resolvedElement}
            selectedPath={postArrayField}
            onSelect={setPostArrayField}
            usedPaths={usedCalldataPaths}
            pathPrefix={
              selectedParam !== null
                ? [
                    selectedParam,
                    ...selectedField,
                    ...(arrayMode === "index" && validIndex ? [Number(arrayIndex)] : []),
                  ]
                : []
            }
          />
        )}

        {/* Operator, value, and buttons — all visible once target is selected. */}
        {targetTypeInfo && (
          <>
            <div className="flex flex-col items-start gap-1">
              {rules.length === 0 && <span className="text-xs text-fd-muted-foreground">operator</span>}
              <Select value={operator} onValueChange={setOperator}>
                <SelectTrigger className="w-40 shrink-0">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {operatorOptions.map((op) => (
                    <SelectItem key={op.value} value={op.value}>
                      {op.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="flex min-w-30 flex-1 flex-col items-start gap-1">
              {rules.length === 0 && (
                <label htmlFor="constraint-value" className="text-xs text-fd-muted-foreground">
                  value
                </label>
              )}
              <MonoInput
                id="constraint-value"
                placeholder={valuePlaceholder(operator, targetTypeInfo)}
                value={valueInput}
                onChange={(e) => setValueInput(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && canAdd && handleSubmit()}
              />
            </div>
            <button
              type="button"
              disabled={!hasValidDraft}
              className={cn(
                "flex h-9 items-center gap-1 text-sm transition-colors",
                hasValidDraft
                  ? "text-fd-muted-foreground hover:text-fd-foreground"
                  : "text-fd-muted-foreground/40 cursor-not-allowed",
              )}
              onClick={handleAddOperator}
            >
              <Plus className="size-3.5" />
              Operator
            </button>
            <button
              type="button"
              className="h-9 shrink-0 rounded-lg border border-fd-border px-3 py-1.5 text-sm text-fd-muted-foreground hover:text-fd-foreground transition-colors"
              onClick={() => {
                setRules([]);
                setOperator("");
                setValueInput("");
                setExpanded(false);
              }}
            >
              Cancel
            </button>
            <button
              type="button"
              className={cn(
                "h-9 shrink-0 rounded-lg px-3 py-1.5 text-sm font-medium transition-colors",
                !canAdd
                  ? "bg-fd-muted text-fd-muted-foreground cursor-not-allowed"
                  : "bg-fd-primary text-fd-primary-foreground hover:bg-fd-primary/90",
              )}
              onClick={handleSubmit}
              disabled={!canAdd}
            >
              Add
            </button>
          </>
        )}
      </div>

      {/* Committed rules — appended below the input row. */}
      {rules.length > 0 && (
        <div className="space-y-1">
          {rules.map((rule, ri) => (
            <div
              // oxlint-disable-next-line react/no-array-index-key
              key={ri}
              className="flex items-center gap-1.5 text-sm font-mono"
            >
              <span className="min-w-[2ch] text-fd-muted-foreground">{getOperatorLabel(rule.operator)}</span>
              <span className="text-fd-foreground">{rule.values.map((v) => String(v)).join(", ")}</span>
              <button
                type="button"
                className="text-fd-muted-foreground hover:text-red-500 transition-colors"
                onClick={() => setRules((prev) => prev.filter((_, i) => i !== ri))}
              >
                <Trash2 className="size-3" />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Validation messages (below the row) */}
      {scope === "calldata" && arrayNode && arrayMode === "index" && (
        <>
          {staticArrayLength !== null &&
            arrayIndex !== "" &&
            (Number(arrayIndex) < 0 ||
              Number(arrayIndex) >= staticArrayLength ||
              !Number.isInteger(Number(arrayIndex))) && (
              <div className="flex items-start gap-1.5 text-xs text-red-700 dark:text-red-300">
                <AlertTriangle className="mt-0.5 size-3 shrink-0" />
                <span>Index must be between 0 and {staticArrayLength - 1}.</span>
              </div>
            )}
          {staticArrayLength === null && (
            <div className="flex items-start gap-1.5 text-xs text-fd-info-foreground">
              <InfoIcon className="mt-0.5 size-3 shrink-0" />
              <span>Dynamic array: index valid syntactically, but array length is only known at runtime.</span>
            </div>
          )}
        </>
      )}
      {resolvedElement?.element && !resolvedElement.children && (
        <div className="flex items-start gap-1.5 text-xs text-fd-info-foreground">
          <InfoIcon className="mt-0.5 size-3 shrink-0" />
          <span>Nested array traversal is not supported in the builder. Use the SDK for deeper paths.</span>
        </div>
      )}

      {previewResult && (previewResult.errors.length > 0 || previewResult.issues.length > 0) && (
        <div className="flex flex-col gap-0.5">
          {previewResult.errors.map((error, i) => (
            // oxlint-disable-next-line react/no-array-index-key
            <div key={`e-${i}`} className="flex items-start gap-1.5 text-xs text-red-700 dark:text-red-300">
              <AlertTriangle className="mt-0.5 size-3 shrink-0" />
              <span>{humanizeError(error)}</span>
            </div>
          ))}
          {previewResult.issues.map((issue, i) => (
            <div
              // oxlint-disable-next-line react/no-array-index-key
              key={`i-${i}`}
              className={cn(
                "flex items-start gap-1.5 text-xs",
                issue.severity === "error" && "text-red-700 dark:text-red-300",
                issue.severity === "warning" && "text-fd-secondary-foreground",
                issue.severity === "info" && "text-fd-info-foreground",
              )}
            >
              {issue.severity === "warning" ? (
                <AlertTriangle className="mt-0.5 size-3 shrink-0" />
              ) : (
                <InfoIcon className="mt-0.5 size-3 shrink-0" />
              )}
              <span>{issue.message}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

///////////////////////////////////////////////////////////////////////////
// Nested field selector for tuple types
///////////////////////////////////////////////////////////////////////////

function FieldSelector({
  node,
  selectedPath,
  onSelect,
  usedPaths,
  pathPrefix,
}: {
  node: ParamNode;
  selectedPath: number[];
  onSelect: (path: number[]) => void;
  usedPaths?: Set<string>;
  pathPrefix?: number[];
}) {
  if (!node.children) return null;

  const prefix = pathPrefix ?? [];
  const currentIndex = selectedPath[0];
  const currentChild = currentIndex !== undefined ? node.children[currentIndex] : null;

  return (
    <div className="flex items-start gap-2">
      <div className="flex flex-col items-start gap-1">
        <span className="text-xs text-fd-muted-foreground">field</span>
        <Select
          value={currentIndex !== undefined ? String(currentIndex) : ""}
          onValueChange={(v) => {
            if (!v) {
              onSelect([]);
            } else {
              onSelect([Number(v)]);
            }
          }}
        >
          <SelectTrigger className="w-48">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {node.children.map((child, i) => {
              if (isLeafNode(child) && usedPaths?.has(pathKey([...prefix, i]))) return null;
              return (
                // oxlint-disable-next-line react/no-array-index-key
                <SelectItem key={i} value={String(i)}>
                  [{i}]{child.name ? ` ${child.name}` : ""}: {child.type}
                </SelectItem>
              );
            })}
          </SelectContent>
        </Select>
      </div>

      {/* Recurse for nested tuples */}
      {currentChild?.children && (
        <FieldSelector
          node={currentChild}
          selectedPath={selectedPath.slice(1)}
          onSelect={(subPath) => onSelect([currentIndex, ...subPath])}
          usedPaths={usedPaths}
          pathPrefix={[...prefix, currentIndex]}
        />
      )}
    </div>
  );
}

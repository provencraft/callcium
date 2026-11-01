"use client";

import { TypeCode, lookupContextProperty, Quantifier } from "@callcium/sdk";
import { buttonVariants } from "fumadocs-ui/components/ui/button";
import { Plus, Trash2, AlertTriangle, Info as InfoIcon } from "lucide-react";
import { useCallback, useMemo, useState } from "react";
import type { Issue, ScalarValue } from "@callcium/sdk";
import { ErrorBox } from "@/components/ui/error-box";
import { MonoInput } from "@/components/ui/mono-input";
import { PillToggle } from "@/components/ui/pill-toggle";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  CONTEXT_PROPERTIES,
  CONTEXT_PROPERTY_COUNT,
  contextPropertyType,
  formatPath,
  quantifierLabel,
} from "@/lib/format-path";
import { formatOperandList } from "@/lib/format-value";
import {
  addConstraint,
  removeConstraint,
  addGroup,
  removeGroup,
  getOperatorArity,
  getOperatorOptions,
  getOperatorLabel,
  isContextOperator,
  issueMatches,
  type BuilderSession,
  type ConstraintConfig,
  type ConstraintInput,
  type OperatorRule,
  type ParamNode,
} from "@/lib/policy-builder";
import { useDebounce } from "@/lib/use-debounce";
import { cn } from "@/lib/utils";

///////////////////////////////////////////////////////////////////////////
// Quantifier options
///////////////////////////////////////////////////////////////////////////

const QUANTIFIER_OPTIONS = [
  {
    value: Quantifier.ALL,
    label: quantifierLabel(Quantifier.ALL),
    desc: "all elements must pass\nempty array → pass",
  },
  {
    value: Quantifier.ANY,
    label: quantifierLabel(Quantifier.ANY),
    desc: "at least one must pass\nempty array → fail",
  },
] as const;

///////////////////////////////////////////////////////////////////////////
// Main component
///////////////////////////////////////////////////////////////////////////

/** The constraint groups of a session, as an editor. */
export function Builder({
  session,
  onChange,
}: {
  session: BuilderSession;
  onChange: (session: BuilderSession) => void;
}) {
  return (
    <div className="space-y-4">
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
                  aria-label="Remove group"
                  onClick={() => onChange(removeGroup(session, gi))}
                >
                  <Trash2 className="size-3.5" />
                </button>
              )}
            </div>

            {group.constraints.map((config, ci) => {
              const rowIssues = session.issues.filter((i) => i.groupIndex === gi && issueMatches(i, config));
              return (
                <ConstraintRow
                  key={config.id}
                  config={config}
                  issues={rowIssues}
                  params={session.params}
                  onRemove={() => onChange(removeConstraint(session, gi, ci))}
                />
              );
            })}

            {/* Add constraint form */}
            <AddConstraintForm
              session={session}
              groupIndex={gi}
              onAdd={(config) => onChange(addConstraint(session, gi, config))}
            />
          </div>
        </div>
      ))}

      <button
        type="button"
        className={buttonVariants({ variant: "outline", size: "sm" })}
        onClick={() => onChange(addGroup(session))}
      >
        Add OR group
      </button>

      {session.errors.length > 0 && (
        <div className="space-y-1">
          {session.errors.map((error, i) => (
            // oxlint-disable-next-line react/no-array-index-key
            <ErrorBox key={i}>{humanizeError(error)}</ErrorBox>
          ))}
        </div>
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

/** Descend a ParamNode tree by tuple-field/array-element steps. Null if a step runs off the tree. */
function walkParamPath(root: ParamNode, steps: number[]): ParamNode | null {
  let node: ParamNode | undefined = root;
  for (const step of steps) {
    if (node.children) node = node.children[step];
    else if (node.element) node = node.element;
    else return null;
    if (!node) return null;
  }
  return node;
}

/** A single validation issue line, severity-styled. */
function IssueLine({ issue, className }: { issue: Issue; className?: string }) {
  return (
    <div
      className={cn(
        "flex items-start gap-1.5 text-xs",
        className,
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
  );
}

/** Resolve the Solidity type string for a constraint's target. */
function resolveTargetType(config: ConstraintConfig, params: ParamNode[]): string | null {
  if (config.scope === "context") {
    return config.contextProperty ? contextPropertyType(config.contextProperty) : null;
  }
  if (!config.path || config.path.length === 0) return null;
  const root = params[config.path[0]];
  if (!root) return null;
  return walkParamPath(root, config.path.slice(1))?.type ?? null;
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
                {formatRuleValues(config.rules[0].operator, config.rules[0].values)}
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
          aria-label="Remove constraint"
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
            <span className="text-fd-foreground break-all">{formatRuleValues(rule.operator, rule.values)}</span>
          </div>
        ))}
      {issues.map((issue, i) => (
        // oxlint-disable-next-line react/no-array-index-key
        <IssueLine key={i} issue={issue} className="mt-0.5" />
      ))}
    </div>
  );
}

///////////////////////////////////////////////////////////////////////////
// Add constraint form (inline within a group)
///////////////////////////////////////////////////////////////////////////

/** Strip error codes and hex paths from structural error messages. */
export function humanizeError(error: string): string {
  // "UNKNOWN_CONTEXT_PROPERTY: Unknown context property ID 0x0009" → "Unknown context property ID"
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

/** Render a rule's operand list for display. */
function formatRuleValues(operator: string, values: ScalarValue[]): string {
  const operands = isContextOperator(operator)
    ? values.map((v) => lookupContextProperty(Number(v)).label)
    : values.map((v) => String(v));
  return formatOperandList(getOperatorArity(operator), operands);
}

function parseConstraintValues(operator: string, valueInput: string, typeCode: number | null): ScalarValue[] | null {
  try {
    // A context property ID, not a value of the target's type, so this precedes the type branches.
    if (isContextOperator(operator)) {
      const trimmed = valueInput.trim();
      return trimmed ? [BigInt(trimmed)] : null;
    }
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
    if (typeCode === TypeCode.ADDRESS) {
      const trimmed = valueInput.trim();
      return trimmed ? [trimmed] : null;
    }
    if (typeCode === TypeCode.BOOL) {
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
function valuePlaceholder(operator: string, typeCode: number | null): string | undefined {
  if (operator === "isIn" || operator === "notIn") return "value1,value2,...";
  if (operator === "between" || operator === "lengthBetween") return "min,max";
  if (typeCode === TypeCode.ADDRESS) return "0x...";
  if (typeCode === TypeCode.BOOL) return "true / false";
  return undefined;
}

/** Assemble the full rules list from committed rules plus the in-progress draft (if valid). */
function resolveRules(
  rules: OperatorRule[],
  operator: string,
  valueInput: string,
  typeCode: number | null,
): OperatorRule[] {
  const result = [...rules];
  if (operator) {
    const values = parseConstraintValues(operator, valueInput, typeCode);
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

  const usedContextProperties = useMemo(() => {
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

  const hasAvailableContext = usedContextProperties.size < CONTEXT_PROPERTY_COUNT;
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
    const node = walkParamPath(session.params[selectedParam], selectedField);
    return node?.element ? node : null;
  }, [scope, selectedParam, selectedField, session.params]);

  const staticArrayLength = useMemo(() => (arrayNode ? parseStaticArrayLength(arrayNode.type) : null), [arrayNode]);

  const resolvedElement = useMemo(() => {
    if (!arrayNode) return null;
    if (arrayMode === "quantified" && quantifier === undefined) return null;
    if (arrayMode === "index" && !/^\d+$/.test(arrayIndex)) return null;
    return arrayNode.element;
  }, [arrayNode, arrayMode, quantifier, arrayIndex]);

  const targetTypeCode = useMemo<number | null>(() => {
    if (scope === "context") {
      if (!contextProperty) return null;
      return CONTEXT_PROPERTIES.find((p) => p.contextKey === contextProperty)?.typeCode ?? null;
    }
    if (selectedParam === null || !session.params[selectedParam]) return null;
    const node = walkParamPath(session.params[selectedParam], selectedField);
    if (!node) return null;
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
        return resolved.typeCode;
      }
      // Array selected but no access mode chosen yet — don't resolve.
      return null;
    }
    return node.typeCode;
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
    if (targetTypeCode === null) return [];
    const all = getOperatorOptions(targetTypeCode);
    const usedOps = new Set(rules.map((r) => r.operator));
    return all.filter((op) => !usedOps.has(op.value));
  }, [targetTypeCode, rules]);

  const debouncedValue = useDebounce(valueInput, 300);
  const validIndex = /^\d+$/.test(arrayIndex);

  const indexValid =
    !arrayNode ||
    arrayMode === "quantified" ||
    (validIndex && (staticArrayLength === null || Number(arrayIndex) < staticArrayLength));

  // Steps down to and including the array access. The quantifier or index step sits immediately after the array node it
  // addresses — where `selectedField` lands.
  const arrayAccessPath = useMemo(() => {
    if (selectedParam === null) return [];
    const base = [selectedParam, ...selectedField];
    if (arrayNode) {
      if (arrayMode === "index" && validIndex) base.push(Number(arrayIndex));
      else if (arrayMode === "quantified" && quantifier !== undefined) base.push(quantifier);
    }
    return base;
  }, [selectedParam, selectedField, arrayNode, arrayMode, validIndex, arrayIndex, quantifier]);

  const constraintPath = useMemo(() => [...arrayAccessPath, ...postArrayField], [arrayAccessPath, postArrayField]);

  const previewResult = useMemo<{ errors: string[]; issues: Issue[] } | null>(() => {
    const candidateRules = resolveRules(rules, operator, debouncedValue, targetTypeCode);
    if (candidateRules.length === 0) return null;

    const path = constraintPath;
    const config: ConstraintInput = {
      scope,
      ...(scope === "calldata" ? { path } : contextProperty ? { contextProperty } : {}),
      rules: candidateRules,
    };

    const preview = addConstraint(session, groupIndex, config);
    return {
      errors: preview.errors,
      issues: preview.issues.filter((i) => i.groupIndex === groupIndex && issueMatches(i, config)),
    };
  }, [scope, constraintPath, contextProperty, operator, debouncedValue, targetTypeCode, rules, session, groupIndex]);

  const hasValidDraft = operator !== "" && parseConstraintValues(operator, valueInput, targetTypeCode) !== null;
  const canAdd =
    indexValid &&
    (rules.length > 0 || hasValidDraft) &&
    previewResult !== null &&
    previewResult.errors.length === 0 &&
    !previewResult.issues.some((i) => i.severity === "error");

  const handleAddOperator = useCallback(() => {
    const values = parseConstraintValues(operator, valueInput, targetTypeCode);
    if (!values || !operator) return;
    setRules((prev) => [...prev, { operator, values }]);
    setOperator("");
    setValueInput("");
  }, [operator, valueInput, targetTypeCode]);

  const handleSubmit = useCallback(() => {
    if (!canAdd) return;
    const finalRules = resolveRules(rules, operator, valueInput, targetTypeCode);
    if (finalRules.length === 0) return;

    const path = constraintPath;
    const config: ConstraintInput = {
      scope,
      ...(scope === "calldata" ? { path } : contextProperty ? { contextProperty } : {}),
      rules: finalRules,
    };

    onAdd(config);
    setRules([]);
    setOperator("");
    setValueInput("");
    setExpanded(false);
  }, [scope, constraintPath, contextProperty, operator, valueInput, targetTypeCode, rules, canAdd, onAdd]);

  if (!expanded) {
    if (!hasAvailableCalldata && !hasAvailableContext) return null;
    return (
      <div className="px-3 py-2">
        <button
          type="button"
          className={buttonVariants({ variant: "outline", size: "sm" })}
          onClick={() => {
            if (hasAvailableCalldata) setScope("calldata");
            else setScope("context");
            setExpanded(true);
          }}
        >
          Add constraint
        </button>
      </div>
    );
  }

  return (
    <div className="border-t border-fd-border/30 px-3 py-2 space-y-2">
      {/* First row: path controls + first operator/value inline. */}
      <div className="flex flex-wrap items-end gap-2">
        {/* Path controls */}
        <div className="flex max-w-full flex-col items-start gap-1">
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
              <SelectTrigger className="w-64 max-w-full shrink-0 font-mono">
                <SelectValue />
              </SelectTrigger>
              <SelectContent className="font-mono">
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
              <SelectTrigger className="w-64 max-w-full shrink-0 font-mono">
                <SelectValue />
              </SelectTrigger>
              <SelectContent className="font-mono">
                {CONTEXT_PROPERTIES.map(
                  (property) =>
                    !usedContextProperties.has(property.contextKey) && (
                      <SelectItem key={property.contextKey} value={property.contextKey}>
                        {property.label}
                      </SelectItem>
                    ),
                )}
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
                <SelectTrigger className="w-48">
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
            pathPrefix={arrayAccessPath}
          />
        )}

        {/* Operator, value, and buttons — all visible once target is selected. */}
        {targetTypeCode !== null && (
          <>
            <div className="flex flex-col items-start gap-1">
              {rules.length === 0 && <span className="text-xs text-fd-muted-foreground">operator</span>}
              <Select
                value={operator}
                onValueChange={(op) => {
                  // A property ID and a literal value are both plain numbers, so a carried-over input would parse as
                  // the wrong operand.
                  if (isContextOperator(op) !== isContextOperator(operator)) setValueInput("");
                  setOperator(op);
                }}
              >
                <SelectTrigger className="w-40 shrink-0 font-mono">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent className="font-mono">
                  {operatorOptions.map((op) => (
                    <SelectItem key={op.value} value={op.value}>
                      {op.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="flex min-w-32 flex-1 flex-col items-start gap-1">
              {rules.length === 0 && (
                <label htmlFor="constraint-value" className="text-xs text-fd-muted-foreground">
                  value
                </label>
              )}
              {isContextOperator(operator) ? (
                <Select value={valueInput} onValueChange={setValueInput}>
                  <SelectTrigger id="constraint-value" className="w-full font-mono">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent className="font-mono">
                    {CONTEXT_PROPERTIES.filter(
                      (property) => (targetTypeCode === TypeCode.ADDRESS) === (property.typeCode === TypeCode.ADDRESS),
                    ).map((property) => (
                      <SelectItem key={property.code} value={String(property.code)}>
                        {property.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <MonoInput
                  id="constraint-value"
                  placeholder={valuePlaceholder(operator, targetTypeCode)}
                  value={valueInput}
                  onChange={(e) => setValueInput(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && canAdd && handleSubmit()}
                />
              )}
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
              <span className="text-fd-foreground">{formatRuleValues(rule.operator, rule.values)}</span>
              <button
                type="button"
                className="text-fd-muted-foreground hover:text-red-500 transition-colors"
                aria-label="Remove operator"
                onClick={() => setRules((prev) => prev.filter((_, i) => i !== ri))}
              >
                <Trash2 className="size-3.5" />
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
            // oxlint-disable-next-line react/no-array-index-key
            <IssueLine key={`i-${i}`} issue={issue} />
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
    <div className="flex max-w-full flex-wrap items-start gap-2">
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
          <SelectTrigger className="w-48 font-mono">
            <SelectValue />
          </SelectTrigger>
          <SelectContent className="font-mono">
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

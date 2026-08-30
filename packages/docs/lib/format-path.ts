import {
  ContextProperty,
  isQuantifier,
  lookupContextProperty,
  lookupOp,
  lookupQuantifier,
  lookupTypeCode,
} from "@callcium/sdk";
import type { ParamNode } from "@/lib/policy-builder";

/** Canonical, SDK-derived list of context properties: code, camelCase key, display label, ABI type code. */
export const CONTEXT_PROPERTIES = Object.values(ContextProperty).map((code) => ({
  code,
  ...lookupContextProperty(code),
}));

/** Map from camelCase context property keys to SDK property codes. */
export const CONTEXT_IDS: Record<string, number> = Object.fromEntries(
  CONTEXT_PROPERTIES.map((p) => [p.contextKey, p.code]),
);

/** Total number of context properties (derived from SDK). */
export const CONTEXT_PROPERTY_COUNT = CONTEXT_PROPERTIES.length;

/** Resolve the Solidity type label for a context property key (e.g. "msgSender" → "address"). */
export function contextPropertyType(key: string): string | null {
  const code = CONTEXT_IDS[key];
  if (code === undefined) return null;
  return lookupTypeCode(lookupContextProperty(code).typeCode).label;
}

///////////////////////////////////////////////////////////////////////////
// Operator formatting
///////////////////////////////////////////////////////////////////////////

/** Format an operator code into a human-readable label, handling negation. */
export function formatOpLabel(opCode: number, negated: boolean): string {
  const base = lookupOp(opCode).label;
  if (!negated) return base;
  if (base === "==") return "!=";
  if (base === "== ctx") return "!= ctx";
  return `not ${base}`;
}

///////////////////////////////////////////////////////////////////////////
// Path formatting — single source of truth for all tools.
///////////////////////////////////////////////////////////////////////////

/**
 * Format a calldata constraint path in dot-bracket notation.
 *
 * `path` carries every step, quantifier sentinels included (detected via
 * `isQuantifier`). Uses `ParamNode` tree for named resolution when available.
 *
 * Examples:
 *   - `transfers[all].amount` (named)
 *   - `arg(0)[all].field(1)` (unnamed)
 *   - `arg(1)` (scalar)
 */
export function formatCalldataPath(steps: number[], params?: ParamNode[]): string {
  if (steps.length === 0) return "arg(?)";

  const argIndex = steps[0];
  let node: ParamNode | undefined = params?.[argIndex];
  let label = node?.name ?? `arg(${argIndex})`;

  let step = 1;
  while (step < steps.length) {
    const stepValue = steps[step];

    if (isQuantifier(stepValue)) {
      label += `[${lookupQuantifier(stepValue).label}]`;
      if (node?.element) node = node.element;
      step++;
      continue;
    }

    if (node?.element) {
      // Array node — this step is an explicit index.
      label += `[${stepValue}]`;
      node = node.element;
      step++;
      continue;
    }

    if (node?.children) {
      // Tuple node — this step is a field index.
      const child = node.children[stepValue];
      label += `.${child?.name ?? `field(${stepValue})`}`;
      node = child;
      step++;
      continue;
    }

    // No node info — fall back to generic notation.
    label += `.field(${stepValue})`;
    step++;
  }

  return label;
}

/**
 * Format a context property path.
 * Accepts either an internal property name (builder) or a numeric ID (inspector).
 */
export function formatContextPath(contextProperty: string | number): string {
  if (typeof contextProperty === "number") {
    try {
      return lookupContextProperty(contextProperty).label;
    } catch {
      return `context(${contextProperty})`;
    }
  }

  const id = CONTEXT_IDS[contextProperty];
  if (id !== undefined) {
    try {
      return lookupContextProperty(id).label;
    } catch {
      return contextProperty;
    }
  }
  return contextProperty;
}

/**
 * Format a constraint path in standardized dot-bracket notation.
 * Single entry point for all tools.
 */
export function formatPath(options: {
  scope: "calldata" | "context";
  path?: number[];
  contextProperty?: string | number;
  params?: ParamNode[];
}): string {
  if (options.scope === "context") {
    return formatContextPath(options.contextProperty ?? "context");
  }
  return formatCalldataPath(options.path ?? [], options.params);
}

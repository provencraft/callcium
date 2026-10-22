import {
  ContextProperty,
  type Hex,
  LoopQuantifier,
  lookupContextProperty,
  lookupOp,
  lookupQuantifier,
  lookupTypeCode,
  parsePathSteps,
  Quantifier,
  type QuantifierCode,
} from "@callcium/sdk";
import type { ParamNode } from "@/lib/policy-builder";

/** Canonical, SDK-derived list of context properties: code, camelCase key, display label, ABI type code. */
export const CONTEXT_PROPERTIES = Object.values(ContextProperty).map((code) => ({
  code,
  ...lookupContextProperty(code),
}));

/** Map from camelCase context property keys to SDK property codes. */
const CONTEXT_IDS: Record<string, number> = Object.fromEntries(CONTEXT_PROPERTIES.map((p) => [p.contextKey, p.code]));

/** Total number of context properties (derived from SDK). */
export const CONTEXT_PROPERTY_COUNT = CONTEXT_PROPERTIES.length;

/** Resolve the context property code for a camelCase key (e.g. "msgSender" → 0). */
export function contextPropertyId(key: string): number | undefined {
  return CONTEXT_IDS[key];
}

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
// Quantifier steps
///////////////////////////////////////////////////////////////////////////

/** True for the path steps that quantify over the array before them. */
function isQuantifierStep(step: number): boolean {
  return step === Quantifier.ALL || step === Quantifier.ANY;
}

/** Display label of a quantifier step. */
export function quantifierLabel(step: number): string {
  return lookupQuantifier(step === Quantifier.ALL ? LoopQuantifier.ALL : LoopQuantifier.ANY).label;
}

/** The steps of a loop's array with the quantifier step after them, as a constraint path spells the loop. */
export function loopSteps(path: Hex, quantifier: QuantifierCode): number[] {
  return [...parsePathSteps(path), quantifier === LoopQuantifier.ALL ? Quantifier.ALL : Quantifier.ANY];
}

///////////////////////////////////////////////////////////////////////////
// Path formatting — single source of truth for all tools.
///////////////////////////////////////////////////////////////////////////

/** A path label so far and the parameter node it has reached, when known. */
type PathPosition = { label: string; node: ParamNode | undefined };

/** The position at an argument. */
function argPosition(argIndex: number, params?: ParamNode[]): PathPosition {
  const node = params?.[argIndex];
  return { label: node?.name ?? `arg(${argIndex})`, node };
}

/** Extend a path label by `steps`, resolving names through the node tree when available. */
function walkSteps(position: PathPosition, steps: readonly number[]): PathPosition {
  let { label, node } = position;
  for (const step of steps) {
    if (isQuantifierStep(step)) {
      label += `[${quantifierLabel(step)}]`;
      if (node?.element) node = node.element;
    } else if (node?.element) {
      // Array node — this step is an explicit index.
      label += `[${step}]`;
      node = node.element;
    } else if (node?.children) {
      // Tuple node — this step is a field index.
      const child = node.children[step];
      label += `.${child?.name ?? `field(${step})`}`;
      node = child;
    } else {
      // No node info — fall back to generic notation.
      label += `.field(${step})`;
    }
  }
  return { label, node };
}

/**
 * Format a calldata constraint path in dot-bracket notation.
 *
 * `steps` carries every step, quantifier steps included. Uses `ParamNode` tree for named resolution when available.
 *
 * Examples:
 *   - `transfers[all].amount` (named)
 *   - `arg(0)[all].field(1)` (unnamed)
 *   - `arg(1)` (scalar)
 */
export function formatCalldataPath(steps: number[], params?: ParamNode[]): string {
  if (steps.length === 0) return "arg(?)";
  return walkSteps(argPosition(steps[0], params), steps.slice(1)).label;
}

/** Format a loop body test's path from the element of the loop at `loop`, e.g. `.amount`. */
export function formatBodyPath(loop: number[], bodySteps: number[], params?: ParamNode[]): string {
  const element = walkSteps(argPosition(loop[0], params), loop.slice(1)).node;
  return walkSteps({ label: "", node: element }, bodySteps).label;
}

/**
 * Format a context property path from an internal property name (builder) or a numeric ID (violation formatter).
 */
export function formatContextPath(contextProperty: string | number): string {
  const id = typeof contextProperty === "number" ? contextProperty : CONTEXT_IDS[contextProperty];
  return id === undefined ? String(contextProperty) : lookupContextProperty(id).label;
}

/**
 * Format a constraint path in standardized dot-bracket notation from the builder's path options.
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

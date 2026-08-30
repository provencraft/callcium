import {
  type DecodedPolicy,
  type DecodedRule,
  Descriptor,
  type Hex,
  type Operands,
  Op,
  Scope,
  type Span,
  TypeCode,
  hexToBytes,
  lookupContextProperty,
  lookupOp,
  lookupScope,
  lookupTypeCode,
  parsePathSteps,
} from "@callcium/sdk";
import { type Abi, type AbiFunction, type AbiParameter, toFunctionSelector } from "viem";
import { formatCalldataPath, formatOpLabel } from "./format-path";
import { decodeOperandsFromData } from "./format-value";
import { type ParamNode, parseDescriptor, toNameTree } from "./policy-builder";

///////////////////////////////////////////////////////////////////////////
// Types
///////////////////////////////////////////////////////////////////////////

export type ExplainedPolicy = {
  selector: Hex;
  functionName: string | null;
  isSelectorless: boolean;
  params: ExplainedParam[];
  groups: ExplainedGroup[];
  span?: Span;
};

export type ExplainedParam = {
  index: number;
  name: string | null;
  type: string;
  isDynamic: boolean;
};

export type ExplainedGroup = {
  constraints: ExplainedConstraint[];
};

export type ExplainedConstraint = {
  scope: string;
  path: Hex;
  pathLabel: string;
  targetType: string;
  rules: ExplainedRule[];
  span?: Span;
};

export type ExplainedRule = {
  operator: string;
  negated: boolean;
  operands: string[];
  arity: Operands;
};

export type ExplainedFlatRule = {
  constraint: ExplainedConstraint;
  rule: ExplainedRule;
};

export type ExplainOptions = {
  abi?: Abi;
};

/** Flatten a group's constraints into a wire-order list of (constraint, rule) pairs. */
export function flattenGroup(group: ExplainedGroup): ExplainedFlatRule[] {
  return group.constraints.flatMap((c) => c.rules.map((r) => ({ constraint: c, rule: r })));
}

/** Render a rule's operands as a display string, bracketed by operator arity (set vs range vs single). */
export function formatOperands(rule: ExplainedRule): string {
  if (rule.arity === "variadic") return `{${rule.operands.join(", ")}}`;
  if (rule.arity === "range") return `[${rule.operands.join(", ")}]`;
  return rule.operands.join(", ");
}

///////////////////////////////////////////////////////////////////////////
// Path resolution
///////////////////////////////////////////////////////////////////////////

function resolveContextPath(steps: number[]): { pathLabel: string; leafTypeCode: number } {
  const propertyCode = steps[0];
  try {
    const property = lookupContextProperty(propertyCode);
    return { pathLabel: property.label, leafTypeCode: property.typeCode };
  } catch {
    return { pathLabel: `context(${propertyCode})`, leafTypeCode: TypeCode.UINT_MAX };
  }
}

///////////////////////////////////////////////////////////////////////////
// Explainer
///////////////////////////////////////////////////////////////////////////

export function explainPolicy(policy: DecodedPolicy, options?: ExplainOptions): ExplainedPolicy {
  const descBytes = hexToBytes(policy.descriptor.raw);

  let functionName: string | null = null;
  let abiInputs: readonly AbiParameter[] | undefined;

  if (options?.abi && !policy.isSelectorless) {
    const matched = options.abi.find(
      (item): item is AbiFunction => item.type === "function" && toFunctionSelector(item) === policy.selector.value,
    );
    if (matched) {
      functionName = matched.name;
      abiInputs = matched.inputs;
    }
  }

  // Parse descriptor once for both param info and path resolution.
  const nameTrees = abiInputs?.map(toNameTree) ?? [];
  const paramNodes = parseDescriptor(descBytes, nameTrees);

  const params: ExplainedParam[] = paramNodes.map((pn, i) => ({
    index: i,
    name: pn.name,
    type: pn.type,
    isDynamic: pn.typeInfo.isDynamic,
  }));

  const groups: ExplainedGroup[] = policy.groups.map((group) => {
    // Group flat rules by (scope, path) into constraints. Map iteration preserves wire order.
    const constraintMap = new Map<string, DecodedRule[]>();

    for (const rule of group.rules) {
      const key = `${rule.scope.value}:${rule.path.value}`;
      const existing = constraintMap.get(key);
      if (existing) existing.push(rule);
      else constraintMap.set(key, [rule]);
    }

    return {
      constraints: [...constraintMap.values()].map((rules) => explainConstraint(rules, descBytes, paramNodes)),
    };
  });

  return {
    selector: policy.selector.value,
    functionName,
    isSelectorless: policy.isSelectorless,
    params,
    groups,
    span: policy.span,
  };
}

function explainConstraint(rules: DecodedRule[], descBytes: Uint8Array, paramNodes: ParamNode[]): ExplainedConstraint {
  const first = rules[0];
  const scope = first.scope.value;
  const path: Hex = first.path.value;
  const steps = parsePathSteps(path);
  const scopeLabel = lookupScope(scope).label;
  const isContext = scope === Scope.CONTEXT;
  let pathLabel: string;
  let leafTypeCode: number;

  if (isContext) {
    ({ pathLabel, leafTypeCode } = resolveContextPath(steps));
  } else {
    pathLabel = formatCalldataPath(steps, paramNodes);
    leafTypeCode = Descriptor.typeAt(descBytes, steps).typeCode;
  }
  const targetType = lookupTypeCode(leafTypeCode).label;

  const explainedRules: ExplainedRule[] = rules.map((rule) => {
    const opCode = rule.opCode.value;
    const negated = (opCode & Op.NOT) !== 0;
    const opBase = opCode & ~Op.NOT;
    const operator = formatOpLabel(opBase, negated);
    const decodeTypeCode = opBase >= Op.LENGTH_EQ && opBase <= Op.LENGTH_BETWEEN ? TypeCode.UINT_MAX : leafTypeCode;

    return {
      operator,
      negated,
      operands: decodeOperandsFromData(rule.data.value, decodeTypeCode, opBase),
      arity: lookupOp(opBase).operands,
    };
  });

  return {
    scope: scopeLabel,
    path,
    pathLabel,
    targetType,
    rules: explainedRules,
    span: first.span,
  };
}

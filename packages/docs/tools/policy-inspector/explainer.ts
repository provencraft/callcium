import {
  type DecodedPolicy,
  type DecodedRule,
  Descriptor,
  type Hex,
  Op,
  Scope,
  type Span,
  TypeCode,
  hexToBytes,
  lookupContextProperty,
  lookupScope,
  lookupTypeCode,
  parsePathSteps,
} from "@callcium/sdk";
import { type Abi, type AbiFunction, type AbiParameter, toFunctionSelector } from "viem";
import { formatCalldataPath, formatOpLabel } from "../../lib/format-path";
import { decodeOperandsFromData } from "../../lib/format-value";
import { type ParamNode, parseDescriptor, toNameTree } from "../policy-builder/builder-engine";

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

///////////////////////////////////////////////////////////////////////////
// Path resolution
///////////////////////////////////////////////////////////////////////////

function resolveContextPath(steps: number[]): {
  pathLabel: string;
  targetType: string;
  leafTypeCode: number;
} {
  const propCode = steps[0];
  try {
    const prop = lookupContextProperty(propCode);
    return {
      pathLabel: prop.label,
      targetType: lookupTypeCode(prop.typeCode).label,
      leafTypeCode: prop.typeCode,
    };
  } catch {
    return { pathLabel: `context(${propCode})`, targetType: "uint256", leafTypeCode: TypeCode.UINT_MAX };
  }
}

///////////////////////////////////////////////////////////////////////////
// ABI matching
///////////////////////////////////////////////////////////////////////////

function findAbiFunction(abi: Abi, selector: Hex): AbiFunction | null {
  for (const item of abi) {
    if (item.type === "function") {
      if (toFunctionSelector(item) === selector) return item;
    }
  }
  return null;
}

///////////////////////////////////////////////////////////////////////////
// Explainer
///////////////////////////////////////////////////////////////////////////

export function explainPolicy(policy: DecodedPolicy, opts?: ExplainOptions): ExplainedPolicy {
  const descBytes = hexToBytes(policy.descriptor.raw);

  let functionName: string | null = null;
  let abiInputs: readonly AbiParameter[] | undefined;

  if (opts?.abi && !policy.isSelectorless) {
    const matched = findAbiFunction(opts.abi, policy.selector.value);
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
    // Group flat rules by (scope, path) into constraints.
    const constraintMap = new Map<string, DecodedRule[]>();
    const constraintOrder: string[] = [];

    for (const rule of group.rules) {
      const key = `${rule.scope.value}:${rule.path.value}`;
      const existing = constraintMap.get(key);
      if (existing) {
        existing.push(rule);
      } else {
        constraintMap.set(key, [rule]);
        constraintOrder.push(key);
      }
    }

    return {
      constraints: constraintOrder.map((key) => explainConstraint(constraintMap.get(key)!, descBytes, paramNodes)),
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
  let targetType: string;
  let leafTypeCode: number;

  if (isContext) {
    ({ pathLabel, targetType, leafTypeCode } = resolveContextPath(steps));
  } else {
    pathLabel = formatCalldataPath(steps, undefined, paramNodes);
    const leaf = Descriptor.typeAt(descBytes, steps);
    targetType = lookupTypeCode(leaf.typeCode).label;
    leafTypeCode = leaf.typeCode;
  }

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

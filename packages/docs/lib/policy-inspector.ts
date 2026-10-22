import {
  type DecodedLoop,
  type DecodedPolicy,
  type DecodedTest,
  type Hex,
  type Operands,
  Scope,
  type Span,
  lookupOp,
  lookupScope,
  lookupTypeCode,
  parsePathSteps,
} from "@callcium/sdk";
import { type Abi, type AbiFunction, type AbiParameter, toFunctionSelector } from "viem";
import { formatBodyPath, formatCalldataPath, formatContextPath, formatOpLabel, loopSteps } from "./format-path";
import { decodeOperands, formatOperandList } from "./format-value";
import { type ParamNode, toNameTree, toParamNodes } from "./policy-builder";

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

type ExplainedParam = {
  index: number;
  name: string | null;
  type: string;
  isDynamic: boolean;
};

export type ExplainedGroup = {
  rules: (ExplainedTest | ExplainedLoop)[];
};

/** A test: its target, its operator and its operands. A body test's path label starts at the element. */
export type ExplainedTest = {
  scope: string;
  path: Hex;
  pathLabel: string;
  targetType: string;
  operator: string;
  negated: boolean;
  operands: string[];
  arity: Operands;
  /** The decoded test. */
  rule: DecodedTest;
};

/** A loop: its array with its quantifier, and the tests its body holds for an element. */
export type ExplainedLoop = {
  pathLabel: string;
  body: ExplainedTest[];
  /** The decoded loop. */
  rule: DecodedLoop;
};

type ExplainOptions = {
  abi?: Abi;
};

/** Render a test's operands as a display string, bracketed by operator arity (set vs range vs single). */
export function formatOperands(test: ExplainedTest): string {
  return formatOperandList(test.arity, test.operands);
}

///////////////////////////////////////////////////////////////////////////
// Explainer
///////////////////////////////////////////////////////////////////////////

export function explainPolicy(policy: DecodedPolicy, options?: ExplainOptions): ExplainedPolicy {
  const { isSelectorless } = policy.header.value;

  let functionName: string | null = null;
  let abiInputs: readonly AbiParameter[] | undefined;

  if (options?.abi && !isSelectorless) {
    const matched = options.abi.find(
      (item): item is AbiFunction => item.type === "function" && toFunctionSelector(item) === policy.selector.value,
    );
    if (matched) {
      functionName = matched.name;
      abiInputs = matched.inputs;
    }
  }

  const nameTrees = abiInputs?.map(toNameTree) ?? [];
  const paramNodes = toParamNodes(policy.descriptor.params, nameTrees);

  const params: ExplainedParam[] = paramNodes.map((pn, i) => ({
    index: i,
    name: pn.name,
    type: pn.type,
    isDynamic: pn.isDynamic,
  }));

  const groups: ExplainedGroup[] = policy.groups.map((group) => ({
    rules: group.rules.map((rule) => ("body" in rule ? explainLoop(rule, paramNodes) : explainTest(rule, paramNodes))),
  }));

  return {
    selector: policy.selector.value,
    functionName,
    isSelectorless,
    params,
    groups,
    span: policy.span,
  };
}

/** Explain a test; a body test takes the steps of its loop, quantifier step included. */
function explainTest(test: DecodedTest, paramNodes: ParamNode[], loop?: number[]): ExplainedTest {
  const scope = test.scope.value;
  const path = test.path.value;
  const steps = parsePathSteps(path);
  let pathLabel: string;
  if (scope === Scope.CONTEXT) pathLabel = formatContextPath(steps[0]);
  else if (loop) pathLabel = formatBodyPath(loop, steps, paramNodes);
  else pathLabel = formatCalldataPath(steps, paramNodes);

  const { operator } = test;
  return {
    scope: lookupScope(scope).label,
    path,
    pathLabel,
    targetType: lookupTypeCode(test.targetType).label,
    operator: formatOpLabel(operator.opCode, operator.negated),
    negated: operator.negated,
    operands: decodeOperands(operator),
    arity: lookupOp(operator.opCode).operands,
    rule: test,
  };
}

/** Explain a loop and each test of its body. */
function explainLoop(loop: DecodedLoop, paramNodes: ParamNode[]): ExplainedLoop {
  const steps = loopSteps(loop.path.value, loop.quantifier.value);
  return {
    pathLabel: formatCalldataPath(steps, paramNodes),
    body: loop.body.map((test) => explainTest(test, paramNodes, steps)),
    rule: loop,
  };
}

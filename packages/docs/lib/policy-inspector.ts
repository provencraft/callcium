import {
  type DecodedLoop,
  type DecodedPolicy,
  type DecodedTest,
  DescriptorCoder,
  type Hex,
  hexToBytes,
  type Operands,
  Scope,
  type Span,
  lookupOp,
  lookupScope,
  lookupTypeCode,
  parsePathSteps,
  PolicyCoder,
} from "@callcium/sdk";
import { type Abi, type AbiFunction, toFunctionSelector } from "viem";
import { formatAbiItem } from "viem/utils";
import { formatError } from "./format-error";
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

/** The ABI function a policy's selector names, and the parameter trees named by its inputs. */
export function resolveParams(
  policy: DecodedPolicy,
  abi?: Abi,
): { abiFunction: AbiFunction | undefined; params: ParamNode[] } {
  const abiFunction = policy.header.value.isSelectorless
    ? undefined
    : abi?.find(
        (item): item is AbiFunction => item.type === "function" && toFunctionSelector(item) === policy.selector.value,
      );
  return { abiFunction, params: toParamNodes(policy.descriptor.params, abiFunction?.inputs.map(toNameTree) ?? []) };
}

export function explainPolicy(policy: DecodedPolicy, options?: ExplainOptions): ExplainedPolicy {
  const { isSelectorless } = policy.header.value;
  const { abiFunction, params: paramNodes } = resolveParams(policy, options?.abi);
  const functionName = abiFunction?.name ?? null;

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

/** An inspected and explained policy blob, or the error that stopped decoding. */
export type DecodeResult =
  | { ok: true; decoded: DecodedPolicy; explained: ExplainedPolicy; hex: string }
  | { ok: false; error: string };

/** Inspect and explain a policy blob, or null when the input is blank. */
export function tryDecode(hex: string, abi: Abi | undefined): DecodeResult | null {
  const trimmed = hex.trim();
  if (!trimmed) return null;
  const normalized = trimmed.startsWith("0x") ? trimmed : `0x${trimmed}`;
  try {
    const decoded = PolicyCoder.inspect(normalized as Hex);
    return { ok: true, decoded, explained: explainPolicy(decoded, abi ? { abi } : undefined), hex: normalized };
  } catch (error) {
    return { ok: false, error: formatError(error) };
  }
}

/**
 * The signature a decoded policy was built from. A function-bound policy takes its name from the ABI, or from
 * `functionName` when that name hashes to the policy's selector. Null when a function-bound policy gets no name.
 */
export function recoverSignature(
  result: Extract<DecodeResult, { ok: true }>,
  abi: Abi | undefined,
  functionName: string | null,
): string | null {
  const { span } = result.decoded.descriptor;
  const types = DescriptorCoder.toTypes(hexToBytes(result.hex).subarray(span.start, span.end));
  if (result.explained.isSelectorless) return types;
  const { abiFunction } = resolveParams(result.decoded, abi);
  if (abiFunction) return formatAbiItem(abiFunction, { includeName: true });
  const signature = `${functionName}(${types})`;
  return functionName && toFunctionSelector(signature) === result.explained.selector ? signature : null;
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

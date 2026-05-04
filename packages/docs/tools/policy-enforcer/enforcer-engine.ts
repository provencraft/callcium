import {
  type Context,
  type EnforceResult,
  type Hex,
  hexToBytes,
  PolicyCoder,
  PolicyEnforcer,
  type Violation,
} from "@callcium/sdk";
import { formatError } from "../../lib/format-error";
import { type ParamNode, parseDescriptor } from "../policy-builder/builder-engine";

///////////////////////////////////////////////////////////////////////////
// Types
///////////////////////////////////////////////////////////////////////////

export type EnforceOutput = {
  /** Three-state result. */
  status: "pass" | "fail" | "inconclusive" | "error";
  /** Violations that caused failure (VALUE_MISMATCH etc.). */
  violations: Violation[];
  /** Violations classified as skipped (MISSING_CONTEXT). */
  skipped: Violation[];
  /** Matched group index on pass. */
  matchedGroup?: number;
  /** Decoded descriptor parameter trees, used by the formatter for path labels. */
  params?: ParamNode[];
  /** Error message if the policy or calldata is malformed. */
  errorMessage?: string;
};

///////////////////////////////////////////////////////////////////////////
// Public API
///////////////////////////////////////////////////////////////////////////

/** Check a policy against calldata and classify the result. */
export function checkPolicy(policy: Hex, callData: Hex, context?: Context): EnforceOutput {
  // Decode once to surface descriptor params for downstream rendering. Re-uses
  // the same decoder PolicyEnforcer.check runs internally; the duplicate cost
  // is negligible at UI scale and keeps the engine surface clean.
  let params: ParamNode[] | undefined;
  try {
    const decoded = PolicyCoder.decode(policy);
    params = parseDescriptor(hexToBytes(decoded.descriptor));
  } catch {
    // Defer error reporting to PolicyEnforcer.check below — its diagnostics
    // are richer than a bare descriptor decode.
  }

  let result: EnforceResult;
  try {
    result = PolicyEnforcer.check(policy, callData, context);
  } catch (e) {
    return { status: "error", violations: [], skipped: [], errorMessage: formatError(e) };
  }

  if (result.ok) {
    return {
      status: "pass",
      violations: [],
      skipped: [],
      matchedGroup: result.matchedGroup,
      ...(params && { params }),
    };
  }

  // Separate MISSING_CONTEXT violations from real failures.
  const realViolations: Violation[] = [];
  const skipped: Violation[] = [];

  for (const v of result.violations) {
    if (v.code === "MISSING_CONTEXT") {
      skipped.push(v);
    } else {
      realViolations.push(v);
    }
  }

  if (realViolations.length === 0 && skipped.length > 0) {
    return { status: "inconclusive", violations: [], skipped, ...(params && { params }) };
  }

  return { status: "fail", violations: realViolations, skipped, ...(params && { params }) };
}

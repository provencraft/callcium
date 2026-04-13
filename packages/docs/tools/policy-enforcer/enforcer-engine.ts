import { type Context, type EnforceResult, type Hex, PolicyEnforcer, type Violation } from "@callcium/sdk";
import { formatError } from "../../lib/format-error";

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
  /** Error message if the policy or calldata is malformed. */
  errorMessage?: string;
};

///////////////////////////////////////////////////////////////////////////
// Public API
///////////////////////////////////////////////////////////////////////////

/** Check a policy against calldata and classify the result. */
export function checkPolicy(policy: Hex, callData: Hex, context?: Context): EnforceOutput {
  let result: EnforceResult;
  try {
    result = PolicyEnforcer.check(policy, callData, context);
  } catch (e) {
    return { status: "error", violations: [], skipped: [], errorMessage: formatError(e) };
  }

  if (result.ok) {
    return { status: "pass", violations: [], skipped: [], matchedGroup: result.matchedGroup };
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
    return { status: "inconclusive", violations: [], skipped };
  }

  return { status: "fail", violations: realViolations, skipped };
}

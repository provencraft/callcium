import {
  CallciumError,
  type Context,
  type DecodedPolicy,
  type EnforceResult,
  type Hex,
  PolicyCoder,
  PolicyEnforcer,
  type Violation,
} from "@callcium/sdk";
import { formatError } from "./format-error";

///////////////////////////////////////////////////////////////////////////
// Types
///////////////////////////////////////////////////////////////////////////

export type EnforceOutput =
  | {
      status: "error";
      /** Error message if the policy or calldata is malformed. */
      errorMessage: string;
    }
  | {
      /** Three-state result of a policy that decodes. */
      status: "pass" | "fail" | "inconclusive";
      /** Violations that caused failure (VALUE_MISMATCH etc.). */
      violations: Violation[];
      /** Violations classified as skipped (MISSING_CONTEXT). */
      skipped: Violation[];
      /** Matched group index on pass. */
      matchedGroup?: number;
      /** The inspected policy, used by the formatter for path labels. */
      policy: DecodedPolicy;
    };

///////////////////////////////////////////////////////////////////////////
// Public API
///////////////////////////////////////////////////////////////////////////

/** Check a policy against calldata and classify the result. */
export function checkPolicy(policy: Hex, callData: Hex, context?: Context): EnforceOutput {
  // Enforcement requires a policy that passes storage validation, which inspection runs.
  let inspected: DecodedPolicy;
  try {
    inspected = PolicyCoder.inspect(policy);
  } catch (e) {
    if (!(e instanceof CallciumError)) throw e;
    return { status: "error", errorMessage: formatError(e) };
  }

  let result: EnforceResult;
  try {
    result = PolicyEnforcer.check(policy, callData, context);
  } catch (e) {
    return { status: "error", errorMessage: formatError(e) };
  }

  if (result.ok) {
    return { status: "pass", violations: [], skipped: [], matchedGroup: result.matchedGroup, policy: inspected };
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
    return { status: "inconclusive", violations: [], skipped, policy: inspected };
  }

  return { status: "fail", violations: realViolations, skipped, policy: inspected };
}

import { bigintToHex } from "./bytes";

import type { Hex, Issue, IssueCode, RuleLocation } from "./types";

/** The zero word. */
const ZERO = bigintToHex(0n);

///////////////////////////////////////////////////////////////////////////
// Type mismatch
///////////////////////////////////////////////////////////////////////////

/** Issue for a descriptor whose composite node at `offset` disagrees with its children. */
export function invalidDescriptor(offset: number): Issue {
  return {
    severity: "error",
    category: "typeMismatch",
    code: "INVALID_DESCRIPTOR",
    value1: bigintToHex(BigInt(offset)),
    value2: ZERO,
    message: "Descriptor node metadata disagrees with its children",
  };
}

/** Issue for a path whose step at `stepIndex` breaks `bound`: a parameter, field or element count, or a type code. */
export function unnavigablePath(location: RuleLocation, stepIndex: number, bound: number): Issue {
  return {
    ...location,
    severity: "error",
    category: "typeMismatch",
    code: "UNNAVIGABLE_PATH",
    value1: bigintToHex(BigInt(stepIndex)),
    value2: bigintToHex(BigInt(bound)),
    message: "Path does not navigate the descriptor",
  };
}

/** Issue for a loop whose array path ends at a node of `typeCode`, which is not an array. */
export function quantifierOnNonArray(location: RuleLocation, typeCode: number): Issue {
  return {
    ...location,
    severity: "error",
    category: "typeMismatch",
    code: "QUANTIFIER_ON_NON_ARRAY",
    value1: bigintToHex(BigInt(typeCode)),
    value2: ZERO,
    message: "Loop path does not end at an array",
  };
}

/** Issue for a hint other than the compilation of its path. */
export function hintMismatch(location: RuleLocation): Issue {
  return {
    ...location,
    severity: "error",
    category: "typeMismatch",
    code: "HINT_MISMATCH",
    value1: ZERO,
    value2: ZERO,
    message: "Hint does not match the path compiled against the descriptor",
  };
}

/** Issue for an operator the compatibility matrix does not admit on its target type. */
export function fromOpRule(code: IssueCode, message: string, location: RuleLocation, opCode: number): Issue {
  return {
    ...location,
    severity: "error",
    category: "typeMismatch",
    code,
    value1: bigintToHex(BigInt(opCode)),
    value2: ZERO,
    message,
  };
}

/** Issue for a context operand whose property type does not pair with the target type. */
export function contextTypeMismatch(location: RuleLocation, contextPropertyId: number, typeCode: number): Issue {
  return {
    ...location,
    severity: "error",
    category: "typeMismatch",
    code: "CONTEXT_TYPE_MISMATCH",
    value1: bigintToHex(BigInt(contextPropertyId)),
    value2: bigintToHex(BigInt(typeCode)),
    message: "Context property type does not match the target type",
  };
}

///////////////////////////////////////////////////////////////////////////
// Contradiction
///////////////////////////////////////////////////////////////////////////

/** Issue for a constant outside its type's values. */
export function outOfPhysicalBounds(location: RuleLocation, value: Hex): Issue {
  return {
    ...location,
    severity: "error",
    category: "contradiction",
    code: "OUT_OF_PHYSICAL_BOUNDS",
    value1: value,
    value2: ZERO,
    message: "Value is outside the physical range of the type",
  };
}

/** Issue for the rule at which the rules on its subject, in order, stop being satisfiable together. */
export function contradictoryRule(location: RuleLocation): Issue {
  return {
    ...location,
    severity: "error",
    category: "contradiction",
    code: "CONTRADICTORY_RULE",
    value1: ZERO,
    value2: ZERO,
    message: "Rules on the subject are not satisfiable together",
  };
}

///////////////////////////////////////////////////////////////////////////
// Redundancy
///////////////////////////////////////////////////////////////////////////

/** Issue for a rule the other rules on its subject imply. */
export function redundantRule(location: RuleLocation): Issue {
  return {
    ...location,
    severity: "warning",
    category: "redundancy",
    code: "REDUNDANT_RULE",
    value1: ZERO,
    value2: ZERO,
    message: "Rule is implied by the other rules on its subject",
  };
}

/** Issue for a bound looser than `tightest`, the tightest bound on its side of the subject. */
export function dominatedBound(isLength: boolean, location: RuleLocation, bound: Hex, tightest: Hex): Issue {
  return {
    ...location,
    severity: "warning",
    category: "redundancy",
    code: isLength ? "DOMINATED_LENGTH_BOUND" : "DOMINATED_BOUND",
    value1: bound,
    value2: tightest,
    message: isLength
      ? "Length bound is dominated by a stricter bound"
      : "Numeric bound is dominated by a stricter bound",
  };
}

///////////////////////////////////////////////////////////////////////////
// Vacuity
///////////////////////////////////////////////////////////////////////////

/** Issue for a rule that holds for every value and every context. */
export function vacuousRule(location: RuleLocation): Issue {
  return {
    ...location,
    severity: "info",
    category: "vacuity",
    code: "VACUOUS_RULE",
    value1: ZERO,
    value2: ZERO,
    message: "Rule holds for every value",
  };
}

///////////////////////////////////////////////////////////////////////////
// Compatibility
///////////////////////////////////////////////////////////////////////////

/** Issue for a loop over a static array declared longer than `maxLength`. */
export function quantifierOverStaticLimit(location: RuleLocation, arrayLength: number, maxLength: number): Issue {
  return {
    ...location,
    severity: "error",
    category: "compatibility",
    code: "QUANTIFIER_OVER_STATIC_LIMIT",
    value1: bigintToHex(BigInt(arrayLength)),
    value2: bigintToHex(BigInt(maxLength)),
    message: "Quantifier over static array exceeds the maximum quantified length",
  };
}

/** Issue for a loop body that contains no test of the element. */
export function contextOnlyBody(location: RuleLocation): Issue {
  return {
    ...location,
    severity: "error",
    category: "compatibility",
    code: "CONTEXT_ONLY_BODY",
    value1: ZERO,
    value2: ZERO,
    message: "Loop body holds no test of the element",
  };
}

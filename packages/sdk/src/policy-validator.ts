import { bigintToHex, hexToBytes } from "./bytes";
import { lookupContextProperty, Op, Scope, TypeCode } from "./constants";
import { Descriptor, type TypeInfo } from "./descriptor";
import { isSigned, isLengthOp, isLengthValidType } from "./operators";
import { parsePathSteps } from "./policy-coder";
import * as Issues from "./validation-issue";
import { boundIssues, type BoundIssueSet } from "./validation-issue";

import type { Constraint, Hex, Issue, PolicyData } from "./types";

///////////////////////////////////////////////////////////////////////////
// Internal types
///////////////////////////////////////////////////////////////////////////

type BoundDomain = {
  isSigned: boolean;
  min: bigint;
  max: bigint;
  hasEq: boolean;
  eq: bigint;
  hasLower: boolean;
  lower: bigint;
  lowerInclusive: boolean;
  hasUpper: boolean;
  upper: bigint;
  upperInclusive: boolean;
  holes: bigint[];
};

type BitmaskDomain = {
  mustBeOne: bigint;
  mustBeZero: bigint;
};

type SetDomain = {
  hasIn: boolean;
  inValues: bigint[];
  notInValues: bigint[];
};

type ConstraintContext = {
  scope: number;
  path: Hex;
  typeInfo: TypeInfo;
  numeric: BoundDomain;
  bitmask: BitmaskDomain;
  length: BoundDomain;
  set: SetDomain;
};

///////////////////////////////////////////////////////////////////////////
// Constants
///////////////////////////////////////////////////////////////////////////

/**
 * Maximum number of tracked "holes" (neq exclusions) and notIn values per
 * domain. A hole is a single value excluded via a negated equality (neq).
 * During cross-operator analysis, holes punch values out of isIn sets — if
 * every member of an isIn set is excluded by holes or notIn, the constraint
 * is unsatisfiable (SET_FULLY_EXCLUDED). When only some are excluded, the
 * validator emits SET_PARTIALLY_EXCLUDED.
 *
 * Both caps are protocol-defined limits. Beyond these limits,
 * additional exclusions are silently ignored — the validator becomes
 * best-effort for set-reduction diagnostics but never produces false
 * positives, only potential false negatives (missed redundancy warnings).
 */
const MAX_HOLES = 8;
const MAX_NOT_IN = 8;
const LENGTH_MAX = 0xffffffffn;

// Mask for reinterpreting uint256 as int256 (two's complement).
const UINT256_MAX = (1n << 256n) - 1n;
const INT256_SIGN_BIT = 1n << 255n;

///////////////////////////////////////////////////////////////////////////
// Signed-aware comparisons
///////////////////////////////////////////////////////////////////////////

/** Reinterpret a uint256 bigint as a signed int256. */
function toSigned(v: bigint): bigint {
  return v >= INT256_SIGN_BIT ? v - (1n << 256n) : v;
}

/** a > b. */
function isGt(a: bigint, b: bigint, signed: boolean): boolean {
  return signed ? toSigned(a) > toSigned(b) : a > b;
}

/** a >= b. */
function isGte(a: bigint, b: bigint, signed: boolean): boolean {
  return signed ? toSigned(a) >= toSigned(b) : a >= b;
}

/** a < b. */
function isLt(a: bigint, b: bigint, signed: boolean): boolean {
  return signed ? toSigned(a) < toSigned(b) : a < b;
}

/** a <= b. */
function isLte(a: bigint, b: bigint, signed: boolean): boolean {
  return signed ? toSigned(a) <= toSigned(b) : a <= b;
}

///////////////////////////////////////////////////////////////////////////
// Type classification
///////////////////////////////////////////////////////////////////////////

/** True for uint and int type codes. */
function isNumericType(typeCode: number): boolean {
  return typeCode <= TypeCode.UINT_MAX || (typeCode >= TypeCode.INT_MIN && typeCode <= TypeCode.INT_MAX);
}

/** True for uint and bytes32 type codes. */
function isBitmaskCompatible(typeCode: number): boolean {
  return typeCode <= TypeCode.UINT_MAX || typeCode === TypeCode.FIXED_BYTES_MIN + 31;
}

/** Physical domain limits for a type code (returned as raw uint256 bigints). */
function getDomainLimits(typeCode: number): { min: bigint; max: bigint } {
  if (typeCode <= TypeCode.UINT_MAX) {
    const bits = BigInt(typeCode - TypeCode.UINT_MIN + 1) * 8n;
    return { min: 0n, max: bits === 256n ? UINT256_MAX : (1n << bits) - 1n };
  }
  if (typeCode >= TypeCode.INT_MIN && typeCode <= TypeCode.INT_MAX) {
    const bits = BigInt(typeCode - TypeCode.INT_MIN + 1) * 8n;
    if (bits === 256n) {
      // int256: min = uint256(type(int256).min), max = uint256(type(int256).max).
      return { min: INT256_SIGN_BIT, max: INT256_SIGN_BIT - 1n };
    }
    const half = 1n << (bits - 1n);
    // Stored as raw uint256: min is two's complement of -(2^(bits-1)).
    const max = half - 1n;
    const min = (UINT256_MAX - half + 1n) & UINT256_MAX;
    return { min, max };
  }
  if (typeCode === TypeCode.BOOL) return { min: 0n, max: 1n };
  if (typeCode === TypeCode.ADDRESS) return { min: 0n, max: (1n << 160n) - 1n };
  return { min: 0n, max: UINT256_MAX };
}

///////////////////////////////////////////////////////////////////////////
// Operator classification
///////////////////////////////////////////////////////////////////////////

/** True for EQ, GT, LT, GTE, LTE, BETWEEN, IN, BITMASK_*. */
function isValueOp(opBase: number): boolean {
  return opBase <= Op.BITMASK_NONE;
}

/** True for GT, LT, GTE, LTE, BETWEEN. */
function isComparisonOp(opBase: number): boolean {
  return opBase >= Op.GT && opBase <= Op.BETWEEN;
}

/** True for BITMASK_ALL, BITMASK_ANY, BITMASK_NONE. */
function isBitmaskOp(opBase: number): boolean {
  return opBase >= Op.BITMASK_ALL && opBase <= Op.BITMASK_NONE;
}

///////////////////////////////////////////////////////////////////////////
// Type compatibility check
///////////////////////////////////////////////////////////////////////////

/** Return the incompatibility reason, or null if the operator is allowed. */
function getIncompat(opBase: number, typeInfo: TypeInfo): { code: string; message: string } | null {
  const { typeCode, isDynamic, staticSize } = typeInfo;
  if (isValueOp(opBase)) {
    if (isDynamic || staticSize !== 32) {
      return { code: "VALUE_OP_ON_DYNAMIC", message: "Value operator used on dynamic type" };
    }
    if (isComparisonOp(opBase) && !isNumericType(typeCode)) {
      return { code: "NUMERIC_OP_ON_NON_NUMERIC", message: "Comparison operator used on non-numeric type" };
    }
    if (isBitmaskOp(opBase) && !isBitmaskCompatible(typeCode)) {
      return { code: "BITMASK_ON_INVALID", message: "Bitmask operator used on incompatible type" };
    }
    return null;
  }
  if (isLengthOp(opBase)) {
    if (!isLengthValidType(typeCode)) {
      return { code: "LENGTH_ON_STATIC", message: "Length operator used on non-dynamic type" };
    }
    return null;
  }
  return { code: "UNKNOWN_OPERATOR", message: "Unknown operator code" };
}

/** Check operator–type compatibility and return an issue descriptor on mismatch. */
function checkCompatibility(
  opBase: number,
  typeCode: number,
  isDynamic: boolean,
  staticSize: number,
): { compatible: boolean; code: string; message: string } {
  const incompat = getIncompat(opBase, { typeCode, isDynamic, staticSize });
  return incompat ? { compatible: false, ...incompat } : { compatible: true, code: "", message: "" };
}

/**
 * True if operator `opCode` is allowed on a target with the given type info.
 * Tolerates the NOT flag on `opCode`.
 */
export function isOpAllowed(opCode: number, typeInfo: TypeInfo): boolean {
  return getIncompat(opCode & ~Op.NOT, typeInfo) === null;
}

///////////////////////////////////////////////////////////////////////////
// Payload reading
///////////////////////////////////////////////////////////////////////////

/** Read a single uint256 from operator hex (bytes after the opcode byte). */
function readValue(opHex: Hex): bigint {
  return BigInt(`0x${opHex.slice(4)}`);
}

/** Read a pair of uint256 values from a BETWEEN operator. */
function readPair(opHex: Hex): { low: bigint; high: bigint } {
  const body = opHex.slice(4);
  return {
    low: BigInt(`0x${body.slice(0, 64)}`),
    high: BigInt(`0x${body.slice(64, 128)}`),
  };
}

/** Unpack an IN operator's payload into an array of bigint values. */
function unpackSet(opHex: Hex): bigint[] {
  const body = opHex.slice(4);
  const count = body.length / 64;
  const values: bigint[] = [];
  for (let i = 0; i < count; i++) {
    values.push(BigInt(`0x${body.slice(i * 64, (i + 1) * 64)}`));
  }
  return values;
}

/** True if every element is strictly greater than the previous. */
function isStrictlyAscending(values: bigint[]): boolean {
  for (let i = 1; i < values.length; i++) {
    if (values[i]! <= values[i - 1]!) return false;
  }
  return true;
}

///////////////////////////////////////////////////////////////////////////
// Opcode normalization
///////////////////////////////////////////////////////////////////////////

/** Convert LENGTH_* opcode to its core comparison equivalent. */
function normalizeLengthOp(base: number): number {
  if (base === Op.LENGTH_EQ) return Op.EQ;
  if (base === Op.LENGTH_GT) return Op.GT;
  if (base === Op.LENGTH_LT) return Op.LT;
  if (base === Op.LENGTH_GTE) return Op.GTE;
  if (base === Op.LENGTH_LTE) return Op.LTE;
  return base;
}

/** Convert a negated bound opcode to its positive equivalent. */
function negateBoundOp(base: number): number {
  if (base === Op.GT) return Op.LTE;
  if (base === Op.GTE) return Op.LT;
  if (base === Op.LT) return Op.GTE;
  if (base === Op.LTE) return Op.GT;
  return base;
}

///////////////////////////////////////////////////////////////////////////
// Context initialization
///////////////////////////////////////////////////////////////////////////

/** Create a fresh constraint context with domain limits from the type. */
function initContext(scope: number, path: Hex, typeInfo: TypeInfo): ConstraintContext {
  const { min, max } = getDomainLimits(typeInfo.typeCode);
  return {
    scope,
    path,
    typeInfo,
    numeric: {
      isSigned: isSigned(typeInfo.typeCode),
      min,
      max,
      hasEq: false,
      eq: 0n,
      hasLower: false,
      lower: 0n,
      lowerInclusive: false,
      hasUpper: false,
      upper: 0n,
      upperInclusive: false,
      holes: [],
    },
    bitmask: { mustBeOne: 0n, mustBeZero: 0n },
    length: {
      isSigned: false,
      min: 0n,
      max: LENGTH_MAX,
      hasEq: false,
      eq: 0n,
      hasLower: false,
      lower: 0n,
      lowerInclusive: false,
      hasUpper: false,
      upper: 0n,
      upperInclusive: false,
      holes: [],
    },
    set: {
      hasIn: false,
      inValues: [],
      notInValues: [],
    },
  };
}

///////////////////////////////////////////////////////////////////////////
// Bound domain update
///////////////////////////////////////////////////////////////////////////

/** Narrow the numeric bound domain with an operator and emit issues on contradiction or redundancy. */
function updateBound(
  domain: BoundDomain,
  base: number,
  isNegated: boolean,
  value: bigint,
  emit: BoundIssueSet,
  groupIndex: number,
  constraintIndex: number,
  issues: Issue[],
): void {
  let changedEq = false;
  let changedLower = false;
  let changedUpper = false;

  // Negation handling.
  if (isNegated) {
    if (base === Op.EQ) {
      if (domain.hasEq && domain.eq === value) {
        issues.push(emit.eqNeqContradiction(groupIndex, constraintIndex, bigintToHex(value)));
      }
      let alreadyHole = false;
      for (let j = 0; j < domain.holes.length; j++) {
        if (domain.holes[j] === value) {
          alreadyHole = true;
          break;
        }
      }
      if (!alreadyHole && domain.holes.length < MAX_HOLES) {
        domain.holes.push(value);
      }
    } else {
      updateBound(domain, negateBoundOp(base), false, value, emit, groupIndex, constraintIndex, issues);
    }
    return;
  }

  // Vacuity checks.
  if (base === Op.GTE && value === domain.min) {
    issues.push(emit.vacuousGte(groupIndex, constraintIndex, bigintToHex(value)));
  } else if (base === Op.LTE && value === domain.max) {
    issues.push(emit.vacuousLte(groupIndex, constraintIndex, bigintToHex(value)));
  }

  // Physical bounds and impossibility.
  if (isLt(value, domain.min, domain.isSigned) || isGt(value, domain.max, domain.isSigned)) {
    issues.push(emit.outOfPhysicalBounds(groupIndex, constraintIndex, bigintToHex(value)));
  } else if (base === Op.GT && value === domain.max) {
    issues.push(emit.impossibleGt(groupIndex, constraintIndex, bigintToHex(value)));
  } else if (base === Op.LT && value === domain.min) {
    issues.push(emit.impossibleLt(groupIndex, constraintIndex, bigintToHex(value)));
  }

  // Equality handling.
  if (base === Op.EQ) {
    if (!domain.hasEq || domain.eq !== value) changedEq = true;
    if (domain.hasEq) {
      if (domain.eq !== value) {
        issues.push(emit.conflicting(groupIndex, constraintIndex, bigintToHex(domain.eq), bigintToHex(value)));
      }
    }
    for (let j = 0; j < domain.holes.length; j++) {
      if (domain.holes[j] === value) {
        issues.push(emit.eqNeqContradiction(groupIndex, constraintIndex, bigintToHex(value)));
      }
    }
    domain.hasEq = true;
    domain.eq = value;
  } else if (base === Op.GT || base === Op.GTE) {
    const inclusive = base === Op.GTE;
    if (domain.hasLower) {
      let redundant = false;
      let strictlyBetter = false;

      if (isLt(value, domain.lower, domain.isSigned)) {
        redundant = true;
      } else if (value === domain.lower) {
        if (domain.lowerInclusive) {
          if (!inclusive) strictlyBetter = true;
          else redundant = true;
        } else {
          if (!inclusive) redundant = true;
        }
      } else {
        strictlyBetter = true;
      }

      if (redundant) {
        issues.push(emit.dominated(groupIndex, constraintIndex, bigintToHex(value)));
      }

      if (strictlyBetter) {
        domain.lower = value;
        domain.lowerInclusive = inclusive;
        changedLower = true;
      }
    } else {
      domain.hasLower = true;
      domain.lower = value;
      domain.lowerInclusive = inclusive;
      changedLower = true;
    }
  } else if (base === Op.LT || base === Op.LTE) {
    const inclusive = base === Op.LTE;
    if (domain.hasUpper) {
      let redundant = false;
      let strictlyBetter = false;

      if (isGt(value, domain.upper, domain.isSigned)) {
        redundant = true;
      } else if (value === domain.upper) {
        if (domain.upperInclusive) {
          if (!inclusive) strictlyBetter = true;
          else redundant = true;
        } else {
          if (!inclusive) redundant = true;
        }
      } else {
        strictlyBetter = true;
      }

      if (redundant) {
        issues.push(emit.dominated(groupIndex, constraintIndex, bigintToHex(value)));
      }

      if (strictlyBetter) {
        domain.upper = value;
        domain.upperInclusive = inclusive;
        changedUpper = true;
      }
    } else {
      domain.hasUpper = true;
      domain.upper = value;
      domain.upperInclusive = inclusive;
      changedUpper = true;
    }
  }

  // Cross-checks: equality vs lower bound.
  if (changedEq || changedLower) {
    if (domain.hasEq && domain.hasLower) {
      const contradiction = domain.lowerInclusive
        ? isLt(domain.eq, domain.lower, domain.isSigned)
        : isLte(domain.eq, domain.lower, domain.isSigned);
      if (contradiction) {
        issues.push(
          emit.boundsExcludeEquality(groupIndex, constraintIndex, bigintToHex(domain.eq), bigintToHex(domain.lower)),
        );
      } else {
        issues.push(emit.redundant(groupIndex, constraintIndex, bigintToHex(domain.lower), bigintToHex(domain.eq)));
      }
    }
  }

  // Cross-checks: equality vs upper bound.
  if (changedEq || changedUpper) {
    if (domain.hasEq && domain.hasUpper) {
      const contradiction = domain.upperInclusive
        ? isGt(domain.eq, domain.upper, domain.isSigned)
        : isGte(domain.eq, domain.upper, domain.isSigned);
      if (contradiction) {
        issues.push(
          emit.boundsExcludeEquality(groupIndex, constraintIndex, bigintToHex(domain.eq), bigintToHex(domain.upper)),
        );
      } else {
        issues.push(emit.redundant(groupIndex, constraintIndex, bigintToHex(domain.upper), bigintToHex(domain.eq)));
      }
    }
  }

  // Cross-check: lower vs upper bound.
  if (changedLower || changedUpper) {
    if (domain.hasLower && domain.hasUpper) {
      const impossible =
        isGt(domain.lower, domain.upper, domain.isSigned) ||
        (domain.lower === domain.upper && (!domain.lowerInclusive || !domain.upperInclusive));
      if (impossible) {
        issues.push(
          emit.impossibleRange(groupIndex, constraintIndex, bigintToHex(domain.lower), bigintToHex(domain.upper)),
        );
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////
// Bitmask domain update
///////////////////////////////////////////////////////////////////////////

/** Update the bitmask domain and emit issues on contradiction or redundancy. */
function updateBitmask(
  ctx: ConstraintContext,
  base: number,
  isNegated: boolean,
  mask: bigint,
  groupIndex: number,
  constraintIndex: number,
  issues: Issue[],
): void {
  if (isNegated) return;

  if (base === Op.BITMASK_ALL) {
    if ((ctx.bitmask.mustBeZero & mask) !== 0n) {
      issues.push(
        Issues.bitmaskContradiction(
          groupIndex,
          constraintIndex,
          bigintToHex(mask),
          bigintToHex(ctx.bitmask.mustBeZero),
        ),
      );
    }
    if ((ctx.bitmask.mustBeOne & mask) === mask) {
      issues.push(
        Issues.redundantBitmask(groupIndex, constraintIndex, bigintToHex(mask), bigintToHex(ctx.bitmask.mustBeOne)),
      );
    }
    ctx.bitmask.mustBeOne |= mask;
  } else if (base === Op.BITMASK_NONE) {
    if ((ctx.bitmask.mustBeOne & mask) !== 0n) {
      issues.push(
        Issues.bitmaskContradiction(groupIndex, constraintIndex, bigintToHex(mask), bigintToHex(ctx.bitmask.mustBeOne)),
      );
    }
    if ((ctx.bitmask.mustBeZero & mask) === mask) {
      issues.push(
        Issues.redundantBitmask(groupIndex, constraintIndex, bigintToHex(mask), bigintToHex(ctx.bitmask.mustBeZero)),
      );
    }
    ctx.bitmask.mustBeZero |= mask;
  } else if (base === Op.BITMASK_ANY) {
    if (mask !== 0n && (ctx.bitmask.mustBeZero & mask) === mask) {
      issues.push(
        Issues.bitmaskAnyImpossible(
          groupIndex,
          constraintIndex,
          bigintToHex(mask),
          bigintToHex(ctx.bitmask.mustBeZero),
        ),
      );
    }
    if ((ctx.bitmask.mustBeOne & mask) !== 0n) {
      issues.push(
        Issues.redundantBitmask(groupIndex, constraintIndex, bigintToHex(mask), bigintToHex(ctx.bitmask.mustBeOne)),
      );
    }
  }
}

///////////////////////////////////////////////////////////////////////////
// Set domain update
///////////////////////////////////////////////////////////////////////////

/** Emit an issue if the IN set has been fully excluded by NOT_IN or NEQ holes. */
function checkSetEmpty(ctx: ConstraintContext, groupIndex: number, constraintIndex: number, issues: Issue[]): void {
  if (!ctx.set.hasIn) return;

  let possibleCount = 0;
  const inCount = ctx.set.inValues.length;
  for (let i = 0; i < inCount; i++) {
    const val = ctx.set.inValues[i]!;
    let forbidden = false;
    for (let k = 0; k < ctx.numeric.holes.length; k++) {
      if (ctx.numeric.holes[k] === val) {
        forbidden = true;
        break;
      }
    }
    if (!forbidden) {
      for (let k = 0; k < ctx.set.notInValues.length; k++) {
        if (ctx.set.notInValues[k] === val) {
          forbidden = true;
          break;
        }
      }
    }
    if (!forbidden) possibleCount++;
  }

  if (possibleCount === 0) {
    issues.push(Issues.setFullyExcluded(groupIndex, constraintIndex));
  } else if (possibleCount < inCount) {
    issues.push(Issues.setPartiallyExcluded(groupIndex, constraintIndex, bigintToHex(BigInt(inCount - possibleCount))));
  }
}

/** Update the set domain with IN or NOT_IN values and emit issues on contradiction or redundancy. */
function updateSet(
  ctx: ConstraintContext,
  isNegated: boolean,
  values: bigint[],
  groupIndex: number,
  constraintIndex: number,
  issues: Issue[],
): void {
  if (isNegated) {
    for (const val of values) {
      if (ctx.numeric.hasEq && ctx.numeric.eq === val) {
        issues.push(Issues.setExcludesEquality(groupIndex, constraintIndex, bigintToHex(val)));
      }
      if (ctx.set.hasIn) {
        let inSet = false;
        for (const iv of ctx.set.inValues) {
          if (iv === val) {
            inSet = true;
            break;
          }
        }
        if (inSet) {
          issues.push(Issues.setReduction(groupIndex, constraintIndex, bigintToHex(val)));
        }
      }
      if (ctx.set.notInValues.length < MAX_NOT_IN) {
        ctx.set.notInValues.push(val);
      }
    }
    checkSetEmpty(ctx, groupIndex, constraintIndex, issues);
  } else {
    if (ctx.numeric.hasEq) {
      let found = false;
      for (const v of values) {
        if (v === ctx.numeric.eq) {
          found = true;
          break;
        }
      }
      if (!found) {
        issues.push(Issues.setExcludesEquality(groupIndex, constraintIndex, bigintToHex(ctx.numeric.eq)));
      }
    }

    if (ctx.set.hasIn) {
      const intersection: bigint[] = [];
      for (const existing of ctx.set.inValues) {
        for (const v of values) {
          if (existing === v) {
            intersection.push(existing);
            break;
          }
        }
      }

      if (intersection.length === 0) {
        issues.push(Issues.emptySetIntersection(groupIndex, constraintIndex));
      } else if (intersection.length < values.length || intersection.length < ctx.set.inValues.length) {
        issues.push(Issues.setRedundancy(groupIndex, constraintIndex, bigintToHex(BigInt(intersection.length))));
      }
      ctx.set.inValues = intersection;
    } else {
      ctx.set.hasIn = true;
      ctx.set.inValues = values;
    }

    checkSetEmpty(ctx, groupIndex, constraintIndex, issues);
  }
}

///////////////////////////////////////////////////////////////////////////
// Duplicate detection
///////////////////////////////////////////////////////////////////////////

/** Emit a warning if the constraint contains any identical operators. */
function checkDuplicates(issues: Issue[], operators: Hex[], groupIndex: number, constraintIndex: number): void {
  const seen = new Set<string>();
  for (const op of operators) {
    const key = op.toLowerCase();
    if (seen.has(key)) {
      issues.push(Issues.duplicateConstraint(groupIndex, constraintIndex));
      return;
    }
    seen.add(key);
  }
}

///////////////////////////////////////////////////////////////////////////
// Constraint validation
///////////////////////////////////////////////////////////////////////////

/** Validate all operators on a single constraint against its domain context. */
function validateConstraint(
  ctx: ConstraintContext,
  constraint: Constraint,
  groupIndex: number,
  constraintIndex: number,
  issues: Issue[],
): void {
  const operators = constraint.operators;

  for (const opHex of operators) {
    const opCode = parseInt(opHex.slice(2, 4), 16);
    const base = opCode & ~Op.NOT;
    const isNegated = (opCode & Op.NOT) !== 0;

    const compat = checkCompatibility(base, ctx.typeInfo.typeCode, ctx.typeInfo.isDynamic, ctx.typeInfo.staticSize);
    if (!compat.compatible) {
      issues.push(
        Issues.fromOpRule(compat.code, compat.message, groupIndex, constraintIndex, bigintToHex(BigInt(opCode))),
      );
      continue;
    }

    if (isValueOp(base)) {
      if (base >= Op.EQ && base <= Op.BETWEEN) {
        if (base === Op.BETWEEN) {
          const { low, high } = readPair(opHex);
          updateBound(ctx.numeric, Op.GTE, isNegated, low, boundIssues(false), groupIndex, constraintIndex, issues);
          updateBound(ctx.numeric, Op.LTE, isNegated, high, boundIssues(false), groupIndex, constraintIndex, issues);
        } else {
          const value = readValue(opHex);
          const holesBefore = ctx.numeric.holes.length;
          updateBound(ctx.numeric, base, isNegated, value, boundIssues(false), groupIndex, constraintIndex, issues);
          if (ctx.numeric.holes.length > holesBefore) {
            checkSetEmpty(ctx, groupIndex, constraintIndex, issues);
          }
        }
      } else if (isBitmaskOp(base)) {
        const mask = readValue(opHex);
        updateBitmask(ctx, base, isNegated, mask, groupIndex, constraintIndex, issues);
      } else if (base === Op.IN) {
        const values = unpackSet(opHex);
        if (!isStrictlyAscending(values)) {
          issues.push(Issues.unsortedInSet(groupIndex, constraintIndex));
        } else {
          updateSet(ctx, isNegated, values, groupIndex, constraintIndex, issues);
        }
      }
    } else if (isLengthOp(base)) {
      if (base === Op.LENGTH_BETWEEN) {
        const { low, high } = readPair(opHex);
        updateBound(ctx.length, Op.GTE, isNegated, low, boundIssues(true), groupIndex, constraintIndex, issues);
        updateBound(ctx.length, Op.LTE, isNegated, high, boundIssues(true), groupIndex, constraintIndex, issues);
      } else {
        const value = readValue(opHex);
        updateBound(
          ctx.length,
          normalizeLengthOp(base),
          isNegated,
          value,
          boundIssues(true),
          groupIndex,
          constraintIndex,
          issues,
        );
      }
    }
  }

  checkDuplicates(issues, operators, groupIndex, constraintIndex);
}

///////////////////////////////////////////////////////////////////////////
// Group validation
///////////////////////////////////////////////////////////////////////////

/** Validate all constraints in a group, building per-path contexts for cross-constraint analysis. */
function validateGroup(data: PolicyData, descBytes: Uint8Array, groupIndex: number, issues: Issue[]): void {
  const constraints = data.groups[groupIndex]!;
  const contexts: ConstraintContext[] = [];

  for (let constraintIndex = 0; constraintIndex < constraints.length; constraintIndex++) {
    const constraint = constraints[constraintIndex]!;
    const normalizedPath: Hex = `0x${constraint.path.slice(2).toLowerCase()}`;

    // Find existing context for this (scope, path) pair.
    let ctx: ConstraintContext | undefined;
    for (const existing of contexts) {
      if (existing.scope === constraint.scope && existing.path === normalizedPath) {
        ctx = existing;
        break;
      }
    }

    if (!ctx) {
      let typeInfo: TypeInfo;
      if (constraint.scope === Scope.CALLDATA) {
        const steps = parsePathSteps(constraint.path);
        typeInfo = Descriptor.typeAt(descBytes, steps);
      } else {
        const steps = parsePathSteps(constraint.path);
        const ctxId = steps[0]!;
        const typeCode = lookupContextProperty(ctxId).typeCode;
        typeInfo = { typeCode, isDynamic: false, staticSize: 32 };
      }
      ctx = initContext(constraint.scope, normalizedPath, typeInfo);
      contexts.push(ctx);
    }

    validateConstraint(ctx, constraint, groupIndex, constraintIndex, issues);
  }
}

///////////////////////////////////////////////////////////////////////////
// Public API
///////////////////////////////////////////////////////////////////////////

/**
 * Validate a policy for type mismatches, contradictions, redundancies, and vacuities.
 * @param data - The canonical policy data to validate.
 * @returns All validation issues found, ordered by group and constraint index.
 */
function validate(data: PolicyData): Issue[] {
  const issues: Issue[] = [];
  const descBytes = hexToBytes(data.descriptor);

  for (let groupIndex = 0; groupIndex < data.groups.length; groupIndex++) {
    if (data.groups[groupIndex]!.length === 0) {
      issues.push(Issues.emptyGroup(groupIndex));
      continue;
    }
    validateGroup(data, descBytes, groupIndex, issues);
  }

  return issues;
}

/** Semantic validation for policies. */
export const PolicyValidator = { validate };

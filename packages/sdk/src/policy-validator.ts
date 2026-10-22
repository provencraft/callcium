import { bigintToHex, bytesToHex, hexToBytes, readU16 } from "./bytes";
import {
  comparisonOf,
  isComparisonCode,
  MAX_CONTEXT_PROPERTY_ID,
  Op,
  PolicyFormat as PF,
  Scope,
  Source,
  sourceOf,
  TypeCode,
} from "./constants";
import { Descriptor } from "./descriptor";
import { Hint } from "./hint";
import {
  acceptsContextSource,
  contextPropertyType,
  hasCalldataLength,
  isLeftAligned,
  isSigned,
  operandTypeOf,
  operandWidth,
  toBigInt,
} from "./operators";
import { parsePathSteps } from "./path";
import { PolicyCoder, validatePolicy } from "./policy-coder";
import * as ValidationIssue from "./validation-issue";

import type { BodyRule, Hex, Issue, IssueCode, LoopRule, Rule, RuleLocation } from "./types";

///////////////////////////////////////////////////////////////////////////
// Compatibility
///////////////////////////////////////////////////////////////////////////

/** Return true for a `uintN` type code. */
function isUnsigned(typeCode: number): boolean {
  return typeCode >= TypeCode.UINT_MIN && typeCode <= TypeCode.UINT_MAX;
}

/** Return true for a `uintN` or `intN` type code. */
function isNumeric(typeCode: number): boolean {
  return isUnsigned(typeCode) || (typeCode >= TypeCode.INT_MIN && typeCode <= TypeCode.INT_MAX);
}

/** Return the code and message a constant comparison raises against its target type, or undefined when it applies. */
function incompatibility(comparison: number, typeCode: number): { code: IssueCode; message: string } | undefined {
  const isOrdering =
    comparison === Op.GT ||
    comparison === Op.LT ||
    comparison === Op.GTE ||
    comparison === Op.LTE ||
    comparison === Op.BETWEEN;
  if (isOrdering && !isNumeric(typeCode)) {
    return { code: "NUMERIC_OP_ON_NON_NUMERIC", message: "Comparison operator used on non-numeric type" };
  }
  if (comparison === Op.IN && typeCode === TypeCode.BOOL) {
    return { code: "IN_ON_BOOL", message: "IN operator used on boolean type" };
  }
  const isMask = comparison === Op.BITMASK_ALL || comparison === Op.BITMASK_ANY || comparison === Op.BITMASK_NONE;
  if (isMask && (typeCode === TypeCode.BOOL || typeCode === TypeCode.FUNCTION)) {
    return { code: "BITMASK_ON_INVALID", message: "Bitmask operator used on incompatible type" };
  }
  return undefined;
}

/** Return true when a context operand of `propertyType` pairs with a target of `typeCode` under `comparison`. */
function pairsWithContext(comparison: number, typeCode: number, propertyType: number): boolean {
  if (isUnsigned(typeCode)) return propertyType === TypeCode.UINT_MAX;
  return comparison === Op.EQ && typeCode === TypeCode.ADDRESS && propertyType === TypeCode.ADDRESS;
}

/**
 * Determine whether the compatibility matrix admits an operator on a target type. A context operand is admitted on a
 * target its comparison can pair with a context property. These targets are `uintN` under `EQ`, `GT`, `LT`, `GTE` and
 * `LTE`, and `address` under `EQ`.
 * @param opCode - The operator code, with or without the NOT flag.
 * @param typeCode - The target's type code.
 * @returns True when the operator applies to the target.
 */
export function isOpAllowed(opCode: number, typeCode: number): boolean {
  const comparison = comparisonOf(opCode);
  if (!isComparisonCode(comparison)) return false;
  if (sourceOf(opCode) === Source.CONTEXT) {
    if (!acceptsContextSource(comparison)) return false;
    return isUnsigned(typeCode) || (comparison === Op.EQ && typeCode === TypeCode.ADDRESS);
  }
  if (sourceOf(opCode) !== Source.CONSTANT) return false;
  return operandTypeOf(comparison, typeCode) !== undefined && incompatibility(comparison, typeCode) === undefined;
}

///////////////////////////////////////////////////////////////////////////
// Rule checks
///////////////////////////////////////////////////////////////////////////

/**
 * Push the PV-5 and PV-6 issues of a test's operator against a target of `typeCode`.
 * Return true when the operator raises none.
 */
function checkOperator(test: BodyRule, typeCode: number, location: RuleLocation, issues: Issue[]): boolean {
  const operator = hexToBytes(test.operator);
  const opCode = operator[0]!;
  const comparison = comparisonOf(opCode);
  if (sourceOf(opCode) === Source.CONTEXT) {
    const propertyId = Number(toBigInt(operator, 1));
    if (pairsWithContext(comparison, typeCode, contextPropertyType(propertyId))) return true;
    issues.push(ValidationIssue.contextTypeMismatch(location, propertyId, typeCode));
    return false;
  }

  const incompatible = incompatibility(comparison, typeCode);
  if (incompatible !== undefined) {
    issues.push(ValidationIssue.fromOpRule(incompatible.code, incompatible.message, location, opCode));
    return false;
  }
  if (typeCode !== TypeCode.BOOL) return true;
  for (let offset = 1; offset < operator.length; offset += 32) {
    const value = toBigInt(operator, offset);
    if (value > 1n) {
      issues.push(ValidationIssue.outOfPhysicalBounds(location, bigintToHex(value)));
      return false;
    }
  }
  return true;
}

/**
 * Push the issues of a test, from the arguments or, given `element`, from the loop element whose node lies there.
 * Returns the test, or undefined when an issue leaves it without a target to analyze or its hint differs from its
 * path's.
 */
function checkTest(
  desc: Uint8Array,
  test: BodyRule,
  element: number | undefined,
  location: RuleLocation,
  issues: Issue[],
): BodyRule | undefined {
  let typeCode: number;
  let hintMatches = true;
  if (test.scope === Scope.CONTEXT) {
    typeCode = contextPropertyType(readU16(hexToBytes(test.path), 0));
  } else {
    const compiled = Hint.compileTest(desc, parsePathSteps(test.path), element);
    if ("fault" in compiled) {
      issues.push(ValidationIssue.unnavigablePath(location, compiled.stepIndex, compiled.bound));
      return undefined;
    }
    hintMatches = bytesToHex(compiled.hint) === test.hint;
    if (!hintMatches) issues.push(ValidationIssue.hintMismatch(location));
    typeCode = desc[compiled.node]!;
  }
  // A test whose hint differs from its path's has constants sized to the hint's type, so it leaves the analysis.
  return checkOperator(test, typeCode, location, issues) && hintMatches ? test : undefined;
}

/** Return the declared length a loop's frame hint carries, or zero for a dynamic array. */
function frameCount(hint: Uint8Array): number {
  const hopCount = hint[0]!;
  return readU16(hint, PF.HINT_HEADER_SIZE + hopCount * PF.HINT_HOP_SIZE + PF.HINT_FRAME_COUNT_OFFSET);
}

/**
 * Push the issues of a loop and its body. Returns the loop without the body tests left without a target. The result is
 * undefined when the loop's array path does not compile or no body test is left.
 */
function checkLoop(desc: Uint8Array, loop: LoopRule, location: RuleLocation, issues: Issue[]): LoopRule | undefined {
  const compiled = Hint.compileLoop(desc, parsePathSteps(loop.path));
  if ("fault" in compiled) {
    issues.push(
      compiled.fault === "NOT_ARRAY"
        ? ValidationIssue.quantifierOnNonArray(location, compiled.bound)
        : ValidationIssue.unnavigablePath(location, compiled.stepIndex, compiled.bound),
    );
    return undefined;
  }
  if (bytesToHex(compiled.hint) !== loop.hint) issues.push(ValidationIssue.hintMismatch(location));
  const count = frameCount(compiled.hint);
  if (count > PF.MAX_QUANTIFIED_ARRAY_LENGTH) {
    issues.push(ValidationIssue.quantifierOverStaticLimit(location, count, PF.MAX_QUANTIFIED_ARRAY_LENGTH));
  }

  const body: BodyRule[] = [];
  loop.body.forEach((test, bodyRuleIndex) => {
    const testLocation = { ...location, bodyRuleIndex, scope: test.scope, path: test.path, operator: test.operator };
    const kept = checkTest(desc, test, compiled.node, testLocation, issues);
    if (kept !== undefined) body.push(kept);
  });
  return body.length === 0 ? undefined : { ...loop, body };
}

/** The identity of a loop within its group across normalization: its quantifier and its array path. */
function loopKey(loop: LoopRule): string {
  return `${loop.quantifier}:${loop.path}`;
}

/**
 * Push a PV-8 issue for each loop of a group's normal form whose body contains no calldata test. Skip a loop if the
 * group lost a test from a loop with the same quantifier and array path.
 */
function checkBodies(rules: Rule[], groupIndex: number, lost: ReadonlySet<string>, issues: Issue[]): void {
  rules.forEach((rule, ruleIndex) => {
    if (rule.scope !== Scope.LOOP || lost.has(loopKey(rule))) return;
    if (rule.body.some((test) => test.scope === Scope.CALLDATA)) return;
    issues.push(ValidationIssue.contextOnlyBody({ groupIndex, ruleIndex, scope: rule.scope, path: rule.path }));
  });
}

///////////////////////////////////////////////////////////////////////////
// Subject analysis
///////////////////////////////////////////////////////////////////////////

/** The values of a subject as keys: `width`-bit patterns ordered unsigned, a signed one with its top bit flipped. */
type Domain = {
  width: number;
  /** The greatest key. */
  max: bigint;
  /** The top bit of a signed type's pattern, zero otherwise. */
  flip: bigint;
  /** The bits below a left-aligned type's pattern in its word, zero otherwise. */
  shift: bigint;
};

/** The relations of a subject to a context property's value: below it, equal to it, above it. */
const LESS = 1;
const EQUAL = 2;
const GREATER = 4;
const ANY_RELATION = LESS | EQUAL | GREATER;

/** The sides of a subject's range a rule bounds. */
const LOWER_SIDE = 1;
const UPPER_SIDE = 2;

/** A rule's condition on its subject's key. */
type Literal =
  /** Keys from `lower` to `upper`, none when `lower` exceeds `upper`. */
  | { kind: "range"; negated: boolean; lower: bigint; upper: bigint }
  /** The member keys. */
  | { kind: "set"; negated: boolean; members: bigint[] }
  /** Keys with every bit of `ones` set and every bit of `zeros` clear. */
  | { kind: "bits"; negated: boolean; ones: bigint; zeros: bigint }
  /** Keys in one of `relations` to the value of a context property. */
  | { kind: "relation"; negated: boolean; property: number; relations: number };

/** A rule on a subject: where it lies, its literal, the context properties it reads and the sides it bounds. */
type SubjectRule = { location: RuleLocation; literal: Literal; reads: number; sides: number };

/** The first `count` literals, the one at `flipped` negated, with their range and fixed bits folded. */
type Conjunction = {
  literals: readonly Literal[];
  count: number;
  flipped: number;
  lower: bigint;
  upper: bigint;
  ones: bigint;
  zeros: bigint;
};

/** Index of no literal. */
const NO_LITERAL = -1;

/** Return the domain of a subject of `typeCode`. A length compares as 256 bits. */
function domainOf(typeCode: number): Domain {
  const width = typeCode === TypeCode.BOOL ? 1 : 8 * (operandWidth(typeCode) ?? 32);
  return {
    width,
    max: (1n << BigInt(width)) - 1n,
    flip: isSigned(typeCode) ? 1n << BigInt(width - 1) : 0n,
    shift: isLeftAligned(typeCode) ? BigInt(256 - width) : 0n,
  };
}

/** Return the pattern a loaded word contains. */
function patternOf(domain: Domain, word: bigint): bigint {
  return (word >> domain.shift) & domain.max;
}

/** Return the word a key of a numeric or length subject loads from. */
function wordOf(domain: Domain, key: bigint): bigint {
  if (domain.flip === 0n) return key;
  return BigInt.asUintN(256, BigInt.asIntN(domain.width, key ^ domain.flip));
}

/** Return the relations to a context property's value a comparison admits. */
function relationsOf(comparison: number): number {
  if (comparison === Op.EQ) return EQUAL;
  if (comparison === Op.GT) return GREATER;
  if (comparison === Op.LT) return LESS;
  if (comparison === Op.GTE) return GREATER | EQUAL;
  return LESS | EQUAL;
}

/** Return the range literal of the keys from `lower` to `upper`. */
function range(lower: bigint, upper: bigint): Literal {
  return { kind: "range", negated: false, lower, upper };
}

/**
 * Return the literal of an operator on a subject, and the sides it bounds. `subjectProperty` is the context property a
 * context test compares, which a context operand naming it equals.
 */
function literalOf(
  domain: Domain,
  operator: Hex,
  subjectProperty: number | undefined,
): { literal: Literal; sides: number } {
  const bytes = hexToBytes(operator);
  const opCode = bytes[0]!;
  const negated = (opCode & Op.NOT) !== 0;
  const comparison = comparisonOf(opCode);
  const key = (index: number) => patternOf(domain, toBigInt(bytes, 1 + 32 * index)) ^ domain.flip;
  let literal: Literal;
  let sides = 0;

  if (sourceOf(opCode) === Source.CONTEXT) {
    const property = Number(toBigInt(bytes, 1));
    const relations = relationsOf(comparison);
    if (property === subjectProperty) {
      literal = (relations & EQUAL) !== 0 ? range(0n, domain.max) : range(1n, 0n);
    } else {
      literal = { kind: "relation", negated: false, property, relations };
    }
  } else if (comparison === Op.EQ || comparison === Op.LENGTH_EQ) {
    literal = { kind: "set", negated: false, members: [key(0)] };
  } else if (comparison === Op.IN) {
    const members: bigint[] = [];
    for (let index = 0; 1 + 32 * index < bytes.length; index++) members.push(key(index));
    literal = { kind: "set", negated: false, members };
  } else if (comparison === Op.GT || comparison === Op.LENGTH_GT) {
    literal = range(key(0) + 1n, domain.max);
    sides = LOWER_SIDE;
  } else if (comparison === Op.LT || comparison === Op.LENGTH_LT) {
    literal = range(0n, key(0) - 1n);
    sides = UPPER_SIDE;
  } else if (comparison === Op.GTE || comparison === Op.LENGTH_GTE) {
    literal = range(key(0), domain.max);
    sides = LOWER_SIDE;
  } else if (comparison === Op.LTE || comparison === Op.LENGTH_LTE) {
    literal = range(0n, key(0));
    sides = UPPER_SIDE;
  } else if (comparison === Op.BETWEEN || comparison === Op.LENGTH_BETWEEN) {
    literal = range(key(0), key(1));
    sides = LOWER_SIDE | UPPER_SIDE;
  } else {
    // A mask's top bit asks the opposite of a signed key's top bit.
    const mask = patternOf(domain, toBigInt(bytes, 1));
    const set = mask & (domain.max ^ domain.flip);
    const flipped = mask & domain.flip;
    literal =
      comparison === Op.BITMASK_ALL
        ? { kind: "bits", negated: false, ones: set, zeros: flipped }
        : { kind: "bits", negated: comparison === Op.BITMASK_ANY, ones: flipped, zeros: set };
  }
  return { literal: { ...literal, negated: literal.negated !== negated }, sides: negated ? 0 : sides };
}

/** Return true when the literal at `index` is negated in a conjunction. */
function isNegated(conjunction: Conjunction, index: number): boolean {
  return conjunction.literals[index]!.negated !== (index === conjunction.flipped);
}

/**
 * Return true when some key and some context meet the first `count` literals, the literal at `flipped` negated. A
 * context property each literal reads is present.
 */
function satisfiable(domain: Domain, literals: readonly Literal[], count: number, flipped: number): boolean {
  const conjunction: Conjunction = { literals, count, flipped, lower: 0n, upper: domain.max, ones: 0n, zeros: 0n };
  const relations = Array.from({ length: MAX_CONTEXT_PROPERTY_ID + 1 }, () => ANY_RELATION);
  let firstSet: Extract<Literal, { kind: "set" }> | undefined;
  for (let index = 0; index < count; index++) {
    const literal = literals[index]!;
    const negated = isNegated(conjunction, index);
    if (literal.kind === "relation") {
      relations[literal.property]! &= negated ? ANY_RELATION ^ literal.relations : literal.relations;
    } else if (negated) {
      continue;
    } else if (literal.kind === "range") {
      if (literal.lower > conjunction.lower) conjunction.lower = literal.lower;
      if (literal.upper < conjunction.upper) conjunction.upper = literal.upper;
    } else if (literal.kind === "bits") {
      conjunction.ones |= literal.ones;
      conjunction.zeros |= literal.zeros;
    } else {
      firstSet ??= literal;
    }
  }

  // A context property's value lies anywhere in its type, so the relations left to it bound the subject's key.
  for (let property = 0; property <= MAX_CONTEXT_PROPERTY_ID; property++) {
    const held = relations[property]!;
    if (held === 0) return false;
    if (held === LESS) {
      const propertyMax = domainOf(contextPropertyType(property)).max;
      if (propertyMax - 1n < conjunction.upper) conjunction.upper = propertyMax - 1n;
    }
    if (held === GREATER && conjunction.lower < 1n) conjunction.lower = 1n;
  }
  if ((conjunction.ones & conjunction.zeros) !== 0n || conjunction.lower > conjunction.upper) return false;

  if (firstSet !== undefined) return firstSet.members.some((key) => admits(conjunction, key));

  // Each step passes one hole or one excluded key, so the walk takes at most one step per literal member.
  let key = nextKey(conjunction, domain.max, conjunction.lower);
  while (key !== undefined && key <= conjunction.upper) {
    const end = excludedTo(conjunction, key);
    if (end === undefined) return true;
    if (end >= conjunction.upper) return false;
    key = nextKey(conjunction, domain.max, end + 1n);
  }
  return false;
}

/** Return true when `key` meets every literal of a conjunction. */
function admits(conjunction: Conjunction, key: bigint): boolean {
  if (key < conjunction.lower || key > conjunction.upper || !meetsBits(conjunction, key)) return false;
  for (let index = 0; index < conjunction.count; index++) {
    const literal = conjunction.literals[index]!;
    if (literal.kind === "set" && literal.members.includes(key) === isNegated(conjunction, index)) return false;
  }
  return excludedTo(conjunction, key) === undefined;
}

/**
 * Return the greatest key the negated range or set of a conjunction that contains `key` excludes from `key` on, or
 * undefined when none contains it.
 */
function excludedTo(conjunction: Conjunction, key: bigint): bigint | undefined {
  for (let index = 0; index < conjunction.count; index++) {
    const literal = conjunction.literals[index]!;
    if (!isNegated(conjunction, index)) continue;
    if (literal.kind === "range" && literal.lower <= key && key <= literal.upper) return literal.upper;
    if (literal.kind === "set" && literal.members.includes(key)) return key;
  }
  return undefined;
}

/** Return true when `key` meets the fixed bits and every negated bits literal of a conjunction. */
function meetsBits(conjunction: Conjunction, key: bigint): boolean {
  if ((key & conjunction.ones) !== conjunction.ones || (key & conjunction.zeros) !== 0n) return false;
  for (let index = 0; index < conjunction.count; index++) {
    const literal = conjunction.literals[index]!;
    if (literal.kind !== "bits" || !isNegated(conjunction, index)) continue;
    if ((key & literal.ones) === literal.ones && (key & literal.zeros) === 0n) return false;
  }
  return true;
}

/**
 * Return the least key from `from` up that meets the fixed bits and every negated bits literal. If `from` meets these
 * conditions, the key is `from`. Otherwise the key sets the lowest clear bit of `from` that can be set and keeps the
 * bits of `from` above that bit. The key completes the bits below that bit, least first.
 */
function nextKey(conjunction: Conjunction, max: bigint, from: bigint): bigint | undefined {
  if (meetsBits(conjunction, from)) return from;
  for (let bit = 1n; bit <= max; bit <<= 1n) {
    if ((from & bit) !== 0n) continue;
    let fixedBits = max ^ (bit - 1n);
    let key = (from & fixedBits) | bit;
    if (!completable(conjunction, max, fixedBits, key)) continue;
    for (let lowBit = bit >> 1n; lowBit !== 0n; lowBit >>= 1n) {
      fixedBits |= lowBit;
      if (!completable(conjunction, max, fixedBits, key)) key |= lowBit;
    }
    return key;
  }
  return undefined;
}

/**
 * Return true when some key whose bits in `fixedBits` are those of `key` meets the fixed bits and every negated bits
 * literal.
 */
function completable(conjunction: Conjunction, max: bigint, fixedBits: bigint, key: bigint): boolean {
  if ((key & conjunction.zeros) !== 0n || (conjunction.ones & fixedBits & ~key) !== 0n) return false;
  const known = fixedBits | conjunction.ones | conjunction.zeros;
  return solvable(conjunction, max, known, key | conjunction.ones);
}

/**
 * Return true when some assignment of the bits outside `known` meets every negated bits literal, with the known bits as
 * in `value`. Propagates the literals left with one free bit. Then branches on the free bits of the first literal left
 * open. Each branch meets that literal, so the recursion runs at most one level per negated bits literal.
 */
function solvable(conjunction: Conjunction, max: bigint, known: bigint, value: bigint): boolean {
  let openOnes = 0n;
  let openZeros = 0n;
  let index = 0;
  while (index < conjunction.count) {
    const literal = conjunction.literals[index++]!;
    if (literal.kind !== "bits" || !isNegated(conjunction, index - 1)) continue;
    if ((literal.ones & known & ~value) !== 0n || (literal.zeros & known & value) !== 0n) continue;
    const ones = literal.ones & max & ~known;
    const zeros = literal.zeros & max & ~known;
    const free = ones | zeros;
    if (free === 0n) return false;
    if ((free & (free - 1n)) === 0n) {
      known |= free;
      value = ones === 0n ? value | free : value & ~free;
      [openOnes, openZeros, index] = [0n, 0n, 0];
    } else if ((openOnes | openZeros) === 0n) {
      [openOnes, openZeros] = [ones, zeros];
    }
  }
  if ((openOnes | openZeros) === 0n) return true;

  // Each branch clears one free bit the literal wants set, or sets one it wants clear; a failed branch's bit then takes
  // the other value.
  for (let free = openOnes | openZeros; free !== 0n; free &= free - 1n) {
    const bit = free & -free;
    const meeting = (openOnes & bit) !== 0n ? value & ~bit : value | bit;
    if (solvable(conjunction, max, known | bit, meeting)) return true;
    known |= bit;
    value = meeting ^ bit;
  }
  return false;
}

/**
 * Push the PV-9 issues of the rules on one subject, in normal-form order. If the rules stop being satisfiable
 * together, push one issue for the rule at which they stop, and nothing else. Otherwise, push an issue for each rule
 * that holds for every value and context, and for each other rule the others imply. Then, among the rules not yet
 * named, push an issue for each constant bound looser than the tightest on its side.
 */
function checkSubject(domain: Domain, isLength: boolean, rules: readonly SubjectRule[], issues: Issue[]): void {
  const literals = rules.map((rule) => rule.literal);
  for (let count = 1; count <= literals.length; count++) {
    if (satisfiable(domain, literals, count, NO_LITERAL)) continue;
    issues.push(ValidationIssue.contradictoryRule(rules[count - 1]!.location));
    return;
  }

  const named = rules.map((rule, index) => {
    if (rule.reads === 0 && !satisfiable(domain, [rule.literal], 1, 0)) {
      issues.push(ValidationIssue.vacuousRule(rule.location));
      return true;
    }
    let othersRead = 0;
    rules.forEach((other, otherIndex) => {
      if (otherIndex !== index) othersRead |= other.reads;
    });
    if ((rule.reads & ~othersRead) !== 0 || satisfiable(domain, literals, literals.length, index)) return false;
    issues.push(ValidationIssue.redundantRule(rule.location));
    return true;
  });
  checkBounds(domain, isLength, rules, named, issues);
}

/**
 * Push an issue for each constant bound of a rule not in `named` looser than the tightest on its side among those
 * rules.
 */
function checkBounds(
  domain: Domain,
  isLength: boolean,
  rules: readonly SubjectRule[],
  named: readonly boolean[],
  issues: Issue[],
): void {
  let tightestLower = 0n;
  let tightestUpper = domain.max;
  rules.forEach(({ literal, sides }, index) => {
    if (named[index] || literal.kind !== "range") return;
    if ((sides & LOWER_SIDE) !== 0 && literal.lower > tightestLower) tightestLower = literal.lower;
    if ((sides & UPPER_SIDE) !== 0 && literal.upper < tightestUpper) tightestUpper = literal.upper;
  });
  rules.forEach(({ location, literal, sides }, index) => {
    if (named[index] || literal.kind !== "range") return;
    let bound: bigint;
    let tightest: bigint;
    if ((sides & LOWER_SIDE) !== 0 && literal.lower < tightestLower) {
      [bound, tightest] = [literal.lower, tightestLower];
    } else if ((sides & UPPER_SIDE) !== 0 && literal.upper > tightestUpper) {
      [bound, tightest] = [literal.upper, tightestUpper];
    } else {
      return;
    }
    const [boundWord, tightestWord] = [bigintToHex(wordOf(domain, bound)), bigintToHex(wordOf(domain, tightest))];
    issues.push(ValidationIssue.dominatedBound(isLength, location, boundWord, tightestWord));
  });
}

/** Push the PV-9 issues of the tests of a group or a loop body, subject by subject in order of first appearance. */
function checkSubjects(tests: readonly { test: BodyRule; location: RuleLocation }[], issues: Issue[]): void {
  const subjects = new Map<string, { test: BodyRule; location: RuleLocation }[]>();
  for (const entry of tests) {
    const subject = `${entry.test.scope}:${entry.test.path}`;
    const entries = subjects.get(subject);
    if (entries === undefined) subjects.set(subject, [entry]);
    else entries.push(entry);
  }
  for (const entries of subjects.values()) {
    const { scope, path, hint } = entries[0]!.test;
    const subjectProperty = scope === Scope.CONTEXT ? readU16(hexToBytes(path), 0) : undefined;
    const typeCode = subjectProperty === undefined ? hexToBytes(hint!).at(-1)! : contextPropertyType(subjectProperty);
    const domain = domainOf(typeCode);
    const rules = entries.map(({ test, location }) => subjectRule(domain, test, location, subjectProperty));
    checkSubject(domain, hasCalldataLength(typeCode), rules, issues);
  }
}

/** Return a test as a rule on its subject, whose context property is `subjectProperty` for a context test. */
function subjectRule(
  domain: Domain,
  test: BodyRule,
  location: RuleLocation,
  subjectProperty: number | undefined,
): SubjectRule {
  const { literal, sides } = literalOf(domain, test.operator, subjectProperty);
  let reads = subjectProperty === undefined ? 0 : 1 << subjectProperty;
  if (literal.kind === "relation") reads |= 1 << literal.property;
  return { location, literal, reads, sides };
}

/** Push the PV-9 issues of a group's normal form: its tests and context tests, then each loop body apart. */
function checkGroupSubjects(rules: Rule[], groupIndex: number, issues: Issue[]): void {
  const tests: { test: BodyRule; location: RuleLocation }[] = [];
  for (const [ruleIndex, rule] of rules.entries()) {
    if (rule.scope === Scope.LOOP) continue;
    tests.push({
      test: rule,
      location: { groupIndex, ruleIndex, scope: rule.scope, path: rule.path, operator: rule.operator },
    });
  }
  checkSubjects(tests, issues);
  for (const [ruleIndex, rule] of rules.entries()) {
    if (rule.scope !== Scope.LOOP) continue;
    const body = rule.body.map((test, bodyRuleIndex) => ({
      test,
      location: { groupIndex, ruleIndex, bodyRuleIndex, scope: test.scope, path: test.path, operator: test.operator },
    }));
    checkSubjects(body, issues);
  }
}

///////////////////////////////////////////////////////////////////////////
// Validation
///////////////////////////////////////////////////////////////////////////

/**
 * Validate a policy blob (PV-1 to PV-9). Storage validation runs first, since the descriptor check reads the descriptor
 * before anything is decoded. Issues of PV-1 to PV-7 name a rule where the blob stores it. Issues of PV-8 and PV-9 name
 * the group where the blob stores it and the rule's position in the normal form of that group. Only rules that raise no
 * PV-2, PV-3, PV-5 or PV-6 issue and no PV-4 issue on a test enter the normal form. PV-8 skips a loop that lost a body
 * test to such an issue.
 * @param blob - A policy blob that passes storage validation.
 * @returns Every issue found, or one issue alone when the descriptor is not valid.
 * @throws {CallciumError} When the blob fails storage validation, or a group's normal form exceeds a format limit.
 */
function validate(blob: Hex): Issue[] {
  validatePolicy(blob);
  const bytes = hexToBytes(blob);
  const desc = bytes.subarray(PF.DESC_OFFSET, PF.DESC_OFFSET + readU16(bytes, PF.DESC_LENGTH_OFFSET));
  const invalid = Descriptor.tryValidateMeta(desc);
  if (invalid !== undefined) return [ValidationIssue.invalidDescriptor(invalid.offset)];

  const data = PolicyCoder.decode(blob);
  const issues: Issue[] = [];
  data.groups.forEach((rules, groupIndex) => {
    const kept: Rule[] = [];
    const lost = new Set<string>();
    rules.forEach((rule, ruleIndex) => {
      if (rule.scope === Scope.LOOP) {
        const loop = checkLoop(desc, rule, { groupIndex, ruleIndex, scope: rule.scope, path: rule.path }, issues);
        if (loop === undefined || loop.body.length < rule.body.length) lost.add(loopKey(rule));
        if (loop !== undefined) kept.push(loop);
        return;
      }
      const location = { groupIndex, ruleIndex, scope: rule.scope, path: rule.path, operator: rule.operator };
      const test = checkTest(desc, rule, undefined, location, issues);
      if (test !== undefined) kept.push(test);
    });
    if (kept.length === 0) return;
    const normal = PolicyCoder.decode(PolicyCoder.encode({ ...data, groups: [kept] })).groups[0]!;
    checkBodies(normal, groupIndex, lost, issues);
    checkGroupSubjects(normal, groupIndex, issues);
  });
  return issues;
}

/** Build-time validation of policy blobs. */
export const PolicyValidator = { validate };

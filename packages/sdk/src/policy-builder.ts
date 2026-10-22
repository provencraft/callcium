import { bigintToHex, bytesToHex, hexToBytes } from "./bytes";
import {
  comparisonOf,
  formatCode,
  lookupContextProperty,
  LoopQuantifier,
  Op,
  PolicyFormat as PF,
  Scope,
  Source,
  sourceOf,
  TypeCode,
} from "./constants";
import { readOperandExtremes } from "./constraint";
import { DescriptorCoder } from "./descriptor-coder";
import { CallciumError, ValidationError } from "./errors";
import { Hint } from "./hint";
import { canonicalize, isSigned, loadOperand, operandTypeOf, operandWidth, toBigInt } from "./operators";
import { encodePath, parsePathSteps, Quantifier } from "./path";
import { PolicyCoder } from "./policy-coder";
import { PolicyValidator } from "./policy-validator";
import { SignatureParser } from "./signature";

import type { Hex } from "./types";
import type { BodyRule, Constraint, Issue, PolicyData, Rule } from "./types";

///////////////////////////////////////////////////////////////////////////
// Internal types
///////////////////////////////////////////////////////////////////////////

type PolicyDraft = {
  isSelectorless: boolean;
  selector: Hex;
  descriptor: Uint8Array;
  groups: Rule[][];
};

///////////////////////////////////////////////////////////////////////////
// Operand domain
///////////////////////////////////////////////////////////////////////////

// Values a 32-byte word represents, which is the distance between an operand and its alias.
const WORD_VALUES = 1n << 256n;

/** Reject an operand outside the target's range whose word carries a value inside it. */
function reject(written: bigint, folded: bigint): never {
  throw new CallciumError(
    "OUT_OF_PHYSICAL_BOUNDS",
    `Operand ${written} is outside the physical range of the type and encodes as ${folded}`,
  );
}

/**
 * Reject an operand that two's complement folds onto a value the target admits. Such an operand and the value it folds
 * onto encode to one word. The operands as written are the only place the two stay distinct. An operand spans no
 * more than one word, which leaves two ways across. A negative's alias clears every target narrower than the whole
 * word. A positive reaches a signed range only at that type's own minimum word.
 */
function checkOperandDomain(constraint: Constraint, typeCode: number): void {
  const extremes = readOperandExtremes(constraint);
  if (extremes === undefined) return;

  // A negative operand encodes as its unsigned alias's word, which only a whole-word target can hold too.
  if (extremes.leastNegative < 0n && typeCode === TypeCode.UINT_MAX) {
    reject(extremes.leastNegative, extremes.leastNegative + WORD_VALUES);
  }

  if (!isSigned(typeCode)) return;
  // An operand at or above the signed minimum's own word denotes that negative, and every such operand already exceeds
  // the signed maximum.
  const signedMinimumWord = WORD_VALUES - (1n << BigInt(8 * operandWidth(typeCode)! - 1));
  if (extremes.greatest >= signedMinimumWord) {
    reject(extremes.greatest, extremes.greatest - WORD_VALUES);
  }
}

/** Reject an operand word its operand type cannot represent. */
function outOfRange(word: bigint): never {
  throw new CallciumError(
    "OUT_OF_PHYSICAL_BOUNDS",
    `Operand ${bigintToHex(word)} is outside the range of its operand type`,
  );
}

/**
 * Require every comparison of `constraint` to apply to a target of `typeCode` and every constant to be a value its
 * operand type can represent. Return the operators with each mask as its operand type's word.
 */
function checkOperands(constraint: Constraint, typeCode: number): Hex[] {
  checkOperandDomain(constraint, typeCode);

  return constraint.operators.map((operatorHex) => {
    const operator = hexToBytes(operatorHex);
    // Only an opcode followed by whole words carries constants to check.
    if (operator.length <= 1 || (operator.length - 1) % 32 !== 0) return operatorHex;
    const opCode = operator[0]!;
    const comparison = comparisonOf(opCode);
    const operandType = operandTypeOf(comparison, typeCode);
    if (operandType === undefined) {
      throw new CallciumError("OPERATOR_TARGET_MISMATCH", "Comparison does not apply to the target type");
    }
    if (sourceOf(opCode) !== Source.CONSTANT) return operatorHex;

    // The members of a set fill at most what the data length field holds.
    const width = operandWidth(operandType)!;
    const limit = Math.floor((2 ** (8 * PF.RULE_DATALENGTH_SIZE) - 1) / width);
    if ((operator.length - 1) / 32 > limit) {
      throw new CallciumError("SET_TOO_LARGE", `Set must contain at most ${limit} values`);
    }

    const isMask = comparison >= Op.BITMASK_ALL && comparison <= Op.BITMASK_NONE;
    const checked = operator.slice();
    for (let offset = 1; offset < operator.length; offset += 32) {
      const word = toBigInt(operator, offset);
      if (!isMask) {
        if (canonicalize(word, operandType) !== word) outOfRange(word);
        continue;
      }
      // A mask is a bit pattern of the type's width, or -1 for every bit.
      if (word !== WORD_VALUES - 1n && word >> BigInt(8 * width) !== 0n) outOfRange(word);
      const pattern = hexToBytes(bigintToHex(word)).subarray(32 - width);
      checked.set(hexToBytes(bigintToHex(loadOperand(pattern, 0, operandType))), offset);
    }
    return bytesToHex(checked);
  });
}

///////////////////////////////////////////////////////////////////////////
// PolicyBuilder
///////////////////////////////////////////////////////////////////////////

/** Fluent API for drafting policies from constraints. */
export class PolicyBuilder {
  private draft: PolicyDraft;

  private constructor(draft: PolicyDraft) {
    this.draft = draft;
  }

  /**
   * Create a builder from a function signature.
   * @param signature - The function signature (for example "transfer(address,uint256)").
   * @returns A new builder.
   * @throws {CallciumError} If the signature is malformed.
   */
  static create(signature: string): PolicyBuilder {
    const parsed = SignatureParser.parse(signature);
    const descriptor = DescriptorCoder.fromTypes(parsed.types);
    return new PolicyBuilder({ isSelectorless: false, selector: parsed.selector, descriptor, groups: [[]] });
  }

  /**
   * Create a selectorless builder from a comma-separated type list.
   * @param typesCsv - The comma-separated ABI types (for example "uint256,address").
   * @returns A new builder.
   * @throws {CallciumError} If a type is malformed.
   */
  static createRaw(typesCsv: string): PolicyBuilder {
    const descriptor = DescriptorCoder.fromTypes(typesCsv);
    return new PolicyBuilder({ isSelectorless: true, selector: "0x00000000", descriptor, groups: [[]] });
  }

  /**
   * Add a constraint to the active group. A path through `Quantifier.ALL` or `Quantifier.ANY` adds its operators to the
   * body of the group's loop over that array with that quantifier.
   * @param constraint - The constraint to add.
   * @returns This builder.
   * @throws {CallciumError} If the constraint has no operator, or its path does not reach a target in the signature.
   * If a comparison does not apply to its target, or an operand is a value its target's type cannot represent.
   */
  add(constraint: Constraint): this {
    if (constraint.operators.length === 0) {
      throw new CallciumError("NO_CONSTRAINT_OPERATORS", "Constraint must have at least one operator");
    }

    // Path shape is established before the scope decides how to navigate it.
    const steps = parsePathSteps(constraint.path);
    if (steps.length === 0) {
      throw new CallciumError("EMPTY_PATH", "Path must have at least one step");
    }

    // A caller from JavaScript can pass any scope, so the value is read as a number.
    const scope: number = constraint.scope;
    if (scope === Scope.CONTEXT) {
      this.addContextTests(constraint, steps);
    } else if (scope === Scope.CALLDATA) {
      this.addCalldataTests(constraint, steps);
    } else {
      throw new CallciumError("UNKNOWN_SCOPE", `Unknown scope value ${scope}`);
    }
    return this;
  }

  /**
   * Start a new constraint group (OR semantics between groups).
   * @returns This builder.
   * @throws {CallciumError} If the current group is empty.
   */
  or(): this {
    const lastGroup = this.draft.groups[this.draft.groups.length - 1]!;
    if (lastGroup.length === 0) {
      throw new CallciumError("EMPTY_GROUP", "Cannot start a new group when the current group is empty");
    }
    this.draft.groups.push([]);
    return this;
  }

  /**
   * Build the policy blob and validate it.
   * @returns The encoded policy.
   * @throws {ValidationError} If validation reports any issue.
   * @throws {CallciumError} If the encoder refuses the policy, or the blob fails storage validation.
   */
  build(): Hex {
    const blob = this.buildUnsafe();
    const issues = PolicyValidator.validate(blob);
    if (issues.length > 0) throw new ValidationError(issues);
    return blob;
  }

  /**
   * Validate the policy the builder contains.
   * @returns Every issue validation reports on the encoded policy.
   * @throws {CallciumError} If the encoder refuses the policy, or the blob fails storage validation.
   */
  validate(): Issue[] {
    return PolicyValidator.validate(this.buildUnsafe());
  }

  /**
   * Build the policy blob without validation. The resulting policy can be invalid.
   * @returns The encoded policy.
   * @throws {CallciumError} If the encoder refuses the policy.
   */
  buildUnsafe(): Hex {
    return PolicyCoder.encode(this.toPolicyData());
  }

  /** Append a context test per operator of `constraint`, whose path names a context property. */
  private addContextTests(constraint: Constraint, steps: number[]): void {
    if (steps.length !== 1) {
      throw new CallciumError("INVALID_CONTEXT_PATH", "Context-scope path must be exactly one step");
    }
    const { typeCode } = lookupContextProperty(steps[0]!);
    for (const operator of checkOperands(constraint, typeCode)) {
      this.currentGroup().push({ scope: Scope.CONTEXT, path: constraint.path, operator });
    }
  }

  /**
   * Append a calldata test per operator of `constraint`. If the path of `constraint` passes a quantifier step, append a
   * body test per operator to the group's loop over that array instead.
   */
  private addCalldataTests(constraint: Constraint, steps: number[]): void {
    const desc = this.draft.descriptor;
    const quantifierIndex = findQuantifierIndex(steps);

    if (quantifierIndex === undefined) {
      const target = Hint.requireCompiled(Hint.compileTest(desc, steps), steps, 0);
      for (const operator of checkOperands(constraint, desc[target.node]!)) {
        this.currentGroup().push({ scope: Scope.CALLDATA, path: constraint.path, operator });
      }
      return;
    }

    // The quantifier splits the path into the array's path and the body test's path from the element.
    const arraySteps = steps.slice(0, quantifierIndex);
    const bodySteps = steps.slice(quantifierIndex + 1);
    const loop = Hint.requireCompiled(Hint.compileLoop(desc, arraySteps), steps, 0);
    const target = Hint.requireCompiled(Hint.compileTest(desc, bodySteps, loop.node), steps, quantifierIndex + 1);

    const bodyPath = encodePath(bodySteps);
    const tests: BodyRule[] = checkOperands(constraint, desc[target.node]!).map((operator) => ({
      scope: Scope.CALLDATA,
      path: bodyPath,
      operator,
    }));
    const quantifier = steps[quantifierIndex] === Quantifier.ALL ? LoopQuantifier.ALL : LoopQuantifier.ANY;
    const arrayPath = encodePath(arraySteps);
    const existing = this.currentGroup().find(
      (rule) => rule.scope === Scope.LOOP && rule.quantifier === quantifier && rule.path === arrayPath,
    );
    if (existing !== undefined && existing.scope === Scope.LOOP) {
      existing.body.push(...tests);
    } else {
      this.currentGroup().push({ scope: Scope.LOOP, quantifier, path: arrayPath, body: tests });
    }
  }

  /** The active group. */
  private currentGroup(): Rule[] {
    return this.draft.groups[this.draft.groups.length - 1]!;
  }

  /** The draft as the encoder takes it. */
  private toPolicyData(): PolicyData {
    return {
      isSelectorless: this.draft.isSelectorless,
      selector: this.draft.selector,
      descriptor: bytesToHex(this.draft.descriptor),
      groups: this.draft.groups,
    };
  }
}

/**
 * Return the index of the path's quantifier step, or undefined when the path has none.
 * The first step is a parameter index.
 * @throws {CallciumError} On a second quantifier step and on any other step in the reserved marker range.
 */
function findQuantifierIndex(steps: readonly number[]): number | undefined {
  let quantifierIndex: number | undefined;
  for (let stepIndex = 1; stepIndex < steps.length; stepIndex++) {
    const step = steps[stepIndex]!;
    if (step < PF.PATH_MARKER_BASE) continue;
    if (step !== Quantifier.ALL && step !== Quantifier.ANY) {
      throw new CallciumError(
        "UNKNOWN_PATH_STEP",
        `Path step ${formatCode(step, PF.PATH_STEP_SIZE)} is in the reserved marker range`,
      );
    }
    if (quantifierIndex !== undefined) {
      throw new CallciumError("INVALID_NESTED_LOOP", "Loop body holds a loop");
    }
    quantifierIndex = stepIndex;
  }
  return quantifierIndex;
}

import { bytesToHex } from "./bytes";
import { Scope, TypeCode, lookupContextProperty } from "./constants";
import { readOperandExtremes } from "./constraint";
import { Descriptor } from "./descriptor";
import { DescriptorCoder } from "./descriptor-coder";
import { CallciumError, ValidationError } from "./errors";
import { isQuantifier, parsePathSteps } from "./path";
import { PolicyCoder } from "./policy-coder";
import { PolicyValidator } from "./policy-validator";
import { SignatureParser } from "./signature";

import type { Constraint, Hex, Issue, PolicyData } from "./types";

///////////////////////////////////////////////////////////////////////////
// Internal types
///////////////////////////////////////////////////////////////////////////

type PolicyDraft = {
  isSelectorless: boolean;
  selector: Hex;
  descriptor: Uint8Array;
  groups: Constraint[][];
  /** Scope-qualified paths already taken in the group being built. */
  groupPathKeys: Set<string>;
};

///////////////////////////////////////////////////////////////////////////
// Path validation
///////////////////////////////////////////////////////////////////////////

/** Validate a context-scope path and return the referenced property's type code. */
function validateContextPath(steps: number[]): number {
  if (steps.length !== 1) {
    throw new CallciumError("INVALID_CONTEXT_PATH", "Context-scope path must be exactly one step");
  }
  return lookupContextProperty(steps[0]!).typeCode;
}

/** Validate a calldata-scope path against the descriptor and return the target's type code. */
function validateCalldataPath(steps: number[], desc: Uint8Array): number {
  const argIndex = steps[0]!;
  const paramCount = Descriptor.paramCount(desc);
  if (argIndex >= paramCount) {
    throw new CallciumError(
      "PARAM_INDEX_OUT_OF_BOUNDS",
      `Param index ${argIndex} out of range (descriptor has ${paramCount} params)`,
    );
  }

  let offset = Descriptor.paramOffset(desc, argIndex);
  let hasQuantifier = false;

  for (let i = 1; i < steps.length; i++) {
    const step = steps[i]!;
    const info = Descriptor.inspect(desc, offset);
    const isArray = info.typeCode === TypeCode.STATIC_ARRAY || info.typeCode === TypeCode.DYNAMIC_ARRAY;

    if (isQuantifier(step)) {
      if (!isArray) {
        throw new CallciumError("QUANTIFIER_ON_NON_ARRAY", "Quantifier step is only valid on an array node");
      }
      if (hasQuantifier) {
        throw new CallciumError("NESTED_QUANTIFIER", "Nested quantifiers are not allowed");
      }
      hasQuantifier = true;
    }

    if (info.typeCode === TypeCode.TUPLE) {
      const fieldCount = Descriptor.tupleFieldCount(desc, offset);
      if (step >= fieldCount) {
        throw new CallciumError(
          "TUPLE_FIELD_OUT_OF_BOUNDS",
          `Tuple field index ${step} out of range (tuple has ${fieldCount} fields)`,
        );
      }
      offset = Descriptor.tupleFieldOffset(desc, offset, step);
    } else if (isArray) {
      if (!isQuantifier(step) && info.typeCode === TypeCode.STATIC_ARRAY) {
        const arrayLength = Descriptor.staticArrayLength(desc, offset);
        if (step >= arrayLength) {
          throw new CallciumError(
            "STATIC_ARRAY_INDEX_OUT_OF_BOUNDS",
            `Array index ${step} out of range (static array has ${arrayLength} elements)`,
          );
        }
      }
      offset = Descriptor.arrayElementOffset(offset);
    } else {
      throw new CallciumError("NOT_COMPOSITE", "Cannot descend into an elementary type");
    }
  }

  return Descriptor.inspect(desc, offset).typeCode;
}

///////////////////////////////////////////////////////////////////////////
// Operand domain
///////////////////////////////////////////////////////////////////////////

// Values a 32-byte word represents, which is the distance between an operand and its alias.
const WORD_VALUES = 1n << 256n;

/** Integers an integer target admits, or null for any other type. */
function targetBounds(typeCode: number): { min: bigint; max: bigint } | null {
  if (typeCode >= TypeCode.UINT_MIN && typeCode <= TypeCode.UINT_MAX) {
    const bits = BigInt(typeCode - TypeCode.UINT_MIN + 1) * 8n;
    return { min: 0n, max: (1n << bits) - 1n };
  }
  if (typeCode >= TypeCode.INT_MIN && typeCode <= TypeCode.INT_MAX) {
    const bits = BigInt(typeCode - TypeCode.INT_MIN + 1) * 8n;
    const half = 1n << (bits - 1n);
    return { min: -half, max: half - 1n };
  }
  return null;
}

/** Reject an operand outside the target's range whose word carries a value inside it. */
function reject(written: bigint, folded: bigint): never {
  throw new CallciumError(
    "OUT_OF_PHYSICAL_BOUNDS",
    `Operand ${written} is outside the physical range of the type and encodes as ${folded}`,
  );
}

/**
 * Reject an operand that two's complement folds onto a value the target admits.
 * Such an operand and the value it folds onto encode to one word, so the operands as written are
 * the only place the two stay distinct. An operand whose word the target cannot hold survives
 * encoding intact and needs no guard here.
 */
function checkOperandDomain(constraint: Constraint, typeCode: number): void {
  const bounds = targetBounds(typeCode);
  const extremes = readOperandExtremes(constraint);
  if (bounds === null || extremes === undefined) return;

  // A negative operand occupies the word its unsigned alias does.
  const alias = extremes.leastNegative + WORD_VALUES;
  if (extremes.leastNegative < bounds.min && alias <= bounds.max) reject(extremes.leastNegative, alias);

  // An operand above the range occupies the word of the negative it denotes.
  const denoted = extremes.greatest - WORD_VALUES;
  if (extremes.greatest > bounds.max && denoted >= bounds.min) reject(extremes.greatest, denoted);
}

///////////////////////////////////////////////////////////////////////////
// PolicyBuilder
///////////////////////////////////////////////////////////////////////////

/** Fluent builder for constructing Callcium policies. */
export class PolicyBuilder {
  private draft: PolicyDraft;

  private constructor(draft: PolicyDraft) {
    this.draft = draft;
  }

  /**
   * Create a builder from a function signature.
   * @param signature - ABI function signature, e.g. `"transfer(address,uint256)"`.
   */
  static create(signature: string): PolicyBuilder {
    const parsed = SignatureParser.parse(signature);
    const descriptor = DescriptorCoder.fromTypes(parsed.types);
    return new PolicyBuilder({
      isSelectorless: false,
      selector: parsed.selector,
      descriptor,
      groups: [[]],
      groupPathKeys: new Set(),
    });
  }

  /**
   * Create a selectorless builder from a raw type string.
   * @param typesCsv - Comma-separated ABI type strings, e.g. `"address,uint256"`.
   */
  static createRaw(typesCsv: string): PolicyBuilder {
    const descriptor = DescriptorCoder.fromTypes(typesCsv);
    return new PolicyBuilder({
      isSelectorless: true,
      selector: "0x00000000",
      descriptor,
      groups: [[]],
      groupPathKeys: new Set(),
    });
  }

  /**
   * Add a constraint to the current group.
   * @param constraint - A `Constraint` object or a `ConstraintBuilder` instance.
   * @throws {CallciumError} With code `OUT_OF_PHYSICAL_BOUNDS` when a numeric operand lies outside
   * the target type's range and encodes as a value inside it. Operands are read as written, so a
   * `Constraint` carrying encoded operator bytes is left to {@link validate}.
   */
  add(constraint: Constraint): this {
    // A builder compiles no hint; one arrives only on a constraint that came already encoded.
    const added: Constraint = {
      scope: constraint.scope,
      path: constraint.path,
      operators: [...constraint.operators],
      ...("hint" in constraint && constraint.hint !== undefined && { hint: constraint.hint }),
    };

    if (added.operators.length === 0) {
      throw new CallciumError("NO_CONSTRAINT_OPERATORS", "Constraint must have at least one operator");
    }

    // Path shape is established before the scope decides how to navigate it.
    const steps = parsePathSteps(added.path);
    if (steps.length === 0) {
      throw new CallciumError("EMPTY_PATH", "Path must have at least one step");
    }

    let targetTypeCode: number;
    if (added.scope === Scope.CONTEXT) {
      targetTypeCode = validateContextPath(steps);
    } else if (added.scope === Scope.CALLDATA) {
      targetTypeCode = validateCalldataPath(steps, this.draft.descriptor);
    } else {
      throw new CallciumError("INVALID_SCOPE", `Unknown scope value ${added.scope}`);
    }

    checkOperandDomain(constraint, targetTypeCode);

    const key = `${added.scope}:${added.path.toLowerCase()}`;
    if (this.draft.groupPathKeys.has(key)) {
      throw new CallciumError("DUPLICATE_PATH_IN_GROUP", `Duplicate path ${added.path} in the same group`);
    }

    this.draft.groupPathKeys.add(key);
    this.draft.groups[this.draft.groups.length - 1]!.push(added);
    return this;
  }

  /** Start a new constraint group (OR branch). */
  or(): this {
    const lastGroup = this.draft.groups[this.draft.groups.length - 1]!;
    if (lastGroup.length === 0) {
      throw new CallciumError("EMPTY_GROUP", "Cannot start a new group when the current group is empty");
    }
    this.draft.groups.push([]);
    this.draft.groupPathKeys.clear();
    return this;
  }

  /**
   * Build the policy into an encoded binary blob with strict validation.
   * Throws on any issue, regardless of severity. Use {@link validate} to
   * inspect issues, or {@link buildUnsafe} to encode without validation.
   * @returns The policy as a 0x-prefixed hex string.
   * @throws {CallciumError} If any group is empty.
   * @throws {ValidationError} If validation finds any issue.
   * @throws {CallciumError} With code `RULE_SIZE_OVERFLOW` when a rule's encoded bytes exceed the
   * width of the rule size field.
   */
  build(): Hex {
    this.checkGroups();
    const policyData = this.toPolicyData();
    const issues = PolicyValidator.validate(policyData);
    if (issues.length > 0) {
      throw new ValidationError(issues);
    }
    return PolicyCoder.encode(policyData);
  }

  /**
   * Build the policy into an encoded binary blob without validation.
   * The resulting policy may be invalid. Prefer {@link build}; use this
   * only to knowingly bypass a reported issue.
   * @returns The policy as a 0x-prefixed hex string.
   * @throws {CallciumError} If any group is empty.
   */
  buildUnsafe(): Hex {
    this.checkGroups();
    return PolicyCoder.encode(this.toPolicyData());
  }

  /**
   * Validate the policy without encoding.
   * @returns All validation issues found.
   */
  validate(): Issue[] {
    this.checkGroups();
    const policyData = this.toPolicyData();
    return PolicyValidator.validate(policyData);
  }

  /** Throw if any group is empty. */
  private checkGroups(): void {
    for (let i = 0; i < this.draft.groups.length; i++) {
      if (this.draft.groups[i]!.length === 0) {
        throw new CallciumError("EMPTY_GROUP", `Group ${i} is empty`);
      }
    }
  }

  /** Convert the draft to a PolicyData structure. */
  private toPolicyData(): PolicyData {
    return {
      isSelectorless: this.draft.isSelectorless,
      selector: this.draft.selector,
      descriptor: bytesToHex(this.draft.descriptor),
      groups: this.draft.groups,
    };
  }
}

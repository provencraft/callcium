import { bytesToHex } from "./bytes";
import { Scope, TypeCode, isQuantifier, MAX_CONTEXT_PROPERTY_ID } from "./constants";
import { ConstraintBuilder } from "./constraint";
import { Descriptor } from "./descriptor";
import { DescriptorCoder } from "./descriptor-coder";
import { CallciumError, ValidationError } from "./errors";
import { PolicyCoder, parsePathSteps } from "./policy-coder";
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
  pathHashes: Set<string>[];
};

///////////////////////////////////////////////////////////////////////////
// Path validation
///////////////////////////////////////////////////////////////////////////

/** Validate a context-scope path. */
function validateContextPath(steps: number[]): void {
  if (steps.length !== 1) {
    throw new CallciumError("INVALID_CONTEXT_PATH", "Context-scope path must be exactly one step.");
  }
  const step = steps[0]!;
  if (step > MAX_CONTEXT_PROPERTY_ID) {
    throw new CallciumError(
      "UNKNOWN_CONTEXT_PROPERTY",
      `Unknown context property ID 0x${step.toString(16).padStart(4, "0")}.`,
    );
  }
}

/** Validate a calldata-scope path against the descriptor. */
function validateCalldataPath(steps: number[], desc: Uint8Array): void {
  const argIndex = steps[0]!;
  const paramCount = Descriptor.paramCount(desc);
  if (argIndex >= paramCount) {
    throw new CallciumError(
      "PARAM_INDEX_OUT_OF_BOUNDS",
      `Param index ${argIndex} out of range (descriptor has ${paramCount} params).`,
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
        throw new CallciumError("QUANTIFIER_ON_NON_ARRAY", "Quantifier step is only valid on an array node.");
      }
      if (hasQuantifier) {
        throw new CallciumError("NESTED_QUANTIFIER", "Nested quantifiers are not allowed.");
      }
      hasQuantifier = true;
    }

    if (info.typeCode === TypeCode.TUPLE) {
      const fieldCount = Descriptor.tupleFieldCount(desc, offset);
      if (step >= fieldCount) {
        throw new CallciumError(
          "TUPLE_FIELD_OUT_OF_BOUNDS",
          `Tuple field index ${step} out of range (tuple has ${fieldCount} fields).`,
        );
      }
      offset = Descriptor.tupleFieldOffset(desc, offset, step);
    } else if (isArray) {
      if (!isQuantifier(step) && info.typeCode === TypeCode.STATIC_ARRAY) {
        const arrayLength = Descriptor.staticArrayLength(desc, offset);
        if (step >= arrayLength) {
          throw new CallciumError(
            "STATIC_ARRAY_INDEX_OUT_OF_BOUNDS",
            `Array index ${step} out of range (static array has ${arrayLength} elements).`,
          );
        }
      }
      offset = Descriptor.arrayElementOffset(offset);
    } else {
      throw new CallciumError("NOT_COMPOSITE", "Cannot descend into an elementary type.");
    }
  }
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
      pathHashes: [new Set()],
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
      pathHashes: [new Set()],
    });
  }

  /**
   * Add a constraint to the current group.
   * @param constraint - A `Constraint` object or a `ConstraintBuilder` instance.
   */
  add(constraint: Constraint | ConstraintBuilder): this {
    const c: Constraint = {
      scope: constraint.scope,
      path: constraint.path,
      operators: [...constraint.operators],
    };

    if (c.operators.length === 0) {
      throw new CallciumError("NO_CONSTRAINT_OPERATORS", "Constraint must have at least one operator.");
    }

    // Path shape is established before the scope decides how to navigate it.
    const steps = parsePathSteps(c.path);
    if (steps.length === 0) {
      throw new CallciumError("EMPTY_PATH", "Path must have at least one step.");
    }

    if (c.scope === Scope.CONTEXT) {
      validateContextPath(steps);
    } else if (c.scope === Scope.CALLDATA) {
      validateCalldataPath(steps, this.draft.descriptor);
    } else {
      throw new CallciumError("INVALID_SCOPE", `Unknown scope value ${c.scope}.`);
    }

    const key = `${c.scope}:${c.path.toLowerCase()}`;
    const currentHashes = this.draft.pathHashes[this.draft.pathHashes.length - 1]!;
    if (currentHashes.has(key)) {
      throw new CallciumError("DUPLICATE_PATH_IN_GROUP", `Duplicate path ${c.path} in the same group.`);
    }

    currentHashes.add(key);
    this.draft.groups[this.draft.groups.length - 1]!.push(c);
    return this;
  }

  /** Start a new constraint group (OR branch). */
  or(): this {
    const lastGroup = this.draft.groups[this.draft.groups.length - 1]!;
    if (lastGroup.length === 0) {
      throw new CallciumError("EMPTY_GROUP", "Cannot start a new group when the current group is empty.");
    }
    this.draft.groups.push([]);
    this.draft.pathHashes.push(new Set());
    return this;
  }

  /**
   * Build the policy into an encoded binary blob with strict validation.
   * Throws on any issue, regardless of severity. Use {@link validate} to
   * inspect issues, or {@link buildUnsafe} to encode without validation.
   * @returns The policy as a 0x-prefixed hex string.
   * @throws {CallciumError} If any group is empty.
   * @throws {ValidationError} If validation finds any issue.
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
        throw new CallciumError("EMPTY_GROUP", `Group ${i} is empty.`);
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

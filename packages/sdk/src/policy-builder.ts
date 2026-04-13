import { bytesToHex, hexToBytes, readU16 } from "./bytes";
import { Scope, TypeCode, isQuantifier, MAX_CONTEXT_PROPERTY_ID, DescriptorFormat as DF } from "./constants";
import { ConstraintBuilder } from "./constraint";
import { Descriptor } from "./descriptor";
import { DescriptorCoder } from "./descriptor-coder";
import { CallciumError } from "./errors";
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
function validateContextPath(pathBytes: Uint8Array): void {
  if (pathBytes.length !== 2) {
    throw new CallciumError("INVALID_CONTEXT_PATH", "Context-scope path must be exactly one step (2 bytes).");
  }
  const step = readU16(pathBytes, 0);
  if (step > MAX_CONTEXT_PROPERTY_ID) {
    throw new CallciumError(
      "INVALID_CONTEXT_PROPERTY",
      `Unknown context property ID 0x${step.toString(16).padStart(4, "0")}.`,
    );
  }
}

/** Validate a calldata-scope path against the descriptor. */
function validateCalldataPath(path: Hex, desc: Uint8Array): void {
  const steps = parsePathSteps(path);
  if (steps.length === 0) {
    throw new CallciumError("INVALID_PATH", "Calldata path must have at least one step.");
  }

  const argIndex = steps[0]!;
  const paramCount = Descriptor.paramCount(desc);
  if (argIndex >= paramCount) {
    throw new CallciumError(
      "INVALID_PATH",
      `Argument index ${argIndex} out of range (descriptor has ${paramCount} params).`,
    );
  }

  let offset = Descriptor.paramOffset(desc, argIndex);
  let hasQuantifier = false;

  for (let i = 1; i < steps.length; i++) {
    const step = steps[i]!;
    const info = Descriptor.inspect(desc, offset);

    if (info.typeCode === TypeCode.TUPLE) {
      if (isQuantifier(step)) {
        throw new CallciumError("INVALID_PATH", "Quantifier step is not valid on a tuple node.");
      }
      const fieldCount = Descriptor.tupleFieldCount(desc, offset);
      if (step >= fieldCount) {
        throw new CallciumError(
          "INVALID_PATH",
          `Tuple field index ${step} out of range (tuple has ${fieldCount} fields).`,
        );
      }
      offset = Descriptor.tupleFieldOffset(desc, offset, step);
    } else if (info.typeCode === TypeCode.STATIC_ARRAY || info.typeCode === TypeCode.DYNAMIC_ARRAY) {
      if (isQuantifier(step)) {
        if (hasQuantifier) {
          throw new CallciumError("INVALID_PATH", "Nested quantifiers are not allowed.");
        }
        hasQuantifier = true;
      } else if (info.typeCode === TypeCode.STATIC_ARRAY) {
        const arrayLength = Descriptor.staticArrayLength(desc, offset);
        if (step >= arrayLength) {
          throw new CallciumError(
            "INVALID_PATH",
            `Array index ${step} out of range (static array has ${arrayLength} elements).`,
          );
        }
      }
      offset = offset + DF.ARRAY_HEADER_SIZE;
    } else {
      throw new CallciumError("INVALID_PATH", "Cannot descend into an elementary type.");
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
      throw new CallciumError("INVALID_CONSTRAINT", "Constraint must have at least one operator.");
    }

    if (c.scope === Scope.CONTEXT) {
      validateContextPath(hexToBytes(c.path));
    } else if (c.scope === Scope.CALLDATA) {
      validateCalldataPath(c.path, this.draft.descriptor);
    } else {
      throw new CallciumError("INVALID_SCOPE", `Unknown scope value ${c.scope}.`);
    }

    const key = `${c.scope}:${c.path.toLowerCase()}`;
    const currentHashes = this.draft.pathHashes[this.draft.pathHashes.length - 1]!;
    if (currentHashes.has(key)) {
      throw new CallciumError("DUPLICATE_PATH", `Duplicate path ${c.path} in the same group.`);
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
   * Build the policy into an encoded binary blob.
   * @returns The policy as a 0x-prefixed hex string.
   * @throws {CallciumError} If any group is empty or validation finds errors.
   */
  build(): Hex {
    this.checkGroups();
    const policyData = this.toPolicyData();
    const issues = PolicyValidator.validate(policyData);
    const firstError = issues.find((issue) => issue.severity === "error");
    if (firstError) {
      throw new CallciumError("VALIDATION_ERROR", firstError.message);
    }
    return PolicyCoder.encode(policyData);
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

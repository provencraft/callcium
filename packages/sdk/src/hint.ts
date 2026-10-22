import { writeBE16, writeBE32 } from "./bytes";
import { DescriptorFormat as DF, PolicyFormat as PF, TypeCode } from "./constants";
import { Descriptor } from "./descriptor";
import { CallciumError } from "./errors";

///////////////////////////////////////////////////////////////////////////
// Types
///////////////////////////////////////////////////////////////////////////

/**
 * Why a path does not compile: an index past its count (parameter, tuple field or static array), a step into an
 * elementary node, or a loop over a non-array node.
 */
export type HintFault = "PARAM_INDEX" | "TUPLE_FIELD" | "ARRAY_INDEX" | "NOT_COMPOSITE" | "NOT_ARRAY";

/** A compiled hint, and the descriptor offset of the target node or of a loop's element node. */
export type CompiledHint = { hint: Uint8Array; node: number };

/**
 * The fault that stopped a compilation: the index of the step at fault, and the bound it broke (a parameter, field or
 * element count, or a type code).
 */
export type HintFaultResult = { fault: HintFault; stepIndex: number; bound: number };

/** A compiled hint, or the fault that stopped its compilation. */
export type Compiled = CompiledHint | HintFaultResult;

/** State threaded through the walk of a path. */
type Walk = {
  /** The hops emitted so far: delta, index and meta. */
  hops: [number, number, number][];
  /** Byte offset of the current node's head from the chain's last base. */
  delta: number;
  /** Whether the chain ends inside the current node, which then takes no entry hop. */
  entered: boolean;
  /** Descriptor offset of the current node. */
  node: number;
};

///////////////////////////////////////////////////////////////////////////
// Compilation
///////////////////////////////////////////////////////////////////////////

/**
 * Compile a test's hint for `steps`. Without `element`, the path starts at the arguments and its first step is a
 * parameter index. Given `element`, the path starts at the loop element whose node lies there, and an empty path
 * is the element itself.
 */
function compileTest(desc: Uint8Array, steps: readonly number[], element?: number): Compiled {
  const walk: Walk = { hops: [], delta: 0, entered: true, node: element ?? 0 };
  const fault = element === undefined ? walkArguments(desc, steps, walk) : walkSteps(desc, steps, 0, walk);
  if (fault !== undefined) return fault;

  // A dynamic target is entered, so the hint ends where its encoding starts.
  const target = Descriptor.inspect(desc, walk.node);
  enter(walk, target.isDynamic && !walk.entered);
  const targetMeta = target.typeCode === TypeCode.DYNAMIC_ARRAY ? arrayMeta(desc, walk.node, target.typeCode) : 0;

  const hint = new Uint8Array(PF.HINT_HEADER_SIZE + walk.hops.length * PF.HINT_HOP_SIZE + PF.HINT_TARGET_SIZE);
  const offset = writeHops(hint, walk);
  writeBE32(hint, offset, walk.delta);
  writeBE16(hint, offset + PF.HINT_TARGET_META_OFFSET, targetMeta);
  hint[offset + PF.HINT_TARGET_TYPECODE_OFFSET] = target.typeCode;
  return { hint, node: walk.node };
}

/** Compile a loop's hint for the array at `steps` from the arguments, the first step a parameter index. */
function compileLoop(desc: Uint8Array, steps: readonly number[]): Compiled {
  const walk: Walk = { hops: [], delta: 0, entered: true, node: 0 };
  const fault = walkArguments(desc, steps, walk);
  if (fault !== undefined) return fault;

  const array = Descriptor.inspect(desc, walk.node);
  let count = 0;
  if (array.typeCode === TypeCode.STATIC_ARRAY) {
    enter(walk, array.isDynamic && !walk.entered);
    count = Descriptor.staticArrayLength(desc, walk.node);
  } else if (array.typeCode === TypeCode.DYNAMIC_ARRAY) {
    enter(walk, !walk.entered);
  } else {
    return { fault: "NOT_ARRAY", stepIndex: steps.length, bound: array.typeCode };
  }

  const hint = new Uint8Array(PF.HINT_HEADER_SIZE + walk.hops.length * PF.HINT_HOP_SIZE + PF.HINT_FRAME_PREFIX_SIZE);
  const offset = writeHops(hint, walk);
  writeBE32(hint, offset, walk.delta);
  writeBE16(hint, offset + PF.HINT_FRAME_COUNT_OFFSET, count);
  writeBE16(hint, offset + PF.HINT_FRAME_META_OFFSET, arrayMeta(desc, walk.node, array.typeCode));
  return { hint, node: Descriptor.arrayElementOffset(walk.node) };
}

/**
 * Return the compiled hint, or throw the error that names `compiled`'s fault.
 * @param compiled - The compilation result.
 * @param steps - The path the steps of `compiled` index into.
 * @param stepOffset - The index in `steps` of the first step `compiled` walked.
 * @throws {CallciumError} When the path does not compile.
 */
function requireCompiled(compiled: Compiled, steps: readonly number[], stepOffset: number): CompiledHint {
  if (!("fault" in compiled)) return compiled;
  const stepIndex = stepOffset + compiled.stepIndex;
  const step = steps[stepIndex];
  switch (compiled.fault) {
    case "PARAM_INDEX":
      throw new CallciumError(
        "PARAM_INDEX_OUT_OF_BOUNDS",
        `Param index ${step} out of range (descriptor has ${compiled.bound} params)`,
      );
    case "TUPLE_FIELD":
      throw new CallciumError(
        "TUPLE_FIELD_OUT_OF_BOUNDS",
        `Tuple field index ${step} out of range (tuple has ${compiled.bound} fields)`,
      );
    case "ARRAY_INDEX":
      throw new CallciumError(
        "STATIC_ARRAY_INDEX_OUT_OF_BOUNDS",
        `Array index ${step} out of range (static array has ${compiled.bound} elements)`,
      );
    case "NOT_COMPOSITE":
      throw new CallciumError("NOT_COMPOSITE", "Cannot descend into an elementary type");
    case "NOT_ARRAY":
      throw new CallciumError("QUANTIFIER_ON_NON_ARRAY", "Quantifier step is only valid on an array node");
    default:
      throw compiled.fault satisfies never;
  }
}

///////////////////////////////////////////////////////////////////////////
// Walk
///////////////////////////////////////////////////////////////////////////

/**
 * Walk `steps` from the arguments, whose encoding starts at the base. The first step selects a parameter, whose head
 * lies past the heads of the parameters before it.
 */
function walkArguments(desc: Uint8Array, steps: readonly number[], walk: Walk): HintFaultResult | undefined {
  const argIndex = steps[0]!;
  const paramCount = Descriptor.paramCount(desc);
  if (argIndex >= paramCount) return { fault: "PARAM_INDEX", stepIndex: 0, bound: paramCount };
  const arg = headSpan(desc, DF.HEADER_SIZE, argIndex);
  walk.delta = arg.span;
  walk.entered = false;
  walk.node = arg.nodeOffset;
  return walkSteps(desc, steps, 1, walk);
}

/** Walk the steps from `firstStep` on, each into the field or element of the current node. */
function walkSteps(
  desc: Uint8Array,
  steps: readonly number[],
  firstStep: number,
  walk: Walk,
): HintFaultResult | undefined {
  for (let stepIndex = firstStep; stepIndex < steps.length; stepIndex++) {
    const step = steps[stepIndex]!;
    const node = Descriptor.inspect(desc, walk.node);

    if (node.typeCode === TypeCode.TUPLE) {
      const fieldCount = Descriptor.tupleFieldCount(desc, walk.node);
      if (step >= fieldCount) return { fault: "TUPLE_FIELD", stepIndex, bound: fieldCount };
      enter(walk, node.isDynamic && !walk.entered);
      const field = headSpan(desc, walk.node + DF.TUPLE_HEADER_SIZE, step);
      walk.delta += field.span;
      walk.entered = false;
      walk.node = field.nodeOffset;
    } else if (node.typeCode === TypeCode.STATIC_ARRAY || node.typeCode === TypeCode.DYNAMIC_ARRAY) {
      if (node.typeCode === TypeCode.STATIC_ARRAY) {
        const arrayLength = Descriptor.staticArrayLength(desc, walk.node);
        if (step >= arrayLength) return { fault: "ARRAY_INDEX", stepIndex, bound: arrayLength };
      }
      const element = Descriptor.arrayElementOffset(walk.node);
      const elementInfo = Descriptor.inspect(desc, element);

      if (node.isDynamic) {
        // An indirected array holds its elements behind an offset word.
        enter(walk, !walk.entered);
        walk.hops.push([0, step, arrayMeta(desc, walk.node, node.typeCode)]);
        walk.delta = 0;
        walk.entered = elementInfo.isDynamic;
      } else {
        // A static array of static elements is inline, so the index folds into the delta.
        walk.delta += step * elementInfo.staticSize;
        walk.entered = false;
      }
      walk.node = element;
    } else {
      return { fault: "NOT_COMPOSITE", stepIndex, bound: node.typeCode };
    }
  }
  return undefined;
}

/** Append the hop entering an indirected node's payload when `needed`, and rebase the delta. */
function enter(walk: Walk, needed: boolean): void {
  if (!needed) return;
  walk.hops.push([walk.delta, PF.HINT_NO_INDEX, 0]);
  walk.delta = 0;
}

/** Write the hint header, the hop count with the reserved bits zero, and the hops. Return the offset past the hops. */
function writeHops(hint: Uint8Array, walk: Walk): number {
  hint[0] = walk.hops.length;
  let offset = PF.HINT_HEADER_SIZE;
  for (const [delta, index, meta] of walk.hops) {
    writeBE32(hint, offset, delta);
    writeBE16(hint, offset + PF.HINT_HOP_INDEX_OFFSET, index);
    writeBE16(hint, offset + PF.HINT_HOP_META_OFFSET, meta);
    offset += PF.HINT_HOP_SIZE;
  }
  return offset;
}

/** Return the combined head span of the `count` nodes at `offset`, and the offset of the node past them. */
function headSpan(desc: Uint8Array, offset: number, count: number): { span: number; nodeOffset: number } {
  let span = 0;
  let nodeOffset = offset;
  for (let i = 0; i < count; i++) {
    const node = Descriptor.inspect(desc, nodeOffset);
    // An indirected node occupies a single offset word.
    span += node.isDynamic ? 32 : node.staticSize;
    nodeOffset += Descriptor.nodeLength(desc, nodeOffset);
  }
  return { span, nodeOffset };
}

/** Return the meta word describing the array node at `arrayOffset`. */
function arrayMeta(desc: Uint8Array, arrayOffset: number, typeCode: number): number {
  const element = Descriptor.inspect(desc, Descriptor.arrayElementOffset(arrayOffset));
  // A dynamic element occupies one offset word within the element region.
  let meta = element.isDynamic ? 1 : element.staticSize >> 5;
  if (element.isDynamic) meta |= PF.HINT_META_ELEM_DYNAMIC;
  if (typeCode === TypeCode.DYNAMIC_ARRAY) meta |= PF.HINT_META_DYNAMIC_ARRAY;
  return meta;
}

/** Compile paths into the hints that address their targets in calldata. */
export const Hint = { compileTest, compileLoop, requireCompiled };

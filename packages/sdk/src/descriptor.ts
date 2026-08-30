import { readU16, readU24, writeBE16, writeBE32 } from "./bytes";
import { DescriptorFormat as DF, PolicyFormat as PF, TypeCode } from "./constants";
import { CallciumError } from "./errors";
import { Quantifier, isQuantifier } from "./path";

///////////////////////////////////////////////////////////////////////////
// Public types
///////////////////////////////////////////////////////////////////////////

/** Structural type information extracted from a descriptor node. */
export type TypeInfo = {
  typeCode: number;
  isDynamic: boolean;
  staticSize: number;
};

///////////////////////////////////////////////////////////////////////////
// Internal types
///////////////////////////////////////////////////////////////////////////

/** A hop entry of a compiled chain: [delta, index, meta]. */
type Hop = [number, number, number];

/** State threaded through the compilation of a path into a hint block. */
type HintWalk = {
  /** Hops of the chain currently being compiled. */
  chain: Hop[];
  /** Hops of the main chain, captured when a quantifier closes it. */
  mainHops: Hop[];
  /** Byte offset of the next node relative to the chain's current base. */
  delta: number;
  /** Frame prefix fields, captured when a quantifier closes the main chain. */
  frame: { arrayDelta: number; count: number; meta: number };
  /** Header kind the path resolves to. */
  kind: number;
  /** Set while the chain already ends inside the current node, which then takes no entry hop. */
  entered: boolean;
};

///////////////////////////////////////////////////////////////////////////
// Internal helpers
///////////////////////////////////////////////////////////////////////////

/**
 * Return the byte length of the node at `offset`.
 * Elementary nodes occupy exactly one byte; composite nodes encode their
 * length in the lower 12 bits of the 24-bit meta field.
 */
function nodeLength(desc: Uint8Array, offset: number): number {
  const typeCode = desc[offset]!;
  if (typeCode < TypeCode.STATIC_ARRAY) return DF.TYPECODE_SIZE;
  return readU24(desc, offset + 1) & DF.META_NODE_LENGTH_MASK;
}

/**
 * Return the byte offset of the `fieldIndex`-th field inside a tuple node.
 * Starts at the first field and skips `fieldIndex` nodes using `nodeLength`.
 */
function tupleFieldOffset(desc: Uint8Array, tupleOffset: number, fieldIndex: number): number {
  let cursor = tupleOffset + DF.TUPLE_HEADER_SIZE;
  for (let i = 0; i < fieldIndex; i++) {
    cursor += nodeLength(desc, cursor);
  }
  return cursor;
}

///////////////////////////////////////////////////////////////////////////
// Public interface
///////////////////////////////////////////////////////////////////////////

/** Return paramCount from header byte 1. */
function paramCount(desc: Uint8Array): number {
  return desc[1]!;
}

/** Return byte offset of the N-th top-level param (0-indexed). */
function paramOffset(desc: Uint8Array, index: number): number {
  const count = desc[1]!;
  if (index >= count) {
    throw new CallciumError("PARAM_INDEX_OUT_OF_BOUNDS", `Param index ${index} out of range (paramCount=${count})`);
  }
  let cursor = DF.HEADER_SIZE;
  for (let i = 0; i < index; i++) {
    cursor += nodeLength(desc, cursor);
  }
  return cursor;
}

/**
 * Inspect the type node at a given byte offset.
 * @param desc - Raw descriptor bytes.
 * @param offset - Byte position of the node.
 * @returns typeCode, isDynamic, and staticSize in bytes.
 */
function inspect(desc: Uint8Array, offset: number): TypeInfo {
  const typeCode = desc[offset]!;
  let staticWords: number;
  if (typeCode < TypeCode.STATIC_ARRAY) {
    staticWords = typeCode === TypeCode.BYTES || typeCode === TypeCode.STRING ? 0 : 1;
  } else {
    staticWords = readU24(desc, offset + 1) >> DF.META_STATIC_WORDS_SHIFT;
  }
  const isDynamic = staticWords === 0;
  return { typeCode, isDynamic, staticSize: staticWords * 32 };
}

/**
 * Resolve the type at a calldata path (array of step indices).
 *
 * The first step selects a top-level param. Each subsequent step descends
 * into the current node: for tuples it selects a field, for arrays it
 * advances to the element descriptor.
 *
 * @param desc - Raw descriptor bytes.
 * @param steps - Path steps, length >= 1.
 * @returns TypeInfo for the node at the resolved path.
 * @throws {CallciumError} On empty steps, out-of-bounds param or array index, or descent into elementary type.
 */
function typeAt(desc: Uint8Array, steps: number[]): TypeInfo {
  return walkPath(desc, steps).typeInfo;
}

/**
 * Resolve the type at the path and the declared length of the static array a
 * quantifier step descends into (zero when the path holds no quantifier step
 * over a static array).
 * @param desc - Raw descriptor bytes.
 * @param steps - Path steps, length >= 1.
 * @returns TypeInfo at the resolved path and the quantified static array length.
 * @throws {CallciumError} On empty steps, out-of-bounds param or array index, or descent into elementary type.
 */
function walkPath(desc: Uint8Array, steps: number[]): { typeInfo: TypeInfo; quantifiedStaticLength: number } {
  if (steps.length === 0) {
    throw new CallciumError("EMPTY_PATH", "Path must have at least one step");
  }

  const paramIndex = steps[0]!;
  const count = desc[1]!;
  if (paramIndex >= count) {
    throw new CallciumError(
      "PARAM_INDEX_OUT_OF_BOUNDS",
      `Param index ${paramIndex} out of range (paramCount=${count})`,
    );
  }

  let cursor = paramOffset(desc, paramIndex);
  let quantifiedStaticLength = 0;

  for (let stepIndex = 1; stepIndex < steps.length; stepIndex++) {
    const typeCode = desc[cursor]!;
    const step = steps[stepIndex]!;

    if (typeCode === TypeCode.TUPLE) {
      const fields = tupleFieldCount(desc, cursor);
      if (step >= fields) {
        throw new CallciumError(
          "TUPLE_FIELD_OUT_OF_BOUNDS",
          `Tuple field index ${step} out of range (tuple has ${fields} fields)`,
        );
      }
      cursor = tupleFieldOffset(desc, cursor, step);
    } else if (typeCode === TypeCode.STATIC_ARRAY || typeCode === TypeCode.DYNAMIC_ARRAY) {
      // Quantifier sentinels descend into the element type; only concrete
      // indices are bounds-checked against the declared array length.
      if (typeCode === TypeCode.STATIC_ARRAY) {
        if (isQuantifier(step)) {
          quantifiedStaticLength = staticArrayLength(desc, cursor);
        } else {
          const length = staticArrayLength(desc, cursor);
          if (step >= length) {
            throw new CallciumError(
              "STATIC_ARRAY_INDEX_OUT_OF_BOUNDS",
              `Array index ${step} out of range (length=${length})`,
            );
          }
        }
      }
      cursor = arrayElementOffset(cursor);
    } else {
      throw new CallciumError("NOT_COMPOSITE", `Cannot descend into elementary type at offset ${cursor}`);
    }
  }

  return { typeInfo: inspect(desc, cursor), quantifiedStaticLength };
}

/**
 * Return tuple field count at a tuple node offset.
 * @param desc - Raw descriptor bytes.
 * @param offset - Byte position of the tuple node.
 */
function tupleFieldCount(desc: Uint8Array, offset: number): number {
  return readU16(desc, offset + 4);
}

/**
 * Return static array length at a static array node offset.
 * @param desc - Raw descriptor bytes.
 * @param offset - Byte position of the static array node.
 */
function staticArrayLength(desc: Uint8Array, offset: number): number {
  const elemOffset = arrayElementOffset(offset);
  const elemNodeLength = nodeLength(desc, elemOffset);
  const lengthOffset = elemOffset + elemNodeLength;
  return readU16(desc, lengthOffset);
}

/**
 * Return the byte offset of the array element descriptor.
 * @param offset - Byte position of the array node (static or dynamic).
 */
function arrayElementOffset(offset: number): number {
  return offset + DF.ARRAY_HEADER_SIZE;
}

/** Build the error for a path step that does not resolve to a hop-chain target. */
function uncompilablePath(stepIndex: number): CallciumError {
  return new CallciumError("UNCOMPILABLE_PATH", `Path step ${stepIndex} does not resolve to a hop-chain target`);
}

/** Return the combined head slot span of the `count` nodes at `offset`, and the offset of the node past them. */
function headSpan(desc: Uint8Array, offset: number, count: number): { span: number; nodeOffset: number } {
  let span = 0;
  let nodeOffset = offset;
  for (let i = 0; i < count; i++) {
    const node = inspect(desc, nodeOffset);
    // An indirected node occupies a single offset word.
    span += node.isDynamic ? 32 : node.staticSize;
    nodeOffset += nodeLength(desc, nodeOffset);
  }
  return { span, nodeOffset };
}

/** Return the meta word describing the array node at `arrayOffset`, and whether its elements are dynamic. */
function arrayMeta(desc: Uint8Array, arrayOffset: number, code: number): { meta: number; elemIsDynamic: boolean } {
  const element = inspect(desc, arrayElementOffset(arrayOffset));
  // A dynamic element occupies one offset word within the element region.
  let meta = element.isDynamic ? 1 : element.staticSize >> 5;
  if (element.isDynamic) meta |= PF.HINT_META_ELEM_DYNAMIC;
  if (code === TypeCode.DYNAMIC_ARRAY) meta |= PF.HINT_META_DYNAMIC_ARRAY;
  return { meta, elemIsDynamic: element.isDynamic };
}

/** Append the hop entering an indirected node's payload and rebase the offset accumulator. */
function enterNode(walk: HintWalk, needed: boolean): void {
  if (!needed) return;
  walk.chain.push([walk.delta, PF.HINT_NO_INDEX, 0]);
  walk.delta = 0;
}

/** Apply one path step to `walk` and return the descriptor offset the step reaches. */
function walkStep(desc: Uint8Array, walk: HintWalk, descOffset: number, step: number, stepIndex: number): number {
  const node = inspect(desc, descOffset);

  // A quantifier reaches an array alone, every other code reading its value as an index.
  if (node.typeCode === TypeCode.TUPLE) {
    if (step >= tupleFieldCount(desc, descOffset)) throw uncompilablePath(stepIndex);
    enterNode(walk, node.isDynamic && !walk.entered);

    const field = headSpan(desc, descOffset + DF.TUPLE_HEADER_SIZE, step);
    walk.delta += field.span;
    walk.entered = false;
    return field.nodeOffset;
  }

  if (node.typeCode !== TypeCode.STATIC_ARRAY && node.typeCode !== TypeCode.DYNAMIC_ARRAY) {
    throw uncompilablePath(stepIndex);
  }
  if (node.typeCode === TypeCode.STATIC_ARRAY && !isQuantifier(step) && step >= staticArrayLength(desc, descOffset)) {
    throw uncompilablePath(stepIndex);
  }
  const { meta, elemIsDynamic } = arrayMeta(desc, descOffset, node.typeCode);

  if (isQuantifier(step)) {
    if (walk.kind !== PF.HINT_KIND_NONE) throw uncompilablePath(stepIndex);
    enterNode(walk, node.isDynamic && !walk.entered);

    const count = node.typeCode === TypeCode.DYNAMIC_ARRAY ? 0 : staticArrayLength(desc, descOffset);
    walk.frame = { arrayDelta: walk.delta, count, meta };
    walk.kind = step === Quantifier.ALL ? PF.HINT_KIND_ALL : PF.HINT_KIND_ANY;

    walk.mainHops = walk.chain;
    walk.chain = [];
    walk.delta = 0;
  } else if (node.isDynamic) {
    // An indirected array holds its elements behind an offset word.
    enterNode(walk, !walk.entered);
    walk.chain.push([0, step, meta]);
    walk.delta = 0;
  } else {
    // A static array of static elements is inline, so the index folds into the accumulator.
    walk.delta += step * (meta & PF.HINT_META_STRIDE_MASK) * 32;
  }

  walk.entered = elemIsDynamic;
  return arrayElementOffset(descOffset);
}

/** Serialize hop entries at `offset` and return the offset past them. */
function writeHops(out: Uint8Array, offset: number, hops: Hop[]): number {
  for (const [delta, index, meta] of hops) {
    writeBE32(out, offset, delta);
    writeBE16(out, offset + PF.HINT_HOP_INDEX_OFFSET, index);
    writeBE16(out, offset + PF.HINT_HOP_META_OFFSET, meta);
    offset += PF.HINT_HOP_SIZE;
  }
  return offset;
}

/** Serialize a completed walk and its target block into the wire hint block. */
function encodeHint(walk: HintWalk, targetMeta: number, typeCode: number, depth: number): Uint8Array {
  let suffixHops: Hop[] = [];
  if (walk.kind === PF.HINT_KIND_NONE) walk.mainHops = walk.chain;
  else suffixHops = walk.chain;

  const mainHopCount = walk.mainHops.length;
  const suffixHopCount = suffixHops.length;
  if (mainHopCount > PF.HINT_HOP_COUNT_MASK || suffixHopCount > PF.HINT_HOP_COUNT_MASK) {
    throw uncompilablePath(depth);
  }

  const quantified = walk.kind !== PF.HINT_KIND_NONE;
  const frameSize = quantified
    ? PF.HINT_FRAME_PREFIX_SIZE + PF.HINT_HEADER_SIZE + suffixHopCount * PF.HINT_HOP_SIZE
    : 0;
  const out = new Uint8Array(PF.HINT_HEADER_SIZE + mainHopCount * PF.HINT_HOP_SIZE + frameSize + PF.HINT_TARGET_SIZE);

  let offset = 0;
  out[offset] = (walk.kind << PF.HINT_KIND_SHIFT) | mainHopCount;
  offset = writeHops(out, offset + PF.HINT_HEADER_SIZE, walk.mainHops);

  if (quantified) {
    writeBE32(out, offset, walk.frame.arrayDelta);
    writeBE16(out, offset + PF.HINT_FRAME_COUNT_OFFSET, walk.frame.count);
    writeBE16(out, offset + PF.HINT_FRAME_META_OFFSET, walk.frame.meta);
    out[offset + PF.HINT_FRAME_PREFIX_SIZE] = suffixHopCount;
    offset = writeHops(out, offset + PF.HINT_FRAME_PREFIX_SIZE + PF.HINT_HEADER_SIZE, suffixHops);
  }

  writeBE32(out, offset, walk.delta);
  writeBE16(out, offset + PF.HINT_TARGET_META_OFFSET, targetMeta);
  out[offset + PF.HINT_TARGET_TYPECODE_OFFSET] = typeCode;
  return out;
}

/**
 * Compile a calldata rule path into its wire hint block.
 *
 * @param desc - Raw descriptor bytes.
 * @param steps - Path steps, length >= 1.
 * @returns The hint block bytes.
 * @throws {CallciumError} When a step leaves the structure the descriptor declares, quantifies over
 * a non-array node, or repeats a quantifier.
 */
function compileHint(desc: Uint8Array, steps: number[]): Uint8Array {
  if (steps.length === 0) {
    throw new CallciumError("EMPTY_PATH", "Path must have at least one step");
  }

  const argIndex = steps[0]!;
  if (argIndex >= paramCount(desc)) throw uncompilablePath(0);

  // The argument's head slot sits past the slots of every preceding parameter.
  const arg = headSpan(desc, DF.HEADER_SIZE, argIndex);
  const walk: HintWalk = {
    chain: [],
    mainHops: [],
    delta: arg.span,
    frame: { arrayDelta: 0, count: 0, meta: 0 },
    kind: PF.HINT_KIND_NONE,
    entered: false,
  };

  let descOffset = arg.nodeOffset;
  for (let stepIndex = 1; stepIndex < steps.length; stepIndex++) {
    descOffset = walkStep(desc, walk, descOffset, steps[stepIndex]!, stepIndex);
  }

  const target = inspect(desc, descOffset);
  enterNode(walk, target.isDynamic && !walk.entered);

  const targetMeta = target.typeCode === TypeCode.DYNAMIC_ARRAY ? arrayMeta(desc, descOffset, target.typeCode).meta : 0;

  return encodeHint(walk, targetMeta, target.typeCode, steps.length);
}

/** Inspect and navigate raw descriptor bytes. */
export const Descriptor = {
  paramCount,
  paramOffset,
  inspect,
  typeAt,
  tupleFieldOffset,
  tupleFieldCount,
  staticArrayLength,
  nodeLength,
  arrayElementOffset,
  walkPath,
  compileHint,
};

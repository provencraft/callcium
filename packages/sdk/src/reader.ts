import { readU16 } from "./bytes";
import { isQuantifier } from "./constants";
import { CallciumError } from "./errors";

import type { DescNode, DynamicArrayNode, StaticArrayNode, TupleNode, ViolationCode } from "./types";

///////////////////////////////////////////////////////////////////////////
// Result Types
///////////////////////////////////////////////////////////////////////////

/** Generic result type for operations that can fail with a violation code. */
export type Result<T> = ({ ok: true } & T) | { ok: false; code: ViolationCode };

/** Result of a calldata read: success with data, or failure with a violation code. */
export type ReadResult<T> = T | { code: ViolationCode };

/** A resolved position within calldata, pairing a descriptor node with its ABI head and base offsets. */
export type Location = {
  /** Byte offset of the node's head (value slot for static, pointer slot for dynamic). */
  head: number;
  /** Composite start for resolving composite-relative offsets. */
  base: number;
  node: DescNode;
};

/** Structural info for an array at a resolved location, pre-computed for element iteration. */
export type ArrayShape = {
  length: number;
  elementNode: DescNode;
  elementIsDynamic: boolean;
  elementStaticSize: number;
  headsBase: number;
  dataOffset: number;
  compositeBase: number;
};

/** Result when locate encounters a quantifier step in the path. */
export type QuantifierResult = {
  quantifier: number;
  location: Location;
  remainingPath: Uint8Array;
};

/** Result of locating a path target. */
export type LocateResult =
  | { ok: true; type: "leaf"; location: Location }
  | { ok: true; type: "quantifier"; quantifier: QuantifierResult }
  | { ok: false; code: ViolationCode };

/** Result of computing array shape. */
export type ArrayShapeResult = Result<{ shape: ArrayShape }>;

/** Result of resolving an array element location. */
export type LocationResult = Result<{ location: Location }>;

/** Result of loading a scalar value. */
export type LoadResult = Result<{ value: Uint8Array }>;

/** Dynamic sequence payload: data offset and logical length (bytes for bytes/string, elements for arrays). */
export type SliceResult = Result<{ dataOffset: number; length: number }>;

///////////////////////////////////////////////////////////////////////////
// Calldata Reading Primitives
///////////////////////////////////////////////////////////////////////////

/** Read 32 bytes at offset, bounds-checked. */
export function load32(callData: Uint8Array, offset: number): ReadResult<Uint8Array> {
  if (offset < 0 || offset + 32 > callData.length) {
    return { code: "CALLDATA_TOO_SHORT" };
  }
  return callData.subarray(offset, offset + 32);
}

/**
 * Read ABI pointer (offset or length) from a 32-byte slot.
 * Validates high 28 bytes are zero (rejects values > 32-bit).
 */
export function readPointer(callData: Uint8Array, head: number): ReadResult<number> {
  const word = load32(callData, head);
  if (word instanceof Uint8Array) {
    for (let i = 0; i < 28; i++) {
      if (word[i] !== 0) return { code: "OFFSET_OUT_OF_BOUNDS" };
    }
    return ((word[28]! << 24) | (word[29]! << 16) | (word[30]! << 8) | word[31]!) >>> 0;
  }
  return word; // propagate CALLDATA_TOO_SHORT
}

///////////////////////////////////////////////////////////////////////////
// Internal Helpers
///////////////////////////////////////////////////////////////////////////

/** Return the number of bytes this node occupies in the head region. */
function headContribution(node: DescNode): number {
  return node.isDynamic ? 32 : node.staticSize;
}

/** Read a single BE16 path step at the given step index. */
function readStep(pathBytes: Uint8Array, stepIndex: number): number {
  return readU16(pathBytes, stepIndex * 2);
}

///////////////////////////////////////////////////////////////////////////
// SINGLE-STEP Descent
///////////////////////////////////////////////////////////////////////////

type DescendResult =
  | { type: "ok"; head: number; base: number; node: DescNode }
  | { type: "violation"; code: ViolationCode };

/** Navigate one path step through a node (tuple field, array element, or quantifier). */
function descend(node: DescNode, callData: Uint8Array, head: number, base: number, childIndex: number): DescendResult {
  if (node.type === "tuple") {
    return descendTuple(node, callData, head, base, childIndex);
  }
  if (node.type === "dynamicArray") {
    return descendDynamicArray(node, callData, head, base, childIndex);
  }
  if (node.type === "staticArray") {
    return descendStaticArray(node, callData, head, base, childIndex);
  }
  return { type: "violation", code: "OFFSET_OUT_OF_BOUNDS" };
}

/** Descend into a tuple field by index. */
function descendTuple(
  node: TupleNode,
  callData: Uint8Array,
  head: number,
  base: number,
  childIndex: number,
): DescendResult {
  if (childIndex >= node.fields.length) {
    return { type: "violation", code: "OFFSET_OUT_OF_BOUNDS" };
  }

  let tupleBase: number;
  let cursor: number;

  if (node.isDynamic) {
    const ptrResult = readPointer(callData, head);
    if (typeof ptrResult !== "number") return { type: "violation", code: ptrResult.code };
    tupleBase = base + ptrResult;
    cursor = tupleBase;
  } else {
    tupleBase = base;
    cursor = head;
  }

  for (let i = 0; i < childIndex; i++) {
    cursor += headContribution(node.fields[i]!);
  }

  return {
    type: "ok",
    head: cursor,
    base: tupleBase,
    node: node.fields[childIndex]!,
  };
}

/** Descend into a dynamic array element by index. */
function descendDynamicArray(
  node: DynamicArrayNode,
  callData: Uint8Array,
  head: number,
  base: number,
  childIndex: number,
): DescendResult {
  const arrayBaseResult = readPointer(callData, head);
  if (typeof arrayBaseResult !== "number") return { type: "violation", code: arrayBaseResult.code };
  const arrayBase = base + arrayBaseResult;

  const lengthResult = readPointer(callData, arrayBase);
  if (typeof lengthResult !== "number") return { type: "violation", code: lengthResult.code };

  if (childIndex >= lengthResult) {
    return { type: "violation", code: "OFFSET_OUT_OF_BOUNDS" };
  }

  const headsBase = arrayBase + 32;
  const elem = node.element;

  if (elem.isDynamic) {
    return {
      type: "ok",
      head: headsBase + childIndex * 32,
      base: headsBase,
      node: elem,
    };
  }
  return {
    type: "ok",
    head: headsBase + childIndex * elem.staticSize,
    base: arrayBase,
    node: elem,
  };
}

/** Descend into a static array element by index. */
function descendStaticArray(
  node: StaticArrayNode,
  callData: Uint8Array,
  head: number,
  base: number,
  childIndex: number,
): DescendResult {
  if (childIndex >= node.length) {
    return { type: "violation", code: "OFFSET_OUT_OF_BOUNDS" };
  }

  const elem = node.element;

  if (elem.isDynamic) {
    const ptrResult = readPointer(callData, head);
    if (typeof ptrResult !== "number") return { type: "violation", code: ptrResult.code };
    const arrayBase = base + ptrResult;
    return {
      type: "ok",
      head: arrayBase + childIndex * 32,
      base: arrayBase,
      node: elem,
    };
  }
  return {
    type: "ok",
    head: head + childIndex * elem.staticSize,
    base,
    node: elem,
  };
}

///////////////////////////////////////////////////////////////////////////
// Composable API
///////////////////////////////////////////////////////////////////////////

/**
 * Resolve a path to a calldata location, stopping at a leaf or quantifier.
 *
 * The path is a sequence of BE16 steps. The first step selects the top-level
 * parameter; subsequent steps descend into tuples and arrays. If a quantifier
 * step is encountered, returns a QuantifierResult with the array location and
 * remaining path suffix.
 */
export function locate(
  tree: DescNode[],
  callData: Uint8Array,
  pathBytes: Uint8Array,
  baseOffset: number,
): LocateResult {
  const stepCount = pathBytes.length / 2;
  if (stepCount === 0) {
    return { ok: false, code: "CALLDATA_TOO_SHORT" };
  }

  // Step 0: resolve the target parameter.
  const paramIndex = readStep(pathBytes, 0);
  if (paramIndex >= tree.length) {
    return { ok: false, code: "OFFSET_OUT_OF_BOUNDS" };
  }

  let head = baseOffset;
  for (let i = 0; i < paramIndex; i++) {
    head += headContribution(tree[i]!);
  }
  let base = baseOffset;
  let node = tree[paramIndex]!;

  // Steps 1..N: descend through the tree.
  for (let s = 1; s < stepCount; s++) {
    const step = readStep(pathBytes, s);

    // Quantifier step: return the array location and remaining path.
    if (isQuantifier(step)) {
      const remaining = pathBytes.subarray((s + 1) * 2);
      // Defence-in-depth: reject nested quantifiers in hand-crafted blobs.
      for (let r = 0; r < remaining.length / 2; r++) {
        if (isQuantifier(readStep(remaining, r))) {
          throw new CallciumError("INVALID_QUANTIFIER", "Nested quantifiers are not supported.");
        }
      }
      return {
        ok: true,
        type: "quantifier",
        quantifier: {
          quantifier: step,
          location: { head, base, node },
          remainingPath: remaining,
        },
      };
    }

    const result = descend(node, callData, head, base, step);
    if (result.type === "violation") return { ok: false, code: result.code };
    head = result.head;
    base = result.base;
    node = result.node;
  }

  return { ok: true, type: "leaf", location: { head, base, node } };
}

/** Extract array shape from a location pointing to an array node. */
export function arrayShape(callData: Uint8Array, location: Location): ArrayShapeResult {
  const { head, base, node } = location;

  if (node.type === "dynamicArray") {
    const arrayBaseResult = readPointer(callData, head);
    if (typeof arrayBaseResult !== "number") return { ok: false, code: arrayBaseResult.code };
    const arrayBase = base + arrayBaseResult;

    const lengthResult = readPointer(callData, arrayBase);
    if (typeof lengthResult !== "number") return { ok: false, code: lengthResult.code };

    const elem = node.element;
    const headsBase = arrayBase + 32;

    if (elem.isDynamic) {
      return {
        ok: true,
        shape: {
          length: lengthResult,
          elementNode: elem,
          elementIsDynamic: true,
          elementStaticSize: 0,
          headsBase,
          dataOffset: 0,
          compositeBase: headsBase,
        },
      };
    }
    return {
      ok: true,
      shape: {
        length: lengthResult,
        elementNode: elem,
        elementIsDynamic: false,
        elementStaticSize: elem.staticSize,
        headsBase: 0,
        dataOffset: headsBase,
        compositeBase: arrayBase,
      },
    };
  }

  if (node.type === "staticArray") {
    const elem = node.element;

    if (elem.isDynamic) {
      const arrayBaseResult = readPointer(callData, head);
      if (typeof arrayBaseResult !== "number") return { ok: false, code: arrayBaseResult.code };
      const arrayBase = base + arrayBaseResult;
      return {
        ok: true,
        shape: {
          length: node.length,
          elementNode: elem,
          elementIsDynamic: true,
          elementStaticSize: 0,
          headsBase: arrayBase,
          dataOffset: 0,
          compositeBase: arrayBase,
        },
      };
    }
    return {
      ok: true,
      shape: {
        length: node.length,
        elementNode: elem,
        elementIsDynamic: false,
        elementStaticSize: elem.staticSize,
        headsBase: 0,
        dataOffset: head,
        compositeBase: base,
      },
    };
  }

  return { ok: false, code: "OFFSET_OUT_OF_BOUNDS" };
}

/** Compute the location for element N within a precomputed array shape. */
export function arrayElementAt(shape: ArrayShape, index: number, callData: Uint8Array): LocationResult {
  if (index >= shape.length) {
    return { ok: false, code: "OFFSET_OUT_OF_BOUNDS" };
  }

  let head: number;
  let base: number;

  if (!shape.elementIsDynamic) {
    head = shape.dataOffset + index * shape.elementStaticSize;
    base = shape.compositeBase;
  } else {
    head = shape.headsBase + index * 32;
    base = shape.headsBase;
  }

  if (head + 32 > callData.length) {
    return { ok: false, code: "CALLDATA_TOO_SHORT" };
  }

  return {
    ok: true,
    location: { head, base, node: shape.elementNode },
  };
}

/** Load a 32-byte scalar value from a resolved location. */
export function loadScalar(callData: Uint8Array, location: Location): LoadResult {
  const result = load32(callData, location.head);
  if (result instanceof Uint8Array) {
    return { ok: true, value: result };
  }
  return { ok: false, code: result.code };
}

/** Load the data offset and logical length for a dynamic type (bytes, string, or dynamic array). */
export function loadSlice(callData: Uint8Array, location: Location): SliceResult {
  const ptrResult = readPointer(callData, location.head);
  if (typeof ptrResult !== "number") return { ok: false, code: ptrResult.code };

  const dataStart = location.base + ptrResult;
  const lengthResult = readPointer(callData, dataStart);
  if (typeof lengthResult !== "number") return { ok: false, code: lengthResult.code };

  return { ok: true, dataOffset: dataStart + 32, length: lengthResult };
}

/** Continue navigating through additional path steps from a resolved location. */
export function descendPath(callData: Uint8Array, location: Location, pathBytes: Uint8Array): LocationResult {
  const stepCount = pathBytes.length / 2;
  let { head, base, node } = location;

  for (let s = 0; s < stepCount; s++) {
    const step = readStep(pathBytes, s);
    const result = descend(node, callData, head, base, step);
    if (result.type === "violation") return { ok: false, code: result.code };
    head = result.head;
    base = result.base;
    node = result.node;
  }

  return { ok: true, location: { head, base, node } };
}

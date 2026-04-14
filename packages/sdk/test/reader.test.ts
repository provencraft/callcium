import { describe, expect, test } from "vitest";

import { Quantifier } from "../src/constants";
import {
  load32,
  readPointer,
  locate,
  arrayShape,
  arrayElementAt,
  loadScalar,
  loadSlice,
  descendPath,
} from "../src/reader";

import type { Location, LocateResult } from "../src/reader";
import type { DescNode } from "../src/types";

///////////////////////////////////////////////////////////////////////////
// Helpers
///////////////////////////////////////////////////////////////////////////

/** Assert that a result is ok and narrow the type. */
function assertOk<T extends { ok: boolean }>(result: T): asserts result is Extract<T, { ok: true }> {
  if (!("ok" in result) || !result.ok) {
    throw new Error(`Expected ok result, got: ${JSON.stringify(result)}`);
  }
}

/** Assert that a locate result is an ok leaf and narrow the type. */
function assertLeaf(result: LocateResult): asserts result is Extract<LocateResult, { type: "leaf" }> {
  assertOk(result);
  expect(result.type).toBe("leaf");
}

/** Assert that a locate result is an ok quantifier and narrow the type. */
function assertQuantifier(result: LocateResult): asserts result is Extract<LocateResult, { type: "quantifier" }> {
  assertOk(result);
  expect(result.type).toBe("quantifier");
}

/** Encode a uint256 value as 32 bytes (big-endian). */
function word(value: number): Uint8Array {
  const buf = new Uint8Array(32);
  buf[28] = (value >>> 24) & 0xff;
  buf[29] = (value >>> 16) & 0xff;
  buf[30] = (value >>> 8) & 0xff;
  buf[31] = value & 0xff;
  return buf;
}

/** Concatenate multiple Uint8Arrays. */
function concat(...arrays: Uint8Array[]): Uint8Array {
  const total = arrays.reduce((sum, arr) => sum + arr.length, 0);
  const result = new Uint8Array(total);
  let offset = 0;
  for (const arr of arrays) {
    result.set(arr, offset);
    offset += arr.length;
  }
  return result;
}

/** Encode a path from an array of step indices. */
function path(...steps: number[]): Uint8Array {
  const buf = new Uint8Array(steps.length * 2);
  for (let i = 0; i < steps.length; i++) {
    buf[i * 2] = (steps[i] >>> 8) & 0xff;
    buf[i * 2 + 1] = steps[i] & 0xff;
  }
  return buf;
}

///////////////////////////////////////////////////////////////////////////
// Node constants
///////////////////////////////////////////////////////////////////////////

const UINT256: DescNode = { type: "elementary", typeCode: 0x1f, isDynamic: false, staticSize: 32 };
const ADDRESS: DescNode = { type: "elementary", typeCode: 0x40, isDynamic: false, staticSize: 32 };
const BYTES: DescNode = { type: "elementary", typeCode: 0x70, isDynamic: true, staticSize: 0 };

function staticTupleNode(fields: DescNode[]): DescNode {
  const staticSize = fields.reduce((sum, field) => sum + (field.isDynamic ? 32 : field.staticSize), 0);
  const isDynamic = fields.some((f) => f.isDynamic);
  return {
    type: "tuple",
    typeCode: 0x90,
    isDynamic,
    staticSize: isDynamic ? 0 : staticSize,
    fields,
  };
}

function dynamicTupleNode(fields: DescNode[]): DescNode {
  return {
    type: "tuple",
    typeCode: 0x90,
    isDynamic: true,
    staticSize: 0,
    fields,
  };
}

function staticArrayNode(element: DescNode, length: number): DescNode {
  const isDynamic = element.isDynamic;
  return {
    type: "staticArray",
    typeCode: 0x80,
    isDynamic,
    staticSize: isDynamic ? 0 : element.staticSize * length,
    element,
    length,
  };
}

function dynamicArrayNode(element: DescNode): DescNode {
  return {
    type: "dynamicArray",
    typeCode: 0x81,
    isDynamic: true,
    staticSize: 0,
    element,
  };
}

///////////////////////////////////////////////////////////////////////////
// load32 and readPointer
///////////////////////////////////////////////////////////////////////////

describe("load32", () => {
  test("reads 32 bytes at offset 0", () => {
    const callData = word(42);
    const result = load32(callData, 0);
    expect(result).toBeInstanceOf(Uint8Array);
    if (result instanceof Uint8Array) {
      expect(result[31]).toBe(42);
    }
  });

  test("reads 32 bytes at nonzero offset", () => {
    const callData = concat(word(0), word(99));
    const result = load32(callData, 32);
    expect(result).toBeInstanceOf(Uint8Array);
    if (result instanceof Uint8Array) {
      expect(result[31]).toBe(99);
    }
  });

  test("returns CALLDATA_OUT_OF_BOUNDS when offset exceeds bounds", () => {
    const callData = word(1);
    const result = load32(callData, 1);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("returns CALLDATA_OUT_OF_BOUNDS for empty callData", () => {
    const result = load32(new Uint8Array(0), 0);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("returns CALLDATA_OUT_OF_BOUNDS for negative offset", () => {
    const result = load32(word(1), -1);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("succeeds at exact boundary (offset + 32 == length)", () => {
    const callData = word(7);
    const result = load32(callData, 0);
    expect(result).toBeInstanceOf(Uint8Array);
  });
});

describe("readPointer", () => {
  test("reads a small value", () => {
    const callData = word(0x60);
    const result = readPointer(callData, 0);
    expect(result).toBe(0x60);
  });

  test("reads zero", () => {
    const result = readPointer(word(0), 0);
    expect(result).toBe(0);
  });

  test("reads max uint32", () => {
    // 0xFFFFFFFF in the last 4 bytes.
    const buf = new Uint8Array(32);
    buf[28] = 0xff;
    buf[29] = 0xff;
    buf[30] = 0xff;
    buf[31] = 0xff;
    const result = readPointer(buf, 0);
    expect(result).toBe(0xffffffff);
  });

  test("rejects value with nonzero high bytes", () => {
    const buf = new Uint8Array(32);
    buf[0] = 1; // High byte nonzero
    const result = readPointer(buf, 0);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("rejects value with byte 27 nonzero", () => {
    const buf = new Uint8Array(32);
    buf[27] = 1;
    const result = readPointer(buf, 0);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("propagates CALLDATA_OUT_OF_BOUNDS", () => {
    const result = readPointer(new Uint8Array(16), 0);
    expect(result).toEqual({ code: "CALLDATA_OUT_OF_BOUNDS" });
  });
});

///////////////////////////////////////////////////////////////////////////
// TOP-LEVEL Param Access
///////////////////////////////////////////////////////////////////////////

describe("locate - top-level param access", () => {
  test("single uint256 at base 0", () => {
    const tree: DescNode[] = [UINT256];
    const callData = word(42);
    const result = locate(tree, callData, path(0), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 0, base: 0, node: tree[0] });
  });

  test("second param of (address, uint256) at base 4", () => {
    // ABI layout: selector(4) + address(32) + uint256(32)
    const tree: DescNode[] = [ADDRESS, UINT256];
    const selector = new Uint8Array(4);
    const callData = concat(selector, word(0), word(99));
    const result = locate(tree, callData, path(1), 4);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 36, base: 4, node: tree[1] }); // 4 + 32
  });

  test("first param of (address, uint256) at base 4", () => {
    const tree: DescNode[] = [ADDRESS, UINT256];
    const selector = new Uint8Array(4);
    const callData = concat(selector, word(0), word(99));
    const result = locate(tree, callData, path(0), 4);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 4, base: 4, node: tree[0] });
  });

  test("param index out of bounds throws integrity error", () => {
    const tree: DescNode[] = [UINT256];
    const callData = word(42);
    expect(() => locate(tree, callData, path(1), 0)).toThrow("Param index 1 out of range");
  });

  test("empty path throws integrity error", () => {
    const tree: DescNode[] = [UINT256];
    expect(() => locate(tree, word(42), new Uint8Array(0), 0)).toThrow("Path is empty");
  });
});

///////////////////////////////////////////////////////////////////////////
// Static Tuple Descent
///////////////////////////////////////////////////////////////////////////

describe("locate - static tuple descent", () => {
  test("locate second field of static tuple", () => {
    const tupleNode = staticTupleNode([UINT256, UINT256]);
    const tree: DescNode[] = [tupleNode];
    const callData = concat(word(10), word(20));

    const result = locate(tree, callData, path(0, 1), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 32, base: 0, node: UINT256 });
  });

  test("locate first field of static tuple", () => {
    const tupleNode = staticTupleNode([ADDRESS, UINT256]);
    const tree: DescNode[] = [tupleNode];
    const callData = concat(word(0), word(42));

    const result = locate(tree, callData, path(0, 0), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 0, base: 0, node: ADDRESS });
  });
});

///////////////////////////////////////////////////////////////////////////
// Dynamic Tuple Descent
///////////////////////////////////////////////////////////////////////////

describe("locate - dynamic tuple descent", () => {
  test("locate static field in a dynamic tuple", () => {
    // tuple(uint256, bytes) — dynamic because of bytes field.
    const tupleNode = dynamicTupleNode([UINT256, BYTES]);
    const tree: DescNode[] = [tupleNode];

    const callData = concat(
      word(32), // offset to tuple data (param head)
      word(0xaa), // tuple field 0: uint256 = 0xaa
      word(64), // tuple field 1: offset to bytes data (relative to tuple base)
    );

    const result = locate(tree, callData, path(0, 0), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 32, base: 32, node: UINT256 });
  });

  test("locate second field in a dynamic tuple", () => {
    const tupleNode = dynamicTupleNode([UINT256, BYTES]);
    const tree: DescNode[] = [tupleNode];

    const callData = concat(
      word(32), // offset to tuple data
      word(0xaa), // field 0: uint256
      word(64), // field 1: offset to bytes (relative to tupleBase=32)
    );

    const result = locate(tree, callData, path(0, 1), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 64, base: 32, node: BYTES });
  });
});

///////////////////////////////////////////////////////////////////////////
// Static Array (Static Elements)
///////////////////////////////////////////////////////////////////////////

describe("locate - static array with static elements", () => {
  test("index into uint256[3]", () => {
    const arrNode = staticArrayNode(UINT256, 3);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(100), word(200), word(300));

    const result = locate(tree, callData, path(0, 2), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 64, base: 0, node: UINT256 }); // 0 + 2 * 32
  });

  test("index 0 into uint256[2]", () => {
    const arrNode = staticArrayNode(UINT256, 2);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(11), word(22));

    const result = locate(tree, callData, path(0, 0), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 0, base: 0, node: UINT256 });
  });

  test("out of bounds index throws integrity error", () => {
    const arrNode = staticArrayNode(UINT256, 2);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(11), word(22));

    expect(() => locate(tree, callData, path(0, 2), 0)).toThrow("Static array index 2 out of range");
  });
});

///////////////////////////////////////////////////////////////////////////
// Dynamic Array (Static Elements)
///////////////////////////////////////////////////////////////////////////

describe("locate - dynamic array with static elements", () => {
  test("index into uint256[]", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32), // offset to array data
      word(2), // length = 2
      word(111), // elem 0
      word(222), // elem 1
    );

    const result = locate(tree, callData, path(0, 1), 0);
    assertLeaf(result);
    expect(result.location).toEqual({
      head: 96, // headsBase(64) + 1 * 32
      base: 32, // arrayBase (static elements: base = arrayBase)
      node: UINT256,
    });
  });

  test("index 0", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(32), word(3), word(10), word(20), word(30));

    const result = locate(tree, callData, path(0, 0), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 64, base: 32, node: UINT256 });
  });

  test("out of bounds index", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(32), word(1), word(42));

    const result = locate(tree, callData, path(0, 1), 0);
    expect(result).toEqual({ ok: false, code: "ARRAY_INDEX_OUT_OF_BOUNDS" });
  });
});

///////////////////////////////////////////////////////////////////////////
// Dynamic Array (Dynamic Elements)
///////////////////////////////////////////////////////////////////////////

describe("locate - dynamic array with dynamic elements", () => {
  test("base anchors to heads section", () => {
    // Element offsets are relative to headsBase, not arrayBase.
    const arrNode = dynamicArrayNode(BYTES);
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32), // offset to array data
      word(2), // length = 2
      word(64), // offset to elem 0 data (relative to headsBase=64)
      word(128), // offset to elem 1 data (relative to headsBase=64)
    );

    const result = locate(tree, callData, path(0, 1), 0);
    assertLeaf(result);
    expect(result.location).toEqual({
      head: 96, // headsBase(64) + 1 * 32
      base: 64, // base = headsBase = arrayBase + 32, NOT arrayBase
      node: BYTES,
    });
  });

  test("index 0 with dynamic elements", () => {
    const arrNode = dynamicArrayNode(BYTES);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(32), word(1), word(32));

    const result = locate(tree, callData, path(0, 0), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 64, base: 64, node: BYTES });
  });
});

///////////////////////////////////////////////////////////////////////////
// Static Array (Dynamic Elements)
///////////////////////////////////////////////////////////////////////////

describe("locate - static array with dynamic elements", () => {
  test("dereferences offset pointer to get array base", () => {
    // Element offsets are relative to arrayBase (32).
    const arrNode = staticArrayNode(BYTES, 2);
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32), // offset to array data
      word(64), // offset to elem 0 (relative to arrayBase=32)
      word(128), // offset to elem 1 (relative to arrayBase=32)
    );

    const result = locate(tree, callData, path(0, 1), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 64, base: 32, node: BYTES });
  });

  test("index 0", () => {
    const arrNode = staticArrayNode(BYTES, 2);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(32), word(64), word(128));

    const result = locate(tree, callData, path(0, 0), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 32, base: 32, node: BYTES });
  });
});

///////////////////////////////////////////////////////////////////////////
// Quantifier Detection
///////////////////////////////////////////////////////////////////////////

describe("locate - quantifier", () => {
  test("ALL_OR_EMPTY on dynamic array returns quantifier result", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(32), word(3), word(10), word(20), word(30));

    const result = locate(tree, callData, path(0, Quantifier.ALL_OR_EMPTY), 0);
    assertQuantifier(result);
    const qr = result.quantifier;
    expect(qr.quantifier).toBe(Quantifier.ALL_OR_EMPTY);
    expect(qr.remainingPath.length).toBe(0);

    const shapeResult = arrayShape(callData, qr.location);
    assertOk(shapeResult);
    expect(shapeResult.shape.length).toBe(3);
    expect(shapeResult.shape.elementIsDynamic).toBe(false);
    expect(shapeResult.shape.dataOffset).toBe(64); // arrayBase(32) + 32
    expect(shapeResult.shape.elementNode).toEqual(UINT256);
  });

  test("ALL on static array", () => {
    const arrNode = staticArrayNode(UINT256, 2);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(10), word(20));

    const result = locate(tree, callData, path(0, Quantifier.ALL), 0);
    assertQuantifier(result);
    const qr = result.quantifier;
    expect(qr.quantifier).toBe(Quantifier.ALL);

    const shapeResult = arrayShape(callData, qr.location);
    assertOk(shapeResult);
    expect(shapeResult.shape.length).toBe(2);
    expect(shapeResult.shape.dataOffset).toBe(0);
    expect(shapeResult.shape.elementNode).toEqual(UINT256);
  });

  test("ANY on dynamic array with remaining path", () => {
    const tupleElem = staticTupleNode([UINT256, ADDRESS]);
    const arrNode = dynamicArrayNode(tupleElem);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(32), word(2));

    const result = locate(tree, callData, path(0, Quantifier.ANY, 1), 0);
    assertQuantifier(result);
    const qr = result.quantifier;
    expect(qr.quantifier).toBe(Quantifier.ANY);
    expect(qr.remainingPath).toEqual(path(1));

    const shapeResult = arrayShape(callData, qr.location);
    assertOk(shapeResult);
    expect(shapeResult.shape.length).toBe(2);
  });

  test("quantifier on non-array throws integrity error from arrayShape", () => {
    const tree: DescNode[] = [UINT256];
    const callData = word(42);
    const result = locate(tree, callData, path(0, Quantifier.ALL), 0);
    assertQuantifier(result);
    expect(() => arrayShape(callData, result.quantifier.location)).toThrow("non-array node");
  });

  test("quantifier on static array with dynamic elements dereferences pointer", () => {
    const arrNode = staticArrayNode(BYTES, 3);
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32), // offset to array data
      word(96), // offset to elem 0
      word(128), // offset to elem 1
      word(160), // offset to elem 2
    );

    const result = locate(tree, callData, path(0, Quantifier.ALL), 0);
    assertQuantifier(result);

    const shapeResult = arrayShape(callData, result.quantifier.location);
    assertOk(shapeResult);
    expect(shapeResult.shape.length).toBe(3);
    expect(shapeResult.shape.headsBase).toBe(32); // arrayBase = base(0) + readPointer(0) = 32
  });
});

///////////////////////////////////////////////////////////////////////////
// Bounds Violations
///////////////////////////////////////////////////////////////////////////

describe("locate - bounds violations", () => {
  test("truncated callData for dynamic array offset", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const tree: DescNode[] = [arrNode];
    const result = locate(tree, new Uint8Array(16), path(0, 0), 0);
    expect(result).toEqual({ ok: false, code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("truncated callData for dynamic array length", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const tree: DescNode[] = [arrNode];
    // Offset says data is at 32, but callData is only 48 bytes.
    const callData = concat(word(32), new Uint8Array(16));
    const result = locate(tree, callData, path(0, 0), 0);
    expect(result).toEqual({ ok: false, code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("offset overflow (pointer value too large)", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(9999), word(0));
    const result = locate(tree, callData, path(0, 0), 0);
    expect(result).toEqual({ ok: false, code: "CALLDATA_OUT_OF_BOUNDS" });
  });

  test("dynamic tuple with truncated callData", () => {
    const tupleNode = dynamicTupleNode([UINT256]);
    const tree: DescNode[] = [tupleNode];
    const result = locate(tree, new Uint8Array(16), path(0, 0), 0);
    expect(result).toEqual({ ok: false, code: "CALLDATA_OUT_OF_BOUNDS" });
  });
});

///////////////////////////////////////////////////////////////////////////
// Nested Navigation
///////////////////////////////////////////////////////////////////////////

describe("locate - nested structures", () => {
  test("tuple inside dynamic array", () => {
    // (uint256, uint256)[] — static tuple elements inline in array.
    const tupleElem = staticTupleNode([UINT256, UINT256]);
    const arrNode = dynamicArrayNode(tupleElem);
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32), // offset to array
      word(2), // length = 2
      word(0xaa), // tuple[0].field0
      word(0xbb), // tuple[0].field1
      word(0xcc), // tuple[1].field0
      word(0xdd), // tuple[1].field1
    );

    // path: param 0, array index 1, tuple field 1
    const result = locate(tree, callData, path(0, 1, 1), 0);
    assertLeaf(result);
    // element[1] starts at 128, skip field0 (32 bytes) → 160.
    expect(result.location).toEqual({ head: 160, base: 32, node: UINT256 });
  });

  test("dynamic array inside tuple", () => {
    // func((uint256, uint256[]))
    const dynArrayField = dynamicArrayNode(UINT256);
    const tupleNode = dynamicTupleNode([UINT256, dynArrayField]);
    const tree: DescNode[] = [tupleNode];

    const callData = concat(
      word(32), // tuple offset pointer
      word(0xaa), // tuple.field0 = 0xaa
      word(64), // tuple.field1 offset (relative to tupleBase=32) → points to 96.
      word(2), // array length = 2
      word(111), // array[0]
      word(222), // array[1]
    );

    // path: param 0, field 1, index 1
    const result = locate(tree, callData, path(0, 1, 1), 0);
    assertLeaf(result);
    // tupleBase=32, field1 head=64, arrayBase=96, headsBase=128, elem1=160.
    expect(result.location).toEqual({ head: 160, base: 96, node: UINT256 });
  });

  test("deeply nested: array in tuple in array", () => {
    const innerArr = staticArrayNode(UINT256, 3);
    const tupleNode = staticTupleNode([innerArr]);
    const tree: DescNode[] = [tupleNode];
    const callData = concat(word(10), word(20), word(30));

    // path: param 0, field 0, index 2
    const result = locate(tree, callData, path(0, 0, 2), 0);
    assertLeaf(result);
    expect(result.location.head).toBe(64); // 0 + 2*32
    expect(result.location.base).toBe(0);
  });

  test("with base offset (selector present)", () => {
    const tree: DescNode[] = [UINT256];
    const selector = new Uint8Array([0x12, 0x34, 0x56, 0x78]);
    const callData = concat(selector, word(42));

    const result = locate(tree, callData, path(0), 4);
    assertLeaf(result);
    expect(result.location.head).toBe(4);
    expect(result.location.base).toBe(4);
  });
});

///////////////////////////////////////////////////////////////////////////
// Composable API: locate
///////////////////////////////////////////////////////////////////////////

describe("locate", () => {
  test("resolves leaf location for single param", () => {
    const tree: DescNode[] = [UINT256];
    const result = locate(tree, word(42), path(0), 0);
    assertLeaf(result);
    expect(result.location).toEqual({ head: 0, base: 0, node: UINT256 });
  });

  test("returns quantifier result when path hits quantifier step", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(32), word(3), word(10), word(20), word(30));

    const result = locate(tree, callData, path(0, Quantifier.ALL_OR_EMPTY), 0);
    assertQuantifier(result);
    expect(result.quantifier.quantifier).toBe(Quantifier.ALL_OR_EMPTY);
    // The location points to the array itself, not the elements.
    expect(result.quantifier.location.node).toEqual(arrNode);
    expect(result.quantifier.remainingPath.length).toBe(0);
  });

  test("quantifier with suffix path captures remaining steps", () => {
    const tupleElem = staticTupleNode([UINT256, ADDRESS]);
    const arrNode = dynamicArrayNode(tupleElem);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(32), word(2));

    const result = locate(tree, callData, path(0, Quantifier.ANY, 1), 0);
    assertQuantifier(result);
    expect(result.quantifier.remainingPath).toEqual(path(1));
  });

  test("throws for out-of-bounds param index", () => {
    const tree: DescNode[] = [UINT256];
    expect(() => locate(tree, word(42), path(1), 0)).toThrow("Param index 1 out of range");
  });

  test("throws for empty path", () => {
    const tree: DescNode[] = [UINT256];
    expect(() => locate(tree, word(42), new Uint8Array(0), 0)).toThrow("Path is empty");
  });
});

///////////////////////////////////////////////////////////////////////////
// Composable API: Arrayshape
///////////////////////////////////////////////////////////////////////////

describe("arrayShape", () => {
  test("dynamic array with static elements", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const callData = concat(word(32), word(3), word(10), word(20), word(30));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const result = arrayShape(callData, loc);
    assertOk(result);
    expect(result.shape.length).toBe(3);
    expect(result.shape.elementIsDynamic).toBe(false);
    expect(result.shape.elementStaticSize).toBe(32);
    expect(result.shape.dataOffset).toBe(64); // arrayBase(32) + 32
    expect(result.shape.compositeBase).toBe(32); // arrayBase
  });

  test("dynamic array with dynamic elements", () => {
    const arrNode = dynamicArrayNode(BYTES);
    const callData = concat(word(32), word(2), word(64), word(128));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const result = arrayShape(callData, loc);
    assertOk(result);
    expect(result.shape.length).toBe(2);
    expect(result.shape.elementIsDynamic).toBe(true);
    expect(result.shape.headsBase).toBe(64); // arrayBase(32) + 32
    expect(result.shape.compositeBase).toBe(64); // headsBase for dynamic
  });

  test("static array with static elements", () => {
    const arrNode = staticArrayNode(UINT256, 3);
    const callData = concat(word(100), word(200), word(300));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const result = arrayShape(callData, loc);
    assertOk(result);
    expect(result.shape.length).toBe(3);
    expect(result.shape.elementIsDynamic).toBe(false);
    expect(result.shape.dataOffset).toBe(0);
    expect(result.shape.compositeBase).toBe(0);
  });

  test("static array with dynamic elements", () => {
    const arrNode = staticArrayNode(BYTES, 2);
    const callData = concat(word(32), word(64), word(128));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const result = arrayShape(callData, loc);
    assertOk(result);
    expect(result.shape.length).toBe(2);
    expect(result.shape.elementIsDynamic).toBe(true);
    expect(result.shape.headsBase).toBe(32);
    expect(result.shape.compositeBase).toBe(32);
  });

  test("throws integrity error for non-array node", () => {
    const loc: Location = { head: 0, base: 0, node: UINT256 };
    expect(() => arrayShape(word(42), loc)).toThrow("non-array node");
  });
});

///////////////////////////////////////////////////////////////////////////
// Composable API: arrayElementAt
///////////////////////////////////////////////////////////////////////////

describe("arrayElementAt", () => {
  test("static elements: computes correct head from dataOffset", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const callData = concat(word(32), word(3), word(10), word(20), word(30));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const shapeResult = arrayShape(callData, loc);
    assertOk(shapeResult);

    const elem1 = arrayElementAt(shapeResult.shape, 1, callData);
    assertOk(elem1);
    expect(elem1.location.head).toBe(96); // dataOffset(64) + 1 * 32
    expect(elem1.location.base).toBe(32); // compositeBase = arrayBase
  });

  test("dynamic elements: computes correct head and base from headsBase", () => {
    const arrNode = dynamicArrayNode(BYTES);
    const callData = concat(word(32), word(2), word(64), word(128));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const shapeResult = arrayShape(callData, loc);
    assertOk(shapeResult);

    const elem1 = arrayElementAt(shapeResult.shape, 1, callData);
    assertOk(elem1);
    expect(elem1.location.head).toBe(96); // headsBase(64) + 1 * 32
    expect(elem1.location.base).toBe(64); // headsBase
  });

  test("out of bounds index returns error", () => {
    const arrNode = dynamicArrayNode(UINT256);
    const callData = concat(word(32), word(2), word(10), word(20));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const shapeResult = arrayShape(callData, loc);
    assertOk(shapeResult);

    const result = arrayElementAt(shapeResult.shape, 2, callData);
    expect(result.ok).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
// Composable API: loadScalar
///////////////////////////////////////////////////////////////////////////

describe("loadScalar", () => {
  test("loads 32-byte value from location", () => {
    const callData = concat(word(42), word(99));
    const loc: Location = { head: 32, base: 0, node: UINT256 };
    const result = loadScalar(callData, loc);
    assertOk(result);
    expect(result.value[31]).toBe(99);
  });

  test("returns error for truncated callData", () => {
    const callData = new Uint8Array(16);
    const loc: Location = { head: 0, base: 0, node: UINT256 };
    const result = loadScalar(callData, loc);
    expect(result.ok).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
// Composable API: loadSlice
///////////////////////////////////////////////////////////////////////////

describe("loadSlice", () => {
  test("reads data offset and length of dynamic bytes", () => {
    // Layout: [offset_ptr(32)] at head=0 pointing to 32, then [length(32)] at 32.
    const callData = concat(word(32), word(10));
    const loc: Location = { head: 0, base: 0, node: BYTES };
    const result = loadSlice(callData, loc);
    assertOk(result);
    expect(result.length).toBe(10);
    expect(result.dataOffset).toBe(64); // base(0) + ptr(32) + length_word(32)
  });

  test("returns error for truncated callData", () => {
    const callData = new Uint8Array(16);
    const loc: Location = { head: 0, base: 0, node: BYTES };
    const result = loadSlice(callData, loc);
    expect(result.ok).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
// Composable API: descendPath
///////////////////////////////////////////////////////////////////////////

describe("descendPath", () => {
  test("descends through tuple fields from a given location", () => {
    const tupleNode = staticTupleNode([UINT256, ADDRESS]);
    const callData = concat(word(10), word(20));

    const loc: Location = { head: 0, base: 0, node: tupleNode };
    const result = descendPath(callData, loc, path(1));
    assertOk(result);
    expect(result.location.head).toBe(32);
    expect(result.location.node).toEqual(ADDRESS);
  });

  test("descends through array and tuple", () => {
    const tupleElem = staticTupleNode([UINT256, UINT256]);
    const callData = concat(word(32), word(2), word(0xaa), word(0xbb), word(0xcc), word(0xdd));

    // Element 1 of (uint256, uint256)[] — static tuple at index 1.
    const elemLoc: Location = { head: 128, base: 32, node: tupleElem };

    const result = descendPath(callData, elemLoc, path(1));
    assertOk(result);
    // Static tuple: cursor = 128, skip field0(32) = 160.
    expect(result.location.head).toBe(160);
    expect(result.location.base).toBe(32);
  });

  test("empty path returns same location", () => {
    const loc: Location = { head: 42, base: 0, node: UINT256 };
    const result = descendPath(word(0), loc, new Uint8Array(0));
    assertOk(result);
    expect(result.location).toEqual(loc);
  });

  test("throws integrity error for non-composite descent", () => {
    const loc: Location = { head: 0, base: 0, node: UINT256 };
    expect(() => descendPath(word(42), loc, path(0))).toThrow("elementary type");
  });
});

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

import type { Location } from "../src/reader";
import type { DescNode } from "../src/types";

///////////////////////////////////////////////////////////////////////////
//                               Helpers
///////////////////////////////////////////////////////////////////////////

/** Assert that a result is ok and narrow the type. */
function assertOk<T extends { ok: boolean }>(result: T): asserts result is Extract<T, { ok: true }> {
  if (!("ok" in result) || !result.ok) {
    throw new Error(`Expected ok result, got: ${JSON.stringify(result)}`);
  }
}

/** Encode a uint256 value as 32 bytes (big-endian). */
function word(value: number): Uint8Array {
  const buf = new Uint8Array(32);
  // Write value into the last 4 bytes.
  buf[28] = (value >>> 24) & 0xff;
  buf[29] = (value >>> 16) & 0xff;
  buf[30] = (value >>> 8) & 0xff;
  buf[31] = value & 0xff;
  return buf;
}

/** Concatenate multiple Uint8Arrays. */
function concat(...arrays: Uint8Array[]): Uint8Array {
  const total = arrays.reduce((sum, a) => sum + a.length, 0);
  const result = new Uint8Array(total);
  let offset = 0;
  for (const a of arrays) {
    result.set(a, offset);
    offset += a.length;
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
//                           Node constructors
///////////////////////////////////////////////////////////////////////////

function uint256Node(): DescNode {
  return {
    type: "elementary",
    typeCode: 0x1f,
    isDynamic: false,
    staticSize: 32,
  };
}

function addressNode(): DescNode {
  return {
    type: "elementary",
    typeCode: 0x40,
    isDynamic: false,
    staticSize: 32,
  };
}

function bytesNode(): DescNode {
  return {
    type: "elementary",
    typeCode: 0x70,
    isDynamic: true,
    staticSize: 0,
  };
}

function staticTupleNode(fields: DescNode[]): DescNode {
  const staticSize = fields.reduce((s, f) => s + (f.isDynamic ? 32 : f.staticSize), 0);
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
//                       LOAD32 AND READPOINTER
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

  test("returns CALLDATA_TOO_SHORT when offset exceeds bounds", () => {
    const callData = word(1);
    const result = load32(callData, 1);
    expect(result).toEqual({ code: "CALLDATA_TOO_SHORT" });
  });

  test("returns CALLDATA_TOO_SHORT for empty callData", () => {
    const result = load32(new Uint8Array(0), 0);
    expect(result).toEqual({ code: "CALLDATA_TOO_SHORT" });
  });

  test("returns CALLDATA_TOO_SHORT for negative offset", () => {
    const result = load32(word(1), -1);
    expect(result).toEqual({ code: "CALLDATA_TOO_SHORT" });
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
    buf[0] = 1; // High byte nonzero.
    const result = readPointer(buf, 0);
    expect(result).toEqual({ code: "OFFSET_OUT_OF_BOUNDS" });
  });

  test("rejects value with byte 27 nonzero", () => {
    const buf = new Uint8Array(32);
    buf[27] = 1;
    const result = readPointer(buf, 0);
    expect(result).toEqual({ code: "OFFSET_OUT_OF_BOUNDS" });
  });

  test("propagates CALLDATA_TOO_SHORT", () => {
    const result = readPointer(new Uint8Array(16), 0);
    expect(result).toEqual({ code: "CALLDATA_TOO_SHORT" });
  });
});

///////////////////////////////////////////////////////////////////////////
//                        TOP-LEVEL PARAM ACCESS
///////////////////////////////////////////////////////////////////////////

describe("locate - top-level param access", () => {
  test("single uint256 at base 0", () => {
    // ABI layout: [value(32)]
    const tree: DescNode[] = [uint256Node()];
    const callData = word(42);
    const result = locate(tree, callData, path(0), 0);
    expect(result.ok).toBe(true);
    expect("location" in result).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({ head: 0, base: 0, node: tree[0] });
    }
  });

  test("second param of (address, uint256) at base 4", () => {
    // ABI layout: selector(4) + address(32) + uint256(32)
    const tree: DescNode[] = [addressNode(), uint256Node()];
    const selector = new Uint8Array(4);
    const callData = concat(selector, word(0), word(99));
    const result = locate(tree, callData, path(1), 4);
    expect(result.ok).toBe(true);
    expect("location" in result).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({ head: 36, base: 4, node: tree[1] }); // 4 + 32
    }
  });

  test("first param of (address, uint256) at base 4", () => {
    const tree: DescNode[] = [addressNode(), uint256Node()];
    const selector = new Uint8Array(4);
    const callData = concat(selector, word(0), word(99));
    const result = locate(tree, callData, path(0), 4);
    expect(result.ok).toBe(true);
    expect("location" in result).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({ head: 4, base: 4, node: tree[0] });
    }
  });

  test("param index out of bounds returns violation", () => {
    const tree: DescNode[] = [uint256Node()];
    const callData = word(42);
    const result = locate(tree, callData, path(1), 0);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("OFFSET_OUT_OF_BOUNDS");
    }
  });

  test("empty path returns violation", () => {
    const tree: DescNode[] = [uint256Node()];
    const result = locate(tree, word(42), new Uint8Array(0), 0);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("CALLDATA_TOO_SHORT");
    }
  });
});

///////////////////////////////////////////////////////////////////////////
//                         STATIC TUPLE DESCENT
///////////////////////////////////////////////////////////////////////////

describe("locate - static tuple descent", () => {
  test("locate second field of static tuple", () => {
    // Descriptor: tuple(uint256, uint256)
    // ABI layout at base 0: [field0(32) + field1(32)]
    const tupleNode = staticTupleNode([uint256Node(), uint256Node()]);
    const tree: DescNode[] = [tupleNode];
    const callData = concat(word(10), word(20));

    // path: param 0, field 1
    const result = locate(tree, callData, path(0, 1), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({
        head: 32, // skipped field0 (32 bytes)
        base: 0, // static tuple: base unchanged
        node: uint256Node(),
      });
    }
  });

  test("locate first field of static tuple", () => {
    const tupleNode = staticTupleNode([addressNode(), uint256Node()]);
    const tree: DescNode[] = [tupleNode];
    const callData = concat(word(0), word(42));

    const result = locate(tree, callData, path(0, 0), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({ head: 0, base: 0, node: addressNode() });
    }
  });
});

///////////////////////////////////////////////////////////////////////////
//                        DYNAMIC TUPLE DESCENT
///////////////////////////////////////////////////////////////////////////

describe("locate - dynamic tuple descent", () => {
  test("locate static field in a dynamic tuple", () => {
    // Descriptor: tuple(uint256, bytes) — dynamic because of bytes field.
    // ABI layout at base 0:
    //   [offset_ptr(32)] → points to tuple data at offset 32
    //   Tuple data at 32: [field0_value(32) + field1_offset(32) + ...]
    const tupleNode = dynamicTupleNode([uint256Node(), bytesNode()]);
    const tree: DescNode[] = [tupleNode];

    const callData = concat(
      word(32), // offset to tuple data (param head)
      word(0xaa), // tuple field 0: uint256 = 0xaa
      word(64), // tuple field 1: offset to bytes data (relative to tuple base)
      // ... bytes data would follow
    );

    // path: param 0, field 0
    const result = locate(tree, callData, path(0, 0), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({
        head: 32, // tupleBase = 0 + 32 = 32, cursor starts at 32, no fields to skip
        base: 32, // tupleBase
        node: uint256Node(),
      });
    }
  });

  test("locate second field in a dynamic tuple", () => {
    const tupleNode = dynamicTupleNode([uint256Node(), bytesNode()]);
    const tree: DescNode[] = [tupleNode];

    const callData = concat(
      word(32), // offset to tuple data
      word(0xaa), // field 0: uint256
      word(64), // field 1: offset to bytes (relative to tupleBase=32)
    );

    // path: param 0, field 1
    const result = locate(tree, callData, path(0, 1), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({
        head: 64, // tupleBase(32) + skip field0(32) = 64
        base: 32,
        node: bytesNode(),
      });
    }
  });
});

///////////////////////////////////////////////////////////////////////////
//                    STATIC ARRAY (STATIC ELEMENTS)
///////////////////////////////////////////////////////////////////////////

describe("locate - static array with static elements", () => {
  test("index into uint256[3]", () => {
    // Descriptor: uint256[3]
    // ABI layout at base 0: [elem0(32) + elem1(32) + elem2(32)]
    const arrNode = staticArrayNode(uint256Node(), 3);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(100), word(200), word(300));

    // path: param 0, index 2
    const result = locate(tree, callData, path(0, 2), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({ head: 64, base: 0, node: uint256Node() }); // 0 + 2 * 32
    }
  });

  test("index 0 into uint256[2]", () => {
    const arrNode = staticArrayNode(uint256Node(), 2);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(11), word(22));

    const result = locate(tree, callData, path(0, 0), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({ head: 0, base: 0, node: uint256Node() });
    }
  });

  test("out of bounds index returns violation", () => {
    const arrNode = staticArrayNode(uint256Node(), 2);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(11), word(22));

    const result = locate(tree, callData, path(0, 2), 0);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("OFFSET_OUT_OF_BOUNDS");
    }
  });
});

///////////////////////////////////////////////////////////////////////////
//                   DYNAMIC ARRAY (STATIC ELEMENTS)
///////////////////////////////////////////////////////////////////////////

describe("locate - dynamic array with static elements", () => {
  test("index into uint256[]", () => {
    // ABI layout at base 0:
    //   [offset_ptr(32)] → 32
    //   At 32: [length(32) + elem0(32) + elem1(32)]
    const arrNode = dynamicArrayNode(uint256Node());
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32), // offset to array data
      word(2), // length = 2
      word(111), // elem 0
      word(222), // elem 1
    );

    // path: param 0, index 1
    const result = locate(tree, callData, path(0, 1), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({
        head: 96, // headsBase(64) + 1 * 32
        base: 32, // arrayBase (static elements: base = arrayBase)
        node: uint256Node(),
      });
    }
  });

  test("index 0", () => {
    const arrNode = dynamicArrayNode(uint256Node());
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32),
      word(3), // length = 3
      word(10),
      word(20),
      word(30),
    );

    const result = locate(tree, callData, path(0, 0), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({
        head: 64, // headsBase = 32 + 32 = 64
        base: 32,
        node: uint256Node(),
      });
    }
  });

  test("out of bounds index", () => {
    const arrNode = dynamicArrayNode(uint256Node());
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32),
      word(1), // length = 1
      word(42),
    );

    const result = locate(tree, callData, path(0, 1), 0);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("OFFSET_OUT_OF_BOUNDS");
    }
  });
});

///////////////////////////////////////////////////////////////////////////
//                  DYNAMIC ARRAY (DYNAMIC ELEMENTS)
///////////////////////////////////////////////////////////////////////////

describe("locate - dynamic array with dynamic elements", () => {
  test("base anchors to heads section", () => {
    // Descriptor: bytes[]
    // ABI layout at base 0:
    //   [offset_ptr(32)] → 32
    //   At 32: [length(32) + offset_elem0(32) + offset_elem1(32) + ...]
    //   Element offsets are relative to headsBase (64).
    const arrNode = dynamicArrayNode(bytesNode());
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32), // offset to array data
      word(2), // length = 2
      word(64), // offset to elem 0 data (relative to headsBase=64)
      word(128), // offset to elem 1 data (relative to headsBase=64)
    );

    // path: param 0, index 1
    const result = locate(tree, callData, path(0, 1), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({
        head: 96, // headsBase(64) + 1 * 32
        base: 64, // KEY: base = headsBase = arrayBase + 32, NOT arrayBase
        node: bytesNode(),
      });
    }
  });

  test("index 0 with dynamic elements", () => {
    const arrNode = dynamicArrayNode(bytesNode());
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32),
      word(1), // length = 1
      word(32), // offset to elem 0 data (relative to headsBase)
    );

    const result = locate(tree, callData, path(0, 0), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({
        head: 64, // headsBase(64) + 0 * 32
        base: 64, // headsBase
        node: bytesNode(),
      });
    }
  });
});

///////////////////////////////////////////////////////////////////////////
//                   STATIC ARRAY (DYNAMIC ELEMENTS)
///////////////////////////////////////////////////////////////////////////

describe("locate - static array with dynamic elements", () => {
  test("dereferences offset pointer to get array base", () => {
    // Descriptor: bytes[2]
    // ABI layout at base 0:
    //   [offset_ptr(32)] → 32
    //   At 32: [offset_elem0(32) + offset_elem1(32) + elem0_data... + elem1_data...]
    //   Element offsets are relative to arrayBase (32).
    const arrNode = staticArrayNode(bytesNode(), 2);
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32), // offset to array data
      word(64), // offset to elem 0 (relative to arrayBase=32)
      word(128), // offset to elem 1 (relative to arrayBase=32)
    );

    // path: param 0, index 1
    const result = locate(tree, callData, path(0, 1), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({
        head: 64, // arrayBase(32) + 1 * 32
        base: 32, // arrayBase
        node: bytesNode(),
      });
    }
  });

  test("index 0", () => {
    const arrNode = staticArrayNode(bytesNode(), 2);
    const tree: DescNode[] = [arrNode];

    const callData = concat(word(32), word(64), word(128));

    const result = locate(tree, callData, path(0, 0), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc).toEqual({
        head: 32, // arrayBase(32) + 0 * 32
        base: 32,
        node: bytesNode(),
      });
    }
  });
});

///////////////////////////////////////////////////////////////////////////
//                        QUANTIFIER DETECTION
///////////////////////////////////////////////////////////////////////////

describe("locate - quantifier", () => {
  test("ALL_OR_EMPTY on dynamic array returns quantifier result", () => {
    const arrNode = dynamicArrayNode(uint256Node());
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32),
      word(3), // length = 3
      word(10),
      word(20),
      word(30),
    );

    const result = locate(tree, callData, path(0, Quantifier.ALL_OR_EMPTY), 0);
    expect(result.ok).toBe(true);
    expect("quantifier" in result).toBe(true);
    if (result.ok && result.type === "quantifier") {
      const qr = result.quantifier;
      expect(qr.quantifier).toBe(Quantifier.ALL_OR_EMPTY);
      expect(qr.remainingPath.length).toBe(0);

      const shapeResult = arrayShape(callData, qr.location);
      expect(shapeResult.ok).toBe(true);
      assertOk(shapeResult);
      const shape = shapeResult.shape;
      expect(shape.length).toBe(3);
      // Static elements: headsBase is 0, dataOffset holds the elements start.
      expect(shape.elementIsDynamic).toBe(false);
      expect(shape.dataOffset).toBe(64); // arrayBase(32) + 32
      expect(shape.elementNode).toEqual(uint256Node());
    }
  });

  test("ALL on static array", () => {
    const arrNode = staticArrayNode(uint256Node(), 2);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(10), word(20));

    const result = locate(tree, callData, path(0, Quantifier.ALL), 0);
    expect(result.ok).toBe(true);
    expect("quantifier" in result).toBe(true);
    if (result.ok && result.type === "quantifier") {
      const qr = result.quantifier;
      expect(qr.quantifier).toBe(Quantifier.ALL);

      const shapeResult = arrayShape(callData, qr.location);
      expect(shapeResult.ok).toBe(true);
      assertOk(shapeResult);
      const shape = shapeResult.shape;
      expect(shape.length).toBe(2);
      expect(shape.dataOffset).toBe(0); // static elements: dataOffset = head
      expect(shape.elementNode).toEqual(uint256Node());
    }
  });

  test("ANY on dynamic array with remaining path", () => {
    // tuple[] — quantifier then descend into tuple field.
    const tupleElem = staticTupleNode([uint256Node(), addressNode()]);
    const arrNode = dynamicArrayNode(tupleElem);
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32),
      word(2), // length
      // ... tuple data follows
    );

    // path: param 0, ANY, field 1
    const result = locate(tree, callData, path(0, Quantifier.ANY, 1), 0);
    expect(result.ok).toBe(true);
    expect("quantifier" in result).toBe(true);
    if (result.ok && result.type === "quantifier") {
      const qr = result.quantifier;
      expect(qr.quantifier).toBe(Quantifier.ANY);
      expect(qr.remainingPath).toEqual(path(1));

      const shapeResult = arrayShape(callData, qr.location);
      expect(shapeResult.ok).toBe(true);
      assertOk(shapeResult);
      const shape = shapeResult.shape;
      expect(shape.length).toBe(2);
    }
  });

  test("quantifier on non-array returns violation", () => {
    const tree: DescNode[] = [uint256Node()];
    const callData = word(42);
    const result = locate(tree, callData, path(0, Quantifier.ALL), 0);
    // locate stops at the quantifier step, returning the array node location.
    // The violation comes from arrayShape seeing a non-array node.
    expect(result.ok).toBe(true);
    expect("quantifier" in result).toBe(true);
    if (result.ok && result.type === "quantifier") {
      const qr = result.quantifier;
      const shapeResult = arrayShape(callData, qr.location);
      expect(shapeResult.ok).toBe(false);
    }
  });

  test("quantifier on static array with dynamic elements dereferences pointer", () => {
    const arrNode = staticArrayNode(bytesNode(), 3);
    const tree: DescNode[] = [arrNode];

    const callData = concat(
      word(32), // offset to array data
      word(96), // offset to elem 0
      word(128), // offset to elem 1
      word(160), // offset to elem 2
    );

    const result = locate(tree, callData, path(0, Quantifier.ALL), 0);
    expect(result.ok).toBe(true);
    expect("quantifier" in result).toBe(true);
    if (result.ok && result.type === "quantifier") {
      const qr = result.quantifier;

      const shapeResult = arrayShape(callData, qr.location);
      expect(shapeResult.ok).toBe(true);
      assertOk(shapeResult);
      const shape = shapeResult.shape;
      expect(shape.length).toBe(3);
      expect(shape.headsBase).toBe(32); // arrayBase = base(0) + readPointer(0) = 32
    }
  });
});

///////////////////////////////////////////////////////////////////////////
//                          BOUNDS VIOLATIONS
///////////////////////////////////////////////////////////////////////////

describe("locate - bounds violations", () => {
  test("truncated callData for dynamic array offset", () => {
    const arrNode = dynamicArrayNode(uint256Node());
    const tree: DescNode[] = [arrNode];

    // CallData too short to read the offset pointer.
    const callData = new Uint8Array(16);
    const result = locate(tree, callData, path(0, 0), 0);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("CALLDATA_TOO_SHORT");
    }
  });

  test("truncated callData for dynamic array length", () => {
    const arrNode = dynamicArrayNode(uint256Node());
    const tree: DescNode[] = [arrNode];

    // Offset says data is at 32, but callData is only 48 bytes (not enough for length word).
    const callData = concat(word(32), new Uint8Array(16));
    const result = locate(tree, callData, path(0, 0), 0);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("CALLDATA_TOO_SHORT");
    }
  });

  test("offset overflow (pointer value too large)", () => {
    const arrNode = dynamicArrayNode(uint256Node());
    const tree: DescNode[] = [arrNode];

    // Offset points way beyond callData.
    const callData = concat(word(9999), word(0));
    const result = locate(tree, callData, path(0, 0), 0);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("CALLDATA_TOO_SHORT");
    }
  });

  test("dynamic tuple with truncated callData", () => {
    const tupleNode = dynamicTupleNode([uint256Node()]);
    const tree: DescNode[] = [tupleNode];

    // CallData is only 16 bytes — too short to read offset pointer.
    const callData = new Uint8Array(16);
    const result = locate(tree, callData, path(0, 0), 0);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("CALLDATA_TOO_SHORT");
    }
  });
});

///////////////////////////////////////////////////////////////////////////
//                          NESTED NAVIGATION
///////////////////////////////////////////////////////////////////////////

describe("locate - nested structures", () => {
  test("tuple inside dynamic array", () => {
    // Descriptor: (uint256, uint256)[]
    // ABI layout at base 0:
    //   [offset_ptr(32)] → 32
    //   At 32: [length(32) + tuple0_field0(32) + tuple0_field1(32) + tuple1_field0(32) + tuple1_field1(32)]
    // Each tuple element is static (2 words = 64 bytes), inline in the array.
    const tupleElem = staticTupleNode([uint256Node(), uint256Node()]);
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
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const leaf = result.location;
      // Array element[1]: headsBase = 64, head = 64 + 1*64 = 128, base = 32.
      // Static tuple descent: tupleBase = 32, cursor = 128. Skip field0 (32 bytes) → 160.
      expect(leaf.head).toBe(160);
      expect(leaf.base).toBe(32);
      expect(leaf.node).toEqual(uint256Node());
    }
  });

  test("dynamic array inside tuple", () => {
    // Descriptor: (uint256, uint256[]).
    // Dynamic top-level params have an offset pointer at their head position.
    //
    // ABI layout for func(uint256, uint256[]):
    //   base=0: [param0_value(32) + param1_offset(32)]
    //   At param1_offset: [length(32) + elem0(32) + elem1(32)]
    //
    // But this is a tuple param: func((uint256, uint256[]))
    // ABI layout:
    //   base=0: [tuple_offset(32)]
    //   At tuple_offset(32): [field0_value(32) + field1_offset(32)]
    //   At tuple_offset + field1_offset: [length(32) + elem0(32) + elem1(32)]
    const dynArrayField = dynamicArrayNode(uint256Node());
    const tupleNode = dynamicTupleNode([uint256Node(), dynArrayField]);
    const tree: DescNode[] = [tupleNode];

    const callData = concat(
      word(32), // tuple offset pointer
      word(0xaa), // tuple.field0 = 0xaa
      word(64), // tuple.field1 offset (relative to tupleBase=32) → points to 32+64=96
      word(2), // array length = 2
      word(111), // array[0]
      word(222), // array[1]
    );

    // path: param 0, field 1, index 1
    const result = locate(tree, callData, path(0, 1, 1), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const leaf = result.location;
      // Step 1 (field 1 of tuple):
      //   Dynamic tuple: tupleBase = 0 + readPointer(0) = 0 + 32 = 32. cursor = 32.
      //   Skip field0 (static, 32 bytes): cursor = 64.
      //   Result: head=64, base=32, node=dynamicArray.
      // Step 2 (index 1 of dynamic array):
      //   arrayBase = 32 + readPointer(64) = 32 + 64 = 96.
      //   length = readPointer(96) = 2. Index 1 < 2: ok.
      //   headsBase = 96 + 32 = 128. Static element: head = 128 + 1*32 = 160.
      //   base = 96 (arrayBase, since static elements).
      expect(leaf.head).toBe(160);
      expect(leaf.base).toBe(96);
      expect(leaf.node).toEqual(uint256Node());
    }
  });

  test("deeply nested: array in tuple in array", () => {
    // Static tuple containing a static array: tuple(uint256[3]).
    const innerArr = staticArrayNode(uint256Node(), 3);
    const tupleNode = staticTupleNode([innerArr]);
    const tree: DescNode[] = [tupleNode];

    // ABI layout at base 0 (all static):
    //   [arr_elem0(32) + arr_elem1(32) + arr_elem2(32)]
    const callData = concat(word(10), word(20), word(30));

    // path: param 0, field 0, index 2
    const result = locate(tree, callData, path(0, 0, 2), 0);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const leaf = result.location;
      // Step 1 (field 0 of static tuple): tupleBase=0, cursor=0, no fields to skip.
      //   head=0, base=0, node=staticArray.
      // Step 2 (index 2 of static array, static elem): head = 0 + 2*32 = 64, base = 0.
      expect(leaf.head).toBe(64);
      expect(leaf.base).toBe(0);
    }
  });

  test("with base offset (selector present)", () => {
    // func(uint256) with selector, base=4.
    const tree: DescNode[] = [uint256Node()];
    const selector = new Uint8Array([0x12, 0x34, 0x56, 0x78]);
    const callData = concat(selector, word(42));

    const result = locate(tree, callData, path(0), 4);
    expect(result.ok).toBe(true);
    if (result.ok && result.type === "leaf") {
      const leaf = result.location;
      expect(leaf.head).toBe(4);
      expect(leaf.base).toBe(4);
    }
  });
});

///////////////////////////////////////////////////////////////////////////
//                        COMPOSABLE API: LOCATE
///////////////////////////////////////////////////////////////////////////

describe("locate", () => {
  test("resolves leaf location for single param", () => {
    const tree: DescNode[] = [uint256Node()];
    const callData = word(42);
    const result = locate(tree, callData, path(0), 0);
    expect(result.ok).toBe(true);
    expect("location" in result && !("quantifier" in result)).toBe(true);
    if (result.ok && result.type === "leaf") {
      const loc = result.location;
      expect(loc.head).toBe(0);
      expect(loc.base).toBe(0);
      expect(loc.node).toEqual(uint256Node());
    }
  });

  test("returns quantifier result when path hits quantifier step", () => {
    const arrNode = dynamicArrayNode(uint256Node());
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(32), word(3), word(10), word(20), word(30));

    const result = locate(tree, callData, path(0, Quantifier.ALL_OR_EMPTY), 0);
    expect(result.ok).toBe(true);
    expect("quantifier" in result).toBe(true);
    if (result.ok && result.type === "quantifier") {
      const qr = result.quantifier;
      expect(qr.quantifier).toBe(Quantifier.ALL_OR_EMPTY);
      // The location points to the array itself, not the elements.
      expect(qr.location.node).toEqual(arrNode);
      expect(qr.remainingPath.length).toBe(0);
    }
  });

  test("quantifier with suffix path captures remaining steps", () => {
    const tupleElem = staticTupleNode([uint256Node(), addressNode()]);
    const arrNode = dynamicArrayNode(tupleElem);
    const tree: DescNode[] = [arrNode];
    const callData = concat(word(32), word(2));

    const result = locate(tree, callData, path(0, Quantifier.ANY, 1), 0);
    expect(result.ok).toBe(true);
    expect("quantifier" in result).toBe(true);
    if (result.ok && result.type === "quantifier") {
      const qr = result.quantifier;
      expect(qr.remainingPath).toEqual(path(1));
    }
  });

  test("returns error for out-of-bounds param index", () => {
    const tree: DescNode[] = [uint256Node()];
    const result = locate(tree, word(42), path(1), 0);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("OFFSET_OUT_OF_BOUNDS");
    }
  });

  test("returns error for empty path", () => {
    const tree: DescNode[] = [uint256Node()];
    const result = locate(tree, word(42), new Uint8Array(0), 0);
    expect(result.ok).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                      COMPOSABLE API: ARRAYSHAPE
///////////////////////////////////////////////////////////////////////////

describe("arrayShape", () => {
  test("dynamic array with static elements", () => {
    const arrNode = dynamicArrayNode(uint256Node());
    const callData = concat(word(32), word(3), word(10), word(20), word(30));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const result = arrayShape(callData, loc);
    expect(result.ok).toBe(true);
    assertOk(result);
    const shape = result.shape;
    expect(shape.length).toBe(3);
    expect(shape.elementIsDynamic).toBe(false);
    expect(shape.elementStaticSize).toBe(32);
    expect(shape.dataOffset).toBe(64); // arrayBase(32) + 32
    expect(shape.compositeBase).toBe(32); // arrayBase
  });

  test("dynamic array with dynamic elements", () => {
    const arrNode = dynamicArrayNode(bytesNode());
    const callData = concat(word(32), word(2), word(64), word(128));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const result = arrayShape(callData, loc);
    expect(result.ok).toBe(true);
    assertOk(result);
    const shape = result.shape;
    expect(shape.length).toBe(2);
    expect(shape.elementIsDynamic).toBe(true);
    expect(shape.headsBase).toBe(64); // arrayBase(32) + 32
    expect(shape.compositeBase).toBe(64); // headsBase for dynamic
  });

  test("static array with static elements", () => {
    const arrNode = staticArrayNode(uint256Node(), 3);
    const callData = concat(word(100), word(200), word(300));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const result = arrayShape(callData, loc);
    expect(result.ok).toBe(true);
    assertOk(result);
    const shape = result.shape;
    expect(shape.length).toBe(3);
    expect(shape.elementIsDynamic).toBe(false);
    expect(shape.dataOffset).toBe(0); // head
    expect(shape.compositeBase).toBe(0); // base
  });

  test("static array with dynamic elements", () => {
    const arrNode = staticArrayNode(bytesNode(), 2);
    const callData = concat(word(32), word(64), word(128));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const result = arrayShape(callData, loc);
    expect(result.ok).toBe(true);
    assertOk(result);
    const shape = result.shape;
    expect(shape.length).toBe(2);
    expect(shape.elementIsDynamic).toBe(true);
    expect(shape.headsBase).toBe(32); // arrayBase
    expect(shape.compositeBase).toBe(32); // arrayBase
  });

  test("returns error for non-array node", () => {
    const loc: Location = { head: 0, base: 0, node: uint256Node() };
    const result = arrayShape(word(42), loc);
    expect(result.ok).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                    COMPOSABLE API: ARRAYELEMENTAT
///////////////////////////////////////////////////////////////////////////

describe("arrayElementAt", () => {
  test("static elements: computes correct head from dataOffset", () => {
    const arrNode = dynamicArrayNode(uint256Node());
    const callData = concat(word(32), word(3), word(10), word(20), word(30));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const shapeResult = arrayShape(callData, loc);
    expect(shapeResult.ok).toBe(true);
    assertOk(shapeResult);
    const shape = shapeResult.shape;

    const elem1 = arrayElementAt(shape, 1, callData);
    expect(elem1.ok).toBe(true);
    assertOk(elem1);
    const loc1 = elem1.location;
    expect(loc1.head).toBe(96); // dataOffset(64) + 1 * 32
    expect(loc1.base).toBe(32); // compositeBase = arrayBase
  });

  test("dynamic elements: computes correct head and base from headsBase", () => {
    const arrNode = dynamicArrayNode(bytesNode());
    const callData = concat(word(32), word(2), word(64), word(128));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const shapeResult = arrayShape(callData, loc);
    expect(shapeResult.ok).toBe(true);
    assertOk(shapeResult);
    const shape = shapeResult.shape;

    const elem1 = arrayElementAt(shape, 1, callData);
    expect(elem1.ok).toBe(true);
    assertOk(elem1);
    const loc1 = elem1.location;
    expect(loc1.head).toBe(96); // headsBase(64) + 1 * 32
    expect(loc1.base).toBe(64); // headsBase
  });

  test("out of bounds index returns error", () => {
    const arrNode = dynamicArrayNode(uint256Node());
    const callData = concat(word(32), word(2), word(10), word(20));

    const loc: Location = { head: 0, base: 0, node: arrNode };
    const shapeResult = arrayShape(callData, loc);
    assertOk(shapeResult);
    const shape = shapeResult.shape;

    const result = arrayElementAt(shape, 2, callData);
    expect(result.ok).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                      COMPOSABLE API: LOADSCALAR
///////////////////////////////////////////////////////////////////////////

describe("loadScalar", () => {
  test("loads 32-byte value from location", () => {
    const callData = concat(word(42), word(99));
    const loc: Location = { head: 32, base: 0, node: uint256Node() };
    const result = loadScalar(callData, loc);
    expect(result.ok).toBe(true);
    assertOk(result);
    expect(result.value[31]).toBe(99);
  });

  test("returns error for truncated callData", () => {
    const callData = new Uint8Array(16);
    const loc: Location = { head: 0, base: 0, node: uint256Node() };
    const result = loadScalar(callData, loc);
    expect(result.ok).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                       COMPOSABLE API: LOADSLICE
///////////////////////////////////////////////////////////////////////////

describe("loadSlice", () => {
  test("reads data offset and length of dynamic bytes", () => {
    // Layout: [offset_ptr(32)] at head=0 pointing to 32, then [length(32)] at 32.
    const callData = concat(word(32), word(10));
    const loc: Location = { head: 0, base: 0, node: bytesNode() };
    const result = loadSlice(callData, loc);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.length).toBe(10);
      expect(result.dataOffset).toBe(64); // base(0) + ptr(32) + length_word(32)
    }
  });

  test("returns error for truncated callData", () => {
    const callData = new Uint8Array(16);
    const loc: Location = { head: 0, base: 0, node: bytesNode() };
    const result = loadSlice(callData, loc);
    expect(result.ok).toBe(false);
  });
});

///////////////////////////////////////////////////////////////////////////
//                      COMPOSABLE API: DESCENDPATH
///////////////////////////////////////////////////////////////////////////

describe("descendPath", () => {
  test("descends through tuple fields from a given location", () => {
    const tupleNode = staticTupleNode([uint256Node(), addressNode()]);
    const callData = concat(word(10), word(20));

    const loc: Location = { head: 0, base: 0, node: tupleNode };
    const result = descendPath(callData, loc, path(1));
    expect(result.ok).toBe(true);
    assertOk(result);
    const leaf = result.location;
    expect(leaf.head).toBe(32);
    expect(leaf.node).toEqual(addressNode());
  });

  test("descends through array and tuple", () => {
    // (uint256, uint256)[] — static tuple elements in a dynamic array.
    const tupleElem = staticTupleNode([uint256Node(), uint256Node()]);
    const callData = concat(word(32), word(2), word(0xaa), word(0xbb), word(0xcc), word(0xdd));

    // Start from element 1 location (the tuple at index 1).
    // Static element: head = dataOffset + 1 * 64 = 64 + 64 = 128, base = arrayBase = 32.
    const elemLoc: Location = { head: 128, base: 32, node: tupleElem };

    // Descend into field 1 of the tuple.
    const result = descendPath(callData, elemLoc, path(1));
    expect(result.ok).toBe(true);
    assertOk(result);
    const leaf = result.location;
    // Static tuple: tupleBase = base = 32, cursor = 128, skip field0(32) = 160.
    expect(leaf.head).toBe(160);
    expect(leaf.base).toBe(32);
  });

  test("empty path returns same location", () => {
    const loc: Location = { head: 42, base: 0, node: uint256Node() };
    const result = descendPath(word(0), loc, new Uint8Array(0));
    expect(result.ok).toBe(true);
    assertOk(result);
    expect(result.location).toEqual(loc);
  });

  test("returns error for non-composite descent", () => {
    const loc: Location = { head: 0, base: 0, node: uint256Node() };
    const result = descendPath(word(42), loc, path(0));
    expect(result.ok).toBe(false);
  });
});

import { describe, expect, test } from "vitest";

import { TypeCode } from "../src/constants";
import { Descriptor } from "../src/descriptor";
import { DescriptorCoder } from "../src/descriptor-coder";
import { expectErrorCode } from "./helpers";

///////////////////////////////////////////////////////////////////////////
// paramCount
///////////////////////////////////////////////////////////////////////////

describe("Descriptor.paramCount", () => {
  test("returns 2 for address,uint256", () => {
    const desc = DescriptorCoder.fromTypes("address,uint256");
    expect(Descriptor.paramCount(desc)).toBe(2);
  });

  test("returns 0 for empty descriptor", () => {
    const desc = DescriptorCoder.fromTypes("");
    expect(Descriptor.paramCount(desc)).toBe(0);
  });
});

///////////////////////////////////////////////////////////////////////////
// inspect
///////////////////////////////////////////////////////////////////////////

describe("Descriptor.inspect", () => {
  test("elementary address: typeCode=0x40, isDynamic=false, staticSize=32", () => {
    const desc = DescriptorCoder.fromTypes("address");
    // offset 2 = first param node.
    const info = Descriptor.inspect(desc, 2);
    expect(info.typeCode).toBe(TypeCode.ADDRESS);
    expect(info.isDynamic).toBe(false);
    expect(info.staticSize).toBe(32);
  });

  test("elementary string: typeCode=0x71, isDynamic=true, staticSize=0", () => {
    const desc = DescriptorCoder.fromTypes("string");
    const info = Descriptor.inspect(desc, 2);
    expect(info.typeCode).toBe(TypeCode.STRING);
    expect(info.isDynamic).toBe(true);
    expect(info.staticSize).toBe(0);
  });

  test("static tuple (address,uint256): typeCode=0x90, isDynamic=false, staticSize=64", () => {
    const desc = DescriptorCoder.fromTypes("(address,uint256)");
    const info = Descriptor.inspect(desc, 2);
    expect(info.typeCode).toBe(TypeCode.TUPLE);
    expect(info.isDynamic).toBe(false);
    expect(info.staticSize).toBe(64);
  });

  test("dynamic tuple (uint256,string): isDynamic=true, staticSize=0", () => {
    const desc = DescriptorCoder.fromTypes("(uint256,string)");
    const info = Descriptor.inspect(desc, 2);
    expect(info.typeCode).toBe(TypeCode.TUPLE);
    expect(info.isDynamic).toBe(true);
    expect(info.staticSize).toBe(0);
  });
});

///////////////////////////////////////////////////////////////////////////
// paramOffset
///////////////////////////////////////////////////////////////////////////

describe("Descriptor.paramOffset", () => {
  test("three elementary params → offsets 2, 3, 4", () => {
    const desc = DescriptorCoder.fromTypes("address,bool,uint256");
    expect(Descriptor.paramOffset(desc, 0)).toBe(2);
    expect(Descriptor.paramOffset(desc, 1)).toBe(3);
    expect(Descriptor.paramOffset(desc, 2)).toBe(4);
  });

  test("composite first param shifts second param offset", () => {
    // (address,uint256) is a composite node; uint256 starts after it.
    const desc = DescriptorCoder.fromTypes("(address,uint256),bool");
    const tupleOffset = 2;
    const tupleLen = Descriptor.inspect(desc, tupleOffset); // inspect to confirm it's a tuple
    expect(tupleLen.typeCode).toBe(TypeCode.TUPLE);
    // second param starts at offset 2 + nodeLength of the tuple node.
    const secondOffset = Descriptor.paramOffset(desc, 1);
    expect(secondOffset).toBeGreaterThan(3); // must be past the single-byte offset.
  });
});

///////////////////////////////////////////////////////////////////////////
// typeAt
///////////////////////////////////////////////////////////////////////////

describe("Descriptor.typeAt", () => {
  test("[0] on address → address info", () => {
    const desc = DescriptorCoder.fromTypes("address");
    const info = Descriptor.typeAt(desc, [0]);
    expect(info.typeCode).toBe(TypeCode.ADDRESS);
    expect(info.isDynamic).toBe(false);
  });

  test("[0, 1] on (address,uint256) → uint256 info", () => {
    const desc = DescriptorCoder.fromTypes("(address,uint256)");
    const info = Descriptor.typeAt(desc, [0, 1]);
    expect(info.typeCode).toBe(TypeCode.UINT_MAX);
    expect(info.isDynamic).toBe(false);
  });

  test("[0, 0] on uint256[] → uint256 info (element type)", () => {
    const desc = DescriptorCoder.fromTypes("uint256[]");
    const info = Descriptor.typeAt(desc, [0, 0]);
    expect(info.typeCode).toBe(TypeCode.UINT_MAX);
    expect(info.isDynamic).toBe(false);
  });

  test("[0, 0] on address[5] → address info (static array element)", () => {
    const desc = DescriptorCoder.fromTypes("address[5]");
    const info = Descriptor.typeAt(desc, [0, 0]);
    expect(info.typeCode).toBe(TypeCode.ADDRESS);
    expect(info.isDynamic).toBe(false);
  });

  test("[0, 0, 1] on (address,uint256)[] → uint256 info", () => {
    const desc = DescriptorCoder.fromTypes("(address,uint256)[]");
    const info = Descriptor.typeAt(desc, [0, 0, 1]);
    expect(info.typeCode).toBe(TypeCode.UINT_MAX);
    expect(info.isDynamic).toBe(false);
  });

  test("throws INVALID_PATH when descending into elementary type", () => {
    const desc = DescriptorCoder.fromTypes("address");
    expectErrorCode(() => Descriptor.typeAt(desc, [0, 0]), "INVALID_PATH");
  });

  test("throws INVALID_PATH for empty steps", () => {
    const desc = DescriptorCoder.fromTypes("address");
    expectErrorCode(() => Descriptor.typeAt(desc, []), "INVALID_PATH");
  });

  test("throws INVALID_PATH for out-of-bounds param index", () => {
    const desc = DescriptorCoder.fromTypes("address");
    expectErrorCode(() => Descriptor.typeAt(desc, [5]), "INVALID_PATH");
  });
});

///////////////////////////////////////////////////////////////////////////
// tupleFieldCount
///////////////////////////////////////////////////////////////////////////

describe("Descriptor.tupleFieldCount", () => {
  test("returns 2 for (address,uint256)", () => {
    const desc = DescriptorCoder.fromTypes("(address,uint256)");
    expect(Descriptor.tupleFieldCount(desc, 2)).toBe(2);
  });
});

///////////////////////////////////////////////////////////////////////////
// staticArrayLength
///////////////////////////////////////////////////////////////////////////

describe("Descriptor.staticArrayLength", () => {
  test("returns 5 for address[5]", () => {
    const desc = DescriptorCoder.fromTypes("address[5]");
    expect(Descriptor.staticArrayLength(desc, 2)).toBe(5);
  });
});

import { describe, expect, test } from "vitest";

import { bytesToHex } from "../src/bytes";
import { Quantifier, TypeCode } from "../src/constants";
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

///////////////////////////////////////////////////////////////////////////
// walkPath
///////////////////////////////////////////////////////////////////////////

describe("Descriptor.walkPath", () => {
  test("no quantifier → zero quantified length", () => {
    const desc = DescriptorCoder.fromTypes("uint256");
    const walk = Descriptor.walkPath(desc, [0]);
    expect(walk.typeInfo.typeCode).toBe(TypeCode.UINT_MAX);
    expect(walk.quantifiedStaticLength).toBe(0);
  });

  test("quantifier over static array → declared length", () => {
    const desc = DescriptorCoder.fromTypes("uint256[3]");
    const walk = Descriptor.walkPath(desc, [0, Quantifier.ALL]);
    expect(walk.typeInfo.typeCode).toBe(TypeCode.UINT_MAX);
    expect(walk.quantifiedStaticLength).toBe(3);
  });

  test("all sentinels return the declared length", () => {
    const desc = DescriptorCoder.fromTypes("address[7]");
    expect(Descriptor.walkPath(desc, [0, Quantifier.ALL]).quantifiedStaticLength).toBe(7);
    expect(Descriptor.walkPath(desc, [0, Quantifier.ANY]).quantifiedStaticLength).toBe(7);
    expect(Descriptor.walkPath(desc, [0, Quantifier.ALL]).quantifiedStaticLength).toBe(7);
  });

  test("quantifier over dynamic array → zero", () => {
    const desc = DescriptorCoder.fromTypes("uint256[]");
    expect(Descriptor.walkPath(desc, [0, Quantifier.ALL]).quantifiedStaticLength).toBe(0);
  });

  test("concrete index into static array → zero", () => {
    const desc = DescriptorCoder.fromTypes("uint256[3]");
    expect(Descriptor.walkPath(desc, [0, 1]).quantifiedStaticLength).toBe(0);
  });

  test("suffix after quantifier → length and field type", () => {
    const desc = DescriptorCoder.fromTypes("(address,uint256)[4]");
    const walk = Descriptor.walkPath(desc, [0, Quantifier.ALL, 1]);
    expect(walk.typeInfo.typeCode).toBe(TypeCode.UINT_MAX);
    expect(walk.quantifiedStaticLength).toBe(4);
  });
});

///////////////////////////////////////////////////////////////////////////
// compileHint
///////////////////////////////////////////////////////////////////////////

describe("Descriptor.compileHint", () => {
  /** Compile the hint for `steps` against the descriptor of `typesCsv`. */
  function compile(typesCsv: string, steps: number[]): string {
    return bytesToHex(Descriptor.compileHint(DescriptorCoder.fromTypes(typesCsv), steps));
  }

  /** Assert that compilation throws UNCOMPILABLE_PATH. */
  function expectUncompilable(typesCsv: string, steps: number[]): void {
    expect(() => compile(typesCsv, steps)).toThrowError(expect.objectContaining({ code: "UNCOMPILABLE_PATH" }));
  }

  describe("static layout", () => {
    test("first argument", () => {
      expect(compile("uint256", [0])).toBe("0x0000000000000020");
    });

    test("second argument skips the preceding head", () => {
      expect(compile("uint256,address", [1])).toBe("0x0000000020000041");
    });

    test("dynamic sibling occupies one word", () => {
      expect(compile("bytes,uint256", [1])).toBe("0x0000000020000020");
    });

    test("static tuple field", () => {
      expect(compile("(address,uint256)", [0, 1])).toBe("0x0000000020000020");
    });

    test("static array element", () => {
      expect(compile("uint256[3]", [0, 2])).toBe("0x0000000040000020");
    });

    test("nested static tuple", () => {
      expect(compile("((uint256,address),uint256)", [0, 0, 1])).toBe("0x0000000020000041");
    });
  });

  describe("hop chains", () => {
    test("bytes target enters its payload", () => {
      expect(compile("uint256,bytes", [1])).toBe("0x0100000020ffff000000000000000070");
    });

    test("dynamic array target carries its meta word", () => {
      expect(compile("uint256[]", [0])).toBe("0x0100000000ffff000000000000400181");
    });

    test("concrete index into a dynamic array emits an element hop", () => {
      expect(compile("uint256[]", [0, 1])).toBe("0x0200000000ffff0000000000000001400100000000000020");
    });

    test("field of a dynamic tuple enters the tuple", () => {
      expect(compile("(bytes,uint256)", [0, 1])).toBe("0x0100000000ffff000000000020000020");
    });
  });

  describe("quantified layout", () => {
    test("quantifier over a dynamic array", () => {
      expect(compile("uint256[]", [0, Quantifier.ALL])).toBe("0x4100000000ffff000000000000000040010000000000000020");
    });

    test("quantifier carries the array head", () => {
      expect(compile("uint256,address[]", [1, Quantifier.ANY])).toBe(
        "0x8100000020ffff000000000000000040010000000000000041",
      );
    });

    test("quantifier with a suffix", () => {
      expect(compile("(address,uint256)[]", [0, Quantifier.ALL, 1])).toBe(
        "0x4100000000ffff000000000000000040020000000020000020",
      );
    });

    test("quantifier over a static array declares its count", () => {
      expect(compile("uint256[3]", [0, Quantifier.ALL])).toBe("0x4000000000000300010000000000000020");
    });

    test("quantifier over dynamic elements", () => {
      expect(compile("bytes[]", [0, Quantifier.ALL])).toBe("0x4100000000ffff0000000000000000c0010000000000000070");
    });

    test("suffix into a dynamic element emits no entry hop", () => {
      expect(compile("(uint256,bytes)[]", [0, Quantifier.ALL, 0])).toBe(
        "0x4100000000ffff0000000000000000c0010000000000000020",
      );
    });
  });

  describe("uncompilable paths", () => {
    test("quantifier over a non-array", () => {
      expectUncompilable("(address,uint256)", [0, Quantifier.ALL]);
    });

    test("nested quantifiers", () => {
      expectUncompilable("uint256[][]", [0, Quantifier.ALL, Quantifier.ALL]);
    });

    test("argument index out of bounds", () => {
      expectUncompilable("uint256", [1]);
    });

    test("tuple field out of bounds", () => {
      expectUncompilable("(address,uint256)", [0, 2]);
    });

    test("static array index out of bounds", () => {
      expectUncompilable("uint256[3]", [0, 3]);
    });

    test("step into an elementary type", () => {
      expectUncompilable("uint256", [0, 0]);
    });
  });
});

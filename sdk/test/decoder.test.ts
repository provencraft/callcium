import { describe, expect, test } from "vitest";

import { decodeDescriptor, _decodeDescriptorFromBytes, decodePolicy, _decodePolicyFromBytes } from "../src/decoder";
import { hexToBytes } from "../src/hex";
import { expectErrorCode } from "./helpers";

describe("decodeDescriptor", () => {
  ///////////////////////////////////////////////////////////////////////////
  //                       EMPTY AND SINGLE-PARAM
  ///////////////////////////////////////////////////////////////////////////

  test("empty params descriptor (0x0100)", () => {
    const result = decodeDescriptor("0x0100");
    expect(result.version).toBe(1);
    expect(result.params).toEqual([]);
  });

  test("single uint256", () => {
    const result = decodeDescriptor("0x01011f");
    expect(result.version).toBe(1);
    expect(result.params).toHaveLength(1);
    expect(result.params[0]).toMatchObject({
      index: 0,
      typeCode: 0x1f,
      isDynamic: false,
      staticSize: 32,
      path: "0x0000",
    });
  });

  test("single address", () => {
    const result = decodeDescriptor("0x010140");
    expect(result.params[0]).toMatchObject({
      typeCode: 0x40,
      isDynamic: false,
      staticSize: 32,
    });
  });

  test("single bool", () => {
    const result = decodeDescriptor("0x010141");
    expect(result.params[0]).toMatchObject({
      typeCode: 0x41,
      isDynamic: false,
      staticSize: 32,
    });
  });

  test("single bytes (dynamic)", () => {
    const result = decodeDescriptor("0x010170");
    expect(result.params[0]).toMatchObject({
      typeCode: 0x70,
      isDynamic: true,
      staticSize: 0,
    });
  });

  test("single string (dynamic)", () => {
    const result = decodeDescriptor("0x010171");
    expect(result.params[0]).toMatchObject({
      typeCode: 0x71,
      isDynamic: true,
      staticSize: 0,
    });
  });

  test("single bytes32 (fixed)", () => {
    const result = decodeDescriptor("0x01016f");
    expect(result.params[0]).toMatchObject({
      typeCode: 0x6f,
      isDynamic: false,
      staticSize: 32,
    });
  });

  ///////////////////////////////////////////////////////////////////////////
  //                           MULTI-PARAM
  ///////////////////////////////////////////////////////////////////////////

  test("three params: address, uint256, bytes", () => {
    const result = decodeDescriptor("0x0103401f70");
    expect(result.params).toHaveLength(3);
    expect(result.params[0]).toMatchObject({ typeCode: 0x40, path: "0x0000" });
    expect(result.params[1]).toMatchObject({ typeCode: 0x1f, path: "0x0001" });
    expect(result.params[2]).toMatchObject({
      typeCode: 0x70,
      path: "0x0002",
      isDynamic: true,
    });
  });

  ///////////////////////////////////////////////////////////////////////////
  //                         COMPOSITE TYPES
  ///////////////////////////////////////////////////////////////////////////

  test("static array uint256[4]", () => {
    const result = decodeDescriptor("0x0101800040071f0004");
    expect(result.params).toHaveLength(1);
    expect(result.params[0]).toMatchObject({
      typeCode: 0x80,
      isDynamic: false,
      staticSize: 128,
    });
  });

  test("dynamic array address[]", () => {
    const result = decodeDescriptor("0x01018100000540");
    expect(result.params).toHaveLength(1);
    expect(result.params[0]).toMatchObject({
      typeCode: 0x81,
      isDynamic: true,
      staticSize: 0,
    });
  });

  test("tuple (address, uint256)", () => {
    const result = decodeDescriptor("0x0101900020080002401f");
    expect(result.params).toHaveLength(1);
    expect(result.params[0]).toMatchObject({
      typeCode: 0x90,
      isDynamic: false,
      staticSize: 64,
    });
  });

  ///////////////////////////////////////////////////////////////////////////
  //                           ERROR CASES
  ///////////////////////////////////////////////////////////////////////////

  test("rejects empty blob", () => {
    expectErrorCode(() => decodeDescriptor("0x"), "MALFORMED_HEADER");
  });

  test("rejects too-short blob (1 byte)", () => {
    expectErrorCode(() => decodeDescriptor("0x01"), "MALFORMED_HEADER");
  });

  test("rejects unsupported version", () => {
    expectErrorCode(() => decodeDescriptor("0x0200"), "UNSUPPORTED_VERSION");
  });

  test("rejects param count mismatch (trailing bytes)", () => {
    expectErrorCode(() => decodeDescriptor("0x01014040"), "PARAM_COUNT_MISMATCH");
  });

  test("rejects param count mismatch (too few params)", () => {
    expectErrorCode(() => decodeDescriptor("0x010240"), "PARAM_COUNT_MISMATCH");
  });

  test("rejects unknown type code", () => {
    expectErrorCode(() => decodeDescriptor("0x010143"), "UNKNOWN_TYPE_CODE");
  });

  test("rejects tuple with zero fields", () => {
    expectErrorCode(() => decodeDescriptor("0x0101900000060000"), "INVALID_TUPLE_FIELD_COUNT");
  });

  test("rejects static array with zero length", () => {
    expectErrorCode(() => decodeDescriptor("0x010180000007400000"), "INVALID_ARRAY_LENGTH");
  });

  test("rejects node length too small", () => {
    expectErrorCode(() => decodeDescriptor("0x010181000000"), "MALFORMED_HEADER");
  });

  test("rejects node overflow", () => {
    expectErrorCode(() => decodeDescriptor("0x0101810000ff40"), "NODE_OVERFLOW");
  });
});

describe("_decodeDescriptorFromBytes", () => {
  test("returns tree alongside descriptor", () => {
    const { descriptor, tree } = _decodeDescriptorFromBytes(hexToBytes("0x01011f"));
    expect(descriptor.params).toHaveLength(1);
    expect(tree).toHaveLength(1);
    expect(tree[0]).toMatchObject({
      type: "elementary",
      typeCode: 0x1f,
      isDynamic: false,
      staticSize: 32,
    });
  });

  test("tuple tree has fields", () => {
    const { tree } = _decodeDescriptorFromBytes(hexToBytes("0x0101900020080002401f"));
    expect(tree).toHaveLength(1);
    const tupleNode = tree[0];
    expect(tupleNode).toBeDefined();
    expect(tupleNode?.type).toBe("tuple");
    if (tupleNode?.type === "tuple") {
      expect(tupleNode.fields).toHaveLength(2);
      expect(tupleNode.fields[0]).toMatchObject({
        type: "elementary",
        typeCode: 0x40,
      });
      expect(tupleNode.fields[1]).toMatchObject({
        type: "elementary",
        typeCode: 0x1f,
      });
    }
  });

  test("static array tree has element and length", () => {
    const { tree } = _decodeDescriptorFromBytes(hexToBytes("0x0101800040071f0004"));
    expect(tree).toHaveLength(1);
    const arrNode = tree[0];
    expect(arrNode).toBeDefined();
    expect(arrNode?.type).toBe("staticArray");
    if (arrNode?.type === "staticArray") {
      expect(arrNode.length).toBe(4);
      expect(arrNode.element).toMatchObject({
        type: "elementary",
        typeCode: 0x1f,
      });
    }
  });

  test("dynamic array tree has element", () => {
    const { tree } = _decodeDescriptorFromBytes(hexToBytes("0x01018100000540"));
    expect(tree).toHaveLength(1);
    const arrNode = tree[0];
    expect(arrNode).toBeDefined();
    expect(arrNode?.type).toBe("dynamicArray");
    if (arrNode?.type === "dynamicArray") {
      expect(arrNode.element).toMatchObject({
        type: "elementary",
        typeCode: 0x40,
      });
    }
  });
});

describe("decodePolicy", () => {
  // calldata-eq-uint256: single EQ rule on uint256 arg(0), calldata scope.
  const BLOB_EQ_UINT256 =
    "0x012fbebd38000301011f01000100000029002901010000010020000000000000000000000000000000000000000000000000000000000000002a";

  ///////////////////////////////////////////////////////////////////////////
  //                         CORE PROPERTIES
  ///////////////////////////////////////////////////////////////////////////

  test("decodes calldata-eq-uint256 header fields", () => {
    const result = decodePolicy(BLOB_EQ_UINT256);
    expect(result.version).toBe(1);
    expect(result.isSelectorless).toBe(false);
    expect(result.header.value).toBe(0x01);
    expect(result.selector.value).toBe("0x2fbebd38");
  });

  test("decodes descriptor embedded in policy", () => {
    const result = decodePolicy(BLOB_EQ_UINT256);
    expect(result.descriptor.raw).toBe("0x01011f");
    expect(result.descriptor.params).toHaveLength(1);
    expect(result.descriptor.params[0]).toMatchObject({
      index: 0,
      typeCode: 0x1f,
      isDynamic: false,
      staticSize: 32,
    });
  });

  test("decodes single group with one rule", () => {
    const result = decodePolicy(BLOB_EQ_UINT256);
    expect(result.groups).toHaveLength(1);
    const group = result.groups[0];
    expect(group).toBeDefined();
    expect(group?.rules).toHaveLength(1);
    const rule = group?.rules[0];
    expect(rule).toBeDefined();
    expect(rule?.scope.value).toBe(0x01); // SCOPE_CALLDATA
    expect(rule?.path.value).toBe("0x0000");
    expect(rule?.opCode.value).toBe(0x01); // OP_EQ
    expect(rule?.data.value).toBe("0x000000000000000000000000000000000000000000000000000000000000002a");
  });

  test("span covers full blob", () => {
    const blobBytes = BLOB_EQ_UINT256.slice(2).length / 2;
    const result = decodePolicy(BLOB_EQ_UINT256);
    expect(result.span.start).toBe(0);
    expect(result.span.end).toBe(blobBytes);
  });

  ///////////////////////////////////////////////////////////////////////////
  //                           ERROR CASES
  ///////////////////////////////////////////////////////////////////////////

  test("rejects too-short blob", () => {
    expectErrorCode(() => decodePolicy("0x01"), "MALFORMED_HEADER");
  });

  test("rejects non-zero reserved header bits", () => {
    // Set bit 5 (reserved) in the header byte.
    const blob =
      "0x212fbebd38000301011f01000100000029002901010000010020000000000000000000000000000000000000000000000000000000000000002a";
    expectErrorCode(() => decodePolicy(blob), "MALFORMED_HEADER");
  });

  test("rejects selectorless policy with non-zero selector", () => {
    // header 0x11 = VERSION | FLAG_NO_SELECTOR, but selector is 0x2fbebd38.
    const blob =
      "0x112fbebd38000301011f01000100000029002901010000010020000000000000000000000000000000000000000000000000000000000000002a";
    expectErrorCode(() => decodePolicy(blob), "MALFORMED_HEADER");
  });

  test("rejects rule with pathDepth 0", () => {
    // Construct a minimal policy blob with a rule where pathDepth == 0.
    // Rule with depth=0 triggers EMPTY_PATH before any size check.
    // Layout: ruleSize(2) + scope(1) + depth(1)=0 + opCode(1) + dataLength(2) + data(32).
    const desc = "01011f"; // descriptor: version + 1 param uint256
    const ruleData = "0000000000000000000000000000000000000000000000000000000000000001";
    // ruleSize = 7 + 0*2 + 32 = 39 = 0x0027, but depth=0 triggers EMPTY_PATH first.
    const rule = "0027" + "01" + "00" + "" + "01" + "0020" + ruleData;
    const groupSize = rule.length / 2;
    const groupSizeHex = groupSize.toString(16).padStart(8, "0");
    const group = "0001" + groupSizeHex + rule;
    const descLen = (desc.length / 2).toString(16).padStart(4, "0");
    const policyHex = "01" + "2fbebd38" + descLen + desc + "01" + group;
    expectErrorCode(() => decodePolicy(`0x${policyHex}`), "EMPTY_PATH");
  });

  test("rejects context rule with pathDepth > 1", () => {
    // scope=0 (context), depth=2 should trigger INVALID_CONTEXT_PATH.
    const desc = "01011f";
    const ruleData = "0000000000000000000000000000000000000000000000000000000000000001";
    // ruleSize = 7 + 2*2 + 32 = 43 = 0x002b
    const rule = "002b" + "00" + "02" + "00000001" + "01" + "0020" + ruleData;
    const groupSize = rule.length / 2;
    const groupSizeHex = groupSize.toString(16).padStart(8, "0");
    const group = "0001" + groupSizeHex + rule;
    const descLen = (desc.length / 2).toString(16).padStart(4, "0");
    const policyHex = "01" + "2fbebd38" + descLen + desc + "01" + group;
    expectErrorCode(() => decodePolicy(`0x${policyHex}`), "INVALID_CONTEXT_PATH");
  });
});

describe("_decodePolicyFromBytes", () => {
  const BLOB_EQ_UINT256 =
    "0x012fbebd38000301011f01000100000029002901010000010020000000000000000000000000000000000000000000000000000000000000002a";

  test("returns policy and DescNode tree", () => {
    const { policy, tree } = _decodePolicyFromBytes(hexToBytes(BLOB_EQ_UINT256));
    expect(policy.version).toBe(1);
    expect(tree).toHaveLength(1);
    expect(tree[0]).toMatchObject({ type: "elementary", typeCode: 0x1f });
  });
});

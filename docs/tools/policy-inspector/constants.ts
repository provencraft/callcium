///////////////////////////////////////////////////////////////////////////
//                              LAYOUT OBJECTS
///////////////////////////////////////////////////////////////////////////

export const PolicyFormat = {
  VERSION: 0x01,
  VERSION_MASK: 0x0f,
  FLAG_NO_SELECTOR: 0x10,
  RESERVED_MASK: 0xe0,
  HEADER_SIZE: 1,
  SELECTOR_OFFSET: 1,
  SELECTOR_SIZE: 4,
  DESC_LENGTH_OFFSET: 5,
  DESC_LENGTH_SIZE: 2,
  DESC_OFFSET: 7,
  GROUP_COUNT_SIZE: 1,
  GROUP_RULECOUNT_SIZE: 2,
  GROUP_SIZE_SIZE: 4,
  GROUP_HEADER_SIZE: 6,
  RULE_SIZE_SIZE: 2,
  RULE_SCOPE_OFFSET: 2,
  RULE_DEPTH_OFFSET: 3,
  RULE_PATH_OFFSET: 4,
  PATH_STEP_SIZE: 2,
  RULE_OPCODE_SIZE: 1,
  RULE_DATALENGTH_SIZE: 2,
  RULE_FIXED_OVERHEAD: 7,
  RULE_MIN_SIZE: 9,
} as const;

export const DescriptorFormat = {
  VERSION: 0x01,
  HEADER_SIZE: 2,
  TYPECODE_SIZE: 1,
  COMPOSITE_META_SIZE: 3,
  TUPLE_FIELDCOUNT_SIZE: 2,
  META_STATIC_WORDS_SHIFT: 12,
  META_NODE_LENGTH_MASK: 0x0fff,
  ARRAY_HEADER_SIZE: 4,
  TUPLE_HEADER_SIZE: 6,
  ARRAY_LENGTH_SIZE: 2,
  MAX_NODE_LENGTH: 0x0fff,
  MAX_STATIC_ARRAY_LENGTH: 4095,
  MAX_TUPLE_FIELDS: 4089,
  MAX_PARAMS: 255,
} as const;

///////////////////////////////////////////////////////////////////////////
//                              DOMAIN VALUES
///////////////////////////////////////////////////////////////////////////

export const Scopes = {
  CONTEXT: { code: 0x00, label: "context" },
  CALLDATA: { code: 0x01, label: "calldata" },
} as const;

export const ContextProperties = {
  MSG_SENDER: { code: 0x0000, label: "msg.sender" },
  MSG_VALUE: { code: 0x0001, label: "msg.value" },
  BLOCK_TIMESTAMP: { code: 0x0002, label: "block.timestamp" },
  BLOCK_NUMBER: { code: 0x0003, label: "block.number" },
  CHAIN_ID: { code: 0x0004, label: "block.chainid" },
  TX_ORIGIN: { code: 0x0005, label: "tx.origin" },
} as const;

export const OpCodes = {
  EQ: { code: 0x01, label: "==" },
  GT: { code: 0x02, label: ">" },
  LT: { code: 0x03, label: "<" },
  GTE: { code: 0x04, label: ">=" },
  LTE: { code: 0x05, label: "<=" },
  BETWEEN: { code: 0x06, label: "between" },
  IN: { code: 0x07, label: "in" },
  BITMASK_ALL: { code: 0x10, label: "bitmask all" },
  BITMASK_ANY: { code: 0x11, label: "bitmask any" },
  BITMASK_NONE: { code: 0x12, label: "bitmask none" },
  LENGTH_EQ: { code: 0x20, label: "length ==" },
  LENGTH_GT: { code: 0x21, label: "length >" },
  LENGTH_LT: { code: 0x22, label: "length <" },
  LENGTH_GTE: { code: 0x23, label: "length >=" },
  LENGTH_LTE: { code: 0x24, label: "length <=" },
  LENGTH_BETWEEN: { code: 0x25, label: "length between" },
  NOT: { code: 0x80, label: "not" },
} as const;

// Structured error for decoder failures.
export class DecodeError extends Error {
  constructor(
    public code: string,
    message: string,
    public offset?: number,
  ) {
    const prefix = offset !== undefined ? `[byte ${offset}] ` : "";
    super(`${prefix}${message}`);
    this.name = "DecodeError";
  }
}

// Unified type code lookup. Returns label, classification, and dynamic flag.
// Throws DecodeError on unknown type codes.

export type TypeClass = "elementary" | "staticArray" | "dynamicArray" | "tuple";

export type TypeCodeInfo = {
  label: string;
  typeClass: TypeClass;
  isDynamic: boolean;
};

export function lookupTypeCode(code: number): TypeCodeInfo {
  if (code >= 0x00 && code <= 0x1f)
    return {
      label: `uint${(code + 1) * 8}`,
      typeClass: "elementary",
      isDynamic: false,
    };
  if (code >= 0x20 && code <= 0x3f)
    return {
      label: `int${(code - 0x20 + 1) * 8}`,
      typeClass: "elementary",
      isDynamic: false,
    };
  if (code === 0x40) return { label: "address", typeClass: "elementary", isDynamic: false };
  if (code === 0x41) return { label: "bool", typeClass: "elementary", isDynamic: false };
  if (code === 0x42) return { label: "function", typeClass: "elementary", isDynamic: false };
  if (code >= 0x50 && code <= 0x6f)
    return {
      label: `bytes${code - 0x50 + 1}`,
      typeClass: "elementary",
      isDynamic: false,
    };
  if (code === 0x70) return { label: "bytes", typeClass: "elementary", isDynamic: true };
  if (code === 0x71) return { label: "string", typeClass: "elementary", isDynamic: true };
  if (code === 0x80) return { label: "T[k]", typeClass: "staticArray", isDynamic: false };
  if (code === 0x81) return { label: "T[]", typeClass: "dynamicArray", isDynamic: true };
  if (code === 0x90) return { label: "tuple", typeClass: "tuple", isDynamic: false };
  throw new DecodeError("UnknownTypeCode", `Unrecognized type code 0x${code.toString(16)}`);
}

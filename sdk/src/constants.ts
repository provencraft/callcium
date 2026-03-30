///////////////////////////////////////////////////////////////////////////
//                        Descriptor format
///////////////////////////////////////////////////////////////////////////

/** Binary layout constants for the Callcium descriptor format. */
export const DescriptorFormat = {
  VERSION: 0x01,
  HEADER_SIZE: 2,
  TYPECODE_SIZE: 1,
  COMPOSITE_META_SIZE: 3,
  TUPLE_HEADER_SIZE: 6,
  ARRAY_HEADER_SIZE: 4,
  ARRAY_LENGTH_SIZE: 2,
  TUPLE_FIELDCOUNT_SIZE: 2,
  META_STATIC_WORDS_SHIFT: 12,
  META_NODE_LENGTH_MASK: 0x0fff,
  MAX_NODE_LENGTH: 0x0fff,
  MAX_STATIC_ARRAY_LENGTH: 4095,
  MAX_TUPLE_FIELDS: 4089,
  MAX_PARAMS: 255,
} as const satisfies Record<string, number>;

///////////////////////////////////////////////////////////////////////////
//                          Policy format
///////////////////////////////////////////////////////////////////////////

/** Binary layout constants for the Callcium policy format. */
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
} as const satisfies Record<string, number>;

///////////////////////////////////////////////////////////////////////////
//                               Scope codes
///////////////////////////////////////////////////////////////////////////

/** Rule scope discriminant: context (EVM environment) vs. calldata (ABI payload). */
export const Scope = {
  CONTEXT: 0x00,
  CALLDATA: 0x01,
} as const satisfies Record<string, number>;

///////////////////////////////////////////////////////////////////////////
//                        Context property IDs
///////////////////////////////////////////////////////////////////////////

/** Well-known context property IDs for context-scope rules. */
export const ContextProperty = {
  MSG_SENDER: 0x0000,
  MSG_VALUE: 0x0001,
  BLOCK_TIMESTAMP: 0x0002,
  BLOCK_NUMBER: 0x0003,
  CHAIN_ID: 0x0004,
  TX_ORIGIN: 0x0005,
} as const satisfies Record<string, number>;

/** Maximum valid context property ID. */
export const MAX_CONTEXT_PROPERTY_ID = Math.max(...Object.values(ContextProperty));

///////////////////////////////////////////////////////////////////////////
//                          Protocol limits
///////////////////////////////////////////////////////////////////////////

/** Protocol-imposed safety limits for path depth and quantifier array size. */
export const Limits = {
  MAX_PATH_DEPTH: 32,
  MAX_QUANTIFIED_ARRAY_LENGTH: 256,
} as const satisfies Record<string, number>;

///////////////////////////////////////////////////////////////////////////
//                         Operator codes
///////////////////////////////////////////////////////////////////////////

/** Callcium policy operator codes. */
export const Op = {
  EQ: 0x01,
  GT: 0x02,
  LT: 0x03,
  GTE: 0x04,
  LTE: 0x05,
  BETWEEN: 0x06,
  IN: 0x07,
  BITMASK_ALL: 0x10,
  BITMASK_ANY: 0x11,
  BITMASK_NONE: 0x12,
  LENGTH_EQ: 0x20,
  LENGTH_GT: 0x21,
  LENGTH_LT: 0x22,
  LENGTH_GTE: 0x23,
  LENGTH_LTE: 0x24,
  LENGTH_BETWEEN: 0x25,
  NOT: 0x80,
} as const satisfies Record<string, number>;

///////////////////////////////////////////////////////////////////////////
//                          Quantifier steps
///////////////////////////////////////////////////////////////////////////

/** Reserved path step values that trigger quantified evaluation over array elements. */
export const Quantifier = {
  ALL_OR_EMPTY: 0xffff,
  ALL: 0xfffe,
  ANY: 0xfffd,
} as const satisfies Record<string, number>;

///////////////////////////////////////////////////////////////////////////
//                          Type code ranges
///////////////////////////////////////////////////////////////////////////

/** ABI type code ranges and sentinel values for the descriptor format. */
export const TypeCode = {
  UINT_MIN: 0x00,
  UINT_MAX: 0x1f,
  INT_MIN: 0x20,
  INT_MAX: 0x3f,
  ADDRESS: 0x40,
  BOOL: 0x41,
  FUNCTION: 0x42,
  FIXED_BYTES_MIN: 0x50,
  FIXED_BYTES_MAX: 0x6f,
  BYTES: 0x70,
  STRING: 0x71,
  STATIC_ARRAY: 0x80,
  DYNAMIC_ARRAY: 0x81,
  TUPLE: 0x90,
} as const satisfies Record<string, number>;

// Operator data size validation.
const SINGLE_OPERAND_OPS = new Set<number>([
  Op.EQ,
  Op.GT,
  Op.LT,
  Op.GTE,
  Op.LTE,
  Op.BITMASK_ALL,
  Op.BITMASK_ANY,
  Op.BITMASK_NONE,
  Op.LENGTH_EQ,
  Op.LENGTH_GT,
  Op.LENGTH_LT,
  Op.LENGTH_GTE,
  Op.LENGTH_LTE,
]);
const RANGE_OPS = new Set<number>([Op.BETWEEN, Op.LENGTH_BETWEEN]);

/**
 * Check whether an operator's data payload has the correct length.
 * @param opBase - Base operator code with the NOT flag stripped.
 * @param dataLength - Byte length of the operator's data payload.
 * @returns True if the data length is valid for the given operator.
 */
export function isValidOperatorData(opBase: number, dataLength: number): boolean {
  if (SINGLE_OPERAND_OPS.has(opBase)) return dataLength === 32;
  if (RANGE_OPS.has(opBase)) return dataLength === 64;
  if (opBase === Op.IN) return dataLength > 0 && dataLength % 32 === 0;
  return false;
}

import { CallciumError } from "./errors";

///////////////////////////////////////////////////////////////////////////
// Descriptor format
///////////////////////////////////////////////////////////////////////////

/** Binary layout constants for the Callcium descriptor format. */
export const DescriptorFormat = {
  VERSION: 0x02,
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
  MAX_STATIC_WORDS: 4095,
  MAX_PARAMS: 255,
  MAX_NESTING_DEPTH: 64,
} as const satisfies Record<string, number>;

///////////////////////////////////////////////////////////////////////////
// Policy format
///////////////////////////////////////////////////////////////////////////

/** Byte width of a rule's data length field. */
const RULE_DATALENGTH_SIZE = 2;

/** Binary layout constants and normative limits for the Callcium policy format. */
export const PolicyFormat = {
  VERSION: 0x02,
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
  RULE_DATALENGTH_SIZE,
  RULE_FIXED_OVERHEAD: 7,
  RULE_MIN_SIZE: 9,
  HINT_HEADER_SIZE: 1,
  HINT_HOP_SIZE: 8,
  HINT_HOP_INDEX_OFFSET: 4,
  HINT_HOP_META_OFFSET: 6,
  HINT_FRAME_PREFIX_SIZE: 8,
  HINT_FRAME_COUNT_OFFSET: 4,
  HINT_FRAME_META_OFFSET: 6,
  HINT_TARGET_SIZE: 7,
  HINT_TARGET_META_OFFSET: 4,
  HINT_TARGET_TYPECODE_OFFSET: 6,
  HINT_KIND_NONE: 0x0,
  HINT_KIND_ALL: 0x1,
  HINT_KIND_ANY: 0x2,
  HINT_KIND_MAX: 0x2,
  HINT_KIND_SHIFT: 6,
  HINT_HOP_COUNT_MASK: 0x3f,
  HINT_SUFFIX_RESERVED_MASK: 0xc0,
  HINT_NO_INDEX: 0xffff,
  HINT_INDEX_RESERVED: 0xfffe,
  HINT_META_ELEM_DYNAMIC: 0x8000,
  HINT_META_DYNAMIC_ARRAY: 0x4000,
  HINT_META_RESERVED_MASK: 0x3000,
  HINT_META_STRIDE_MASK: 0x0fff,
  // Normative limits.
  MAX_PATH_DEPTH: 32,
  MAX_QUANTIFIED_ARRAY_LENGTH: 256,
  MAX_SET_MEMBERS: Math.floor((256 ** RULE_DATALENGTH_SIZE - 1) / 32),
} as const satisfies Record<string, number>;

///////////////////////////////////////////////////////////////////////////
// Table-derived helpers
///////////////////////////////////////////////////////////////////////////

/**
 * Extract a `{ KEY: code }` map from a table with `key` and `code` fields.
 * @internal
 */
type CodeMap<T extends readonly { readonly key: string; readonly code: number }[]> = {
  readonly [E in T[number] as E["key"]]: E["code"];
};

/** Build a plain `{ KEY: code }` object from a table at runtime. */
export function buildCodeMap<T extends readonly { readonly key: string; readonly code: number }[]>(
  table: T,
): CodeMap<T> {
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- derived from the same const table that defines the type.
  return Object.fromEntries(table.map((e) => [e.key, e.code])) as CodeMap<T>;
}

///////////////////////////////////////////////////////////////////////////
// Scope codes
///////////////////////////////////////////////////////////////////////////

const SCOPE_TABLE = [
  { key: "CONTEXT", code: 0x00, label: "context" },
  { key: "CALLDATA", code: 0x01, label: "calldata" },
] as const;

/** Rule scope discriminant: context (EVM environment) vs. calldata (ABI payload). */
export const Scope = buildCodeMap(SCOPE_TABLE);

/** Display metadata for a scope code. */
export type ScopeInfo = { label: string };

const scopeByCode: ReadonlyMap<number, ScopeInfo> = new Map<number, ScopeInfo>(
  SCOPE_TABLE.map((e) => [e.code, { label: e.label }]),
);

/**
 * Map a scope code to its display label.
 * @param code - Scope byte value.
 * @returns Display metadata for the scope.
 * @throws {CallciumError} If the code is not a recognised scope.
 */
export function lookupScope(code: number): ScopeInfo {
  const info = scopeByCode.get(code);
  if (!info) throw new CallciumError("INVALID_SCOPE", `Unknown scope value ${code}`);
  return info;
}

///////////////////////////////////////////////////////////////////////////
// Type code ranges
///////////////////////////////////////////////////////////////////////////

/** ABI type code ranges and sentinel values for the descriptor format. */
export const TypeCode = {
  UINT_MIN: 0x01,
  UINT_MAX: 0x20,
  INT_MIN: 0x21,
  INT_MAX: 0x40,
  ADDRESS: 0x41,
  BOOL: 0x42,
  FUNCTION: 0x43,
  FIXED_BYTES_MIN: 0x50,
  FIXED_BYTES_MAX: 0x6f,
  BYTES: 0x70,
  STRING: 0x71,
  STATIC_ARRAY: 0x80,
  DYNAMIC_ARRAY: 0x81,
  TUPLE: 0x90,
} as const satisfies Record<string, number>;

///////////////////////////////////////////////////////////////////////////
// Context property IDs
///////////////////////////////////////////////////////////////////////////

// oxfmt-ignore
const CTX_PROPERTY_TABLE = [
  { key: "MSG_SENDER", code: 0x0000, label: "msg.sender", contextKey: "msgSender", typeCode: TypeCode.ADDRESS },
  { key: "MSG_VALUE", code: 0x0001, label: "msg.value", contextKey: "msgValue", typeCode: TypeCode.UINT_MAX },
  { key: "BLOCK_TIMESTAMP", code: 0x0002, label: "block.timestamp", contextKey: "blockTimestamp", typeCode: TypeCode.UINT_MAX },
  { key: "BLOCK_NUMBER", code: 0x0003, label: "block.number", contextKey: "blockNumber", typeCode: TypeCode.UINT_MAX },
  { key: "CHAIN_ID", code: 0x0004, label: "block.chainid", contextKey: "chainId", typeCode: TypeCode.UINT_MAX },
  { key: "TX_ORIGIN", code: 0x0005, label: "tx.origin", contextKey: "txOrigin", typeCode: TypeCode.ADDRESS },
  { key: "BASE_FEE", code: 0x0006, label: "block.basefee", contextKey: "baseFee", typeCode: TypeCode.UINT_MAX },
  { key: "GAS_PRICE", code: 0x0007, label: "tx.gasprice", contextKey: "gasPrice", typeCode: TypeCode.UINT_MAX },
] as const;

/** Well-known context property IDs for context-scope rules. */
export const ContextProperty = buildCodeMap(CTX_PROPERTY_TABLE);

/** Maximum valid context property ID. */
export const MAX_CONTEXT_PROPERTY_ID = Math.max(...CTX_PROPERTY_TABLE.map((e) => e.code));

/** Display metadata for a context property code. */
export type ContextPropertyInfo = { label: string; contextKey: keyof import("./types").Context; typeCode: number };

const ctxPropertyByCode: ReadonlyMap<number, ContextPropertyInfo> = new Map<number, ContextPropertyInfo>(
  CTX_PROPERTY_TABLE.map((e) => [e.code, { label: e.label, contextKey: e.contextKey, typeCode: e.typeCode }]),
);

/**
 * Map a context property code to its display label and ABI type code.
 * @param code - Context property ID.
 * @returns Display metadata including the ABI type code for the property value.
 * @throws {CallciumError} If the code is not a recognised context property.
 */
export function lookupContextProperty(code: number): ContextPropertyInfo {
  const info = ctxPropertyByCode.get(code);
  if (!info) throw new CallciumError("UNKNOWN_CONTEXT_PROPERTY", `Unknown context property ${code}`);
  return info;
}

///////////////////////////////////////////////////////////////////////////
// Operator codes
///////////////////////////////////////////////////////////////////////////

/** Operand count category for operator data validation. */
export type Operands = "single" | "range" | "variadic";

/** @internal */
const OP_TABLE = [
  { key: "EQ", code: 0x01, label: "==", operands: "single" },
  { key: "GT", code: 0x02, label: ">", operands: "single" },
  { key: "LT", code: 0x03, label: "<", operands: "single" },
  { key: "GTE", code: 0x04, label: ">=", operands: "single" },
  { key: "LTE", code: 0x05, label: "<=", operands: "single" },
  { key: "BETWEEN", code: 0x06, label: "between", operands: "range" },
  { key: "IN", code: 0x07, label: "in", operands: "variadic" },
  { key: "EQ_CTX", code: 0x08, label: "== ctx", operands: "single" },
  { key: "BITMASK_ALL", code: 0x10, label: "bitmask all", operands: "single" },
  { key: "BITMASK_ANY", code: 0x11, label: "bitmask any", operands: "single" },
  { key: "BITMASK_NONE", code: 0x12, label: "bitmask none", operands: "single" },
  { key: "LENGTH_EQ", code: 0x20, label: "length ==", operands: "single" },
  { key: "LENGTH_GT", code: 0x21, label: "length >", operands: "single" },
  { key: "LENGTH_LT", code: 0x22, label: "length <", operands: "single" },
  { key: "LENGTH_GTE", code: 0x23, label: "length >=", operands: "single" },
  { key: "LENGTH_LTE", code: 0x24, label: "length <=", operands: "single" },
  { key: "LENGTH_BETWEEN", code: 0x25, label: "length between", operands: "range" },
] as const;

/** Callcium policy operator codes. */
export const Op: CodeMap<typeof OP_TABLE> & { readonly NOT: 0x80 } = { ...buildCodeMap(OP_TABLE), NOT: 0x80 };

/** Display metadata for an operator code. */
export type OpInfo = { label: string; operands: Operands };

const opByCode: ReadonlyMap<number, OpInfo> = new Map<number, OpInfo>(
  OP_TABLE.map((e) => [e.code, { label: e.label, operands: e.operands }]),
);

/**
 * Map an operator code to its display label. Strips the NOT flag automatically.
 * @param code - Operator byte value (may include the NOT flag).
 * @returns Display metadata for the base operator.
 * @throws {CallciumError} If the base code is not a recognised operator.
 */
export function lookupOp(code: number): OpInfo {
  const base = code & ~Op.NOT;
  const info = opByCode.get(base);
  if (!info)
    throw new CallciumError("UNKNOWN_OPERATOR", `Unknown operator code 0x${base.toString(16).padStart(2, "0")}`);
  return info;
}

/** Operand count category for an operator code, or undefined when unrecognised. */
export function operandsOf(opBase: number): Operands | undefined {
  return opByCode.get(opBase)?.operands;
}

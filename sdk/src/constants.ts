import { CallciumError } from "./errors";

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
//                        Table-derived helpers
///////////////////////////////////////////////////////////////////////////

/** Extract a `{ KEY: code }` map from a table with `key` and `code` fields. */
type CodeMap<T extends readonly { readonly key: string; readonly code: number }[]> = {
  readonly [E in T[number] as E["key"]]: E["code"];
};

/** Build a plain `{ KEY: code }` object from a table at runtime. */
function buildCodeMap<T extends readonly { readonly key: string; readonly code: number }[]>(table: T): CodeMap<T> {
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- derived from the same const table that defines the type.
  return Object.fromEntries(table.map((e) => [e.key, e.code])) as CodeMap<T>;
}

///////////////////////////////////////////////////////////////////////////
//                               Scope codes
///////////////////////////////////////////////////////////////////////////

const SCOPE_TABLE = [
  { key: "CONTEXT", code: 0x00, label: "context" },
  { key: "CALLDATA", code: 0x01, label: "calldata" },
] as const;

/** Rule scope discriminant: context (EVM environment) vs. calldata (ABI payload). */
export const Scope = buildCodeMap(SCOPE_TABLE);

/** Display metadata for a scope code. */
export type ScopeInfo = { label: string };

const scopeByCode = new Map<number, ScopeInfo>(SCOPE_TABLE.map((e) => [e.code, { label: e.label }]));

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
//                        Context property IDs
///////////////////////////////////////////////////////////////////////////

const CTX_PROP_TABLE = [
  { key: "MSG_SENDER", code: 0x0000, label: "msg.sender", typeCode: 0x40 },
  { key: "MSG_VALUE", code: 0x0001, label: "msg.value", typeCode: 0x1f },
  { key: "BLOCK_TIMESTAMP", code: 0x0002, label: "block.timestamp", typeCode: 0x1f },
  { key: "BLOCK_NUMBER", code: 0x0003, label: "block.number", typeCode: 0x1f },
  { key: "CHAIN_ID", code: 0x0004, label: "block.chainid", typeCode: 0x1f },
  { key: "TX_ORIGIN", code: 0x0005, label: "tx.origin", typeCode: 0x40 },
] as const;

/** Well-known context property IDs for context-scope rules. */
export const ContextProperty = buildCodeMap(CTX_PROP_TABLE);

/** Maximum valid context property ID. */
export const MAX_CONTEXT_PROPERTY_ID = Math.max(...CTX_PROP_TABLE.map((e) => e.code));

/** Display metadata for a context property code. */
export type ContextPropertyInfo = { label: string; typeCode: number };

const ctxPropByCode = new Map<number, ContextPropertyInfo>(
  CTX_PROP_TABLE.map((e) => [e.code, { label: e.label, typeCode: e.typeCode }]),
);

/**
 * Map a context property code to its display label and ABI type code.
 * @param code - Context property ID.
 * @returns Display metadata including the Solidity type code for the property value.
 * @throws {CallciumError} If the code is not a recognised context property.
 */
export function lookupContextProperty(code: number): ContextPropertyInfo {
  const info = ctxPropByCode.get(code);
  if (!info) throw new CallciumError("INVALID_CONTEXT_PROPERTY", `Unknown context property ${code}`);
  return info;
}

///////////////////////////////////////////////////////////////////////////
//                          Protocol limits
///////////////////////////////////////////////////////////////////////////

/** Protocol-imposed safety limits for path depth and quantifier array size. */
export const Limits = {
  MAX_PATH_DEPTH: 32,
  MAX_QUANTIFIED_ARRAY_LENGTH: 256,
} as const satisfies Record<string, number>;

///////////////////////////////////////////////////////////////////////////
//                           Operator codes
///////////////////////////////////////////////////////////////////////////

/** Operand count category for operator data validation. */
export type Operands = "single" | "range" | "variadic";

const OP_TABLE = [
  { key: "EQ", code: 0x01, label: "==", operands: "single" },
  { key: "GT", code: 0x02, label: ">", operands: "single" },
  { key: "LT", code: 0x03, label: "<", operands: "single" },
  { key: "GTE", code: 0x04, label: ">=", operands: "single" },
  { key: "LTE", code: 0x05, label: "<=", operands: "single" },
  { key: "BETWEEN", code: 0x06, label: "between", operands: "range" },
  { key: "IN", code: 0x07, label: "in", operands: "variadic" },
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

const opByCode = new Map<number, OpInfo>(OP_TABLE.map((e) => [e.code, { label: e.label, operands: e.operands }]));

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
    throw new CallciumError("INVALID_OPERATOR", `Unknown operator code 0x${base.toString(16).padStart(2, "0")}`);
  return info;
}

const operandsByCode = new Map<number, Operands>(OP_TABLE.map((e) => [e.code, e.operands]));

/**
 * Check whether an operator's data payload has the correct length.
 * @param opBase - Base operator code with the NOT flag stripped.
 * @param dataLength - Byte length of the operator's data payload.
 * @returns True if the data length is valid for the given operator.
 */
export function isValidOperatorData(opBase: number, dataLength: number): boolean {
  const operands = operandsByCode.get(opBase);
  if (operands === "single") return dataLength === 32;
  if (operands === "range") return dataLength === 64;
  if (operands === "variadic") return dataLength > 0 && dataLength % 32 === 0;
  return false;
}

///////////////////////////////////////////////////////////////////////////
//                          Quantifier steps
///////////////////////////////////////////////////////////////////////////

const QUANTIFIER_TABLE = [
  { key: "ALL_OR_EMPTY", code: 0xffff, label: "all or empty" },
  { key: "ALL", code: 0xfffe, label: "all" },
  { key: "ANY", code: 0xfffd, label: "any" },
] as const;

/** Reserved path step values that trigger quantified evaluation over array elements. */
export const Quantifier = buildCodeMap(QUANTIFIER_TABLE);

/** Display metadata for a quantifier step. */
export type QuantifierInfo = { label: string };

const quantifierByCode = new Map<number, QuantifierInfo>(QUANTIFIER_TABLE.map((e) => [e.code, { label: e.label }]));

/**
 * Map a quantifier path step to its display label.
 * @param code - Quantifier step value.
 * @returns Display metadata for the quantifier.
 * @throws {CallciumError} If the code is not a recognised quantifier.
 */
export function lookupQuantifier(code: number): QuantifierInfo {
  const info = quantifierByCode.get(code);
  if (!info) throw new CallciumError("INVALID_QUANTIFIER", `Unknown quantifier step 0x${code.toString(16)}`);
  return info;
}

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

/** Structural category for a descriptor type code. */
export type TypeClass = "elementary" | "tuple" | "staticArray" | "dynamicArray";

/** Structural classification without label — used by the decoder hot path. */
export type TypeClassInfo = { typeClass: TypeClass; isDynamic: boolean };

/** Display metadata for a descriptor type code. */
export type TypeCodeInfo = TypeClassInfo & { label: string };

/** Throw an UNKNOWN_TYPE_CODE error. */
function unknownTypeCode(code: number): never {
  throw new CallciumError("UNKNOWN_TYPE_CODE", `Unknown type code 0x${code.toString(16).padStart(2, "0")}`);
}

// Pre-allocated constant objects for fixed type codes (avoids per-call allocation).
const ELEMENTARY = { typeClass: "elementary", isDynamic: false } as const;
const ELEMENTARY_DYN = { typeClass: "elementary", isDynamic: true } as const;
const STATIC_ARR = { typeClass: "staticArray", isDynamic: false } as const;
const DYNAMIC_ARR = { typeClass: "dynamicArray", isDynamic: true } as const;
const TUPLE = { typeClass: "tuple", isDynamic: false } as const;

/**
 * Classify a type code into its structural category and dynamism.
 * Lightweight variant of `lookupTypeCode` that skips label computation.
 * @param code - A single-byte descriptor type code.
 * @returns Type class and whether the type is ABI-dynamic.
 * @throws {CallciumError} If the code is not a recognised type code.
 */
export function classifyTypeCode(code: number): TypeClassInfo {
  if (code >= TypeCode.UINT_MIN && code <= TypeCode.UINT_MAX) return ELEMENTARY;
  if (code >= TypeCode.INT_MIN && code <= TypeCode.INT_MAX) return ELEMENTARY;
  if (code === TypeCode.ADDRESS || code === TypeCode.BOOL || code === TypeCode.FUNCTION) return ELEMENTARY;
  if (code >= 0x43 && code <= 0x4f) unknownTypeCode(code);
  if (code >= TypeCode.FIXED_BYTES_MIN && code <= TypeCode.FIXED_BYTES_MAX) return ELEMENTARY;
  if (code === TypeCode.BYTES || code === TypeCode.STRING) return ELEMENTARY_DYN;
  if (code >= 0x72 && code <= 0x7f) unknownTypeCode(code);
  if (code === TypeCode.STATIC_ARRAY) return STATIC_ARR;
  if (code === TypeCode.DYNAMIC_ARRAY) return DYNAMIC_ARR;
  if (code >= 0x82 && code <= 0x8f) unknownTypeCode(code);
  if (code === TypeCode.TUPLE) return TUPLE;
  unknownTypeCode(code);
}

/** Compute the Solidity type label for a type code. */
function typeCodeLabel(code: number): string {
  if (code >= TypeCode.UINT_MIN && code <= TypeCode.UINT_MAX) return `uint${(code - TypeCode.UINT_MIN + 1) * 8}`;
  if (code >= TypeCode.INT_MIN && code <= TypeCode.INT_MAX) return `int${(code - TypeCode.INT_MIN + 1) * 8}`;
  if (code === TypeCode.ADDRESS) return "address";
  if (code === TypeCode.BOOL) return "bool";
  if (code === TypeCode.FUNCTION) return "function";
  if (code >= TypeCode.FIXED_BYTES_MIN && code <= TypeCode.FIXED_BYTES_MAX)
    return `bytes${code - TypeCode.FIXED_BYTES_MIN + 1}`;
  if (code === TypeCode.BYTES) return "bytes";
  if (code === TypeCode.STRING) return "string";
  if (code === TypeCode.STATIC_ARRAY) return "T[k]";
  if (code === TypeCode.DYNAMIC_ARRAY) return "T[]";
  if (code === TypeCode.TUPLE) return "tuple";
  return `0x${code.toString(16).padStart(2, "0")}`;
}

/**
 * Map a raw type code byte to its Solidity label, structural category, and dynamism.
 * @param code - A single-byte descriptor type code.
 * @returns Label, type class, and whether the type is ABI-dynamic.
 * @throws {CallciumError} If the code is not a recognised type code.
 */
export function lookupTypeCode(code: number): TypeCodeInfo {
  return { label: typeCodeLabel(code), ...classifyTypeCode(code) };
}

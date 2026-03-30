///////////////////////////////////////////////////////////////////////////
//                              Primitives
///////////////////////////////////////////////////////////////////////////

/** Hex-encoded byte string, 0x-prefixed. */
export type Hex = `0x${string}`;

/** Ethereum address, 0x-prefixed. */
export type Address = `0x${string}`;

/** Generic result type for operations that can fail with a violation code. */
export type Result<T> = ({ ok: true } & T) | { ok: false; code: ViolationCode };

/** Byte range in a source blob. */
export type Span = { start: number; end: number };

/** A decoded value with its byte position in the source blob. */
export type Field<T> = { value: T; span: Span };

///////////////////////////////////////////////////////////////////////////
//           Descriptor AST (internal — not exported from index.ts)
///////////////////////////////////////////////////////////////////////////

/** Shared properties for all descriptor node variants. */
type DescNodeBase = {
  typeCode: number;
  isDynamic: boolean;
  /** ABI head size in bytes; 0 if dynamic. */
  staticSize: number;
  /** Byte range in the descriptor blob. Present after decoding. */
  span?: Span;
};

export type ElementaryNode = DescNodeBase & { type: "elementary" };

export type TupleNode = DescNodeBase & {
  type: "tuple";
  /** Tuple field descriptors, in declaration order. */
  fields: DescNode[];
};

export type StaticArrayNode = DescNodeBase & {
  type: "staticArray";
  /** The element type descriptor. */
  element: DescNode;
  /** Fixed number of elements declared in the type. */
  length: number;
};

export type DynamicArrayNode = DescNodeBase & {
  type: "dynamicArray";
  /** The element type descriptor. */
  element: DescNode;
};

/** Recursive AST node representing one type in a descriptor tree. */
export type DescNode = ElementaryNode | TupleNode | StaticArrayNode | DynamicArrayNode;

///////////////////////////////////////////////////////////////////////////
//                          Decoded structures
///////////////////////////////////////////////////////////////////////////

export type DecodedParam = {
  index: number;
  typeCode: number;
  isDynamic: boolean;
  staticSize: number;
  /** Parameter index encoded as a big-endian uint16 hex string. */
  path: Hex;
  span: Span;
};

export type DecodedDescriptor = {
  version: number;
  params: DecodedParam[];
};

export type DecodedRule = {
  scope: Field<number>;
  path: Field<Hex>;
  opCode: Field<number>;
  data: Field<Hex>;
  span: Span;
};

export type DecodedGroup = {
  rules: DecodedRule[];
  span: Span;
};

export type DecodedPolicy = {
  header: Field<number>;
  selector: Field<Hex>;
  descriptor: { raw: Hex; params: DecodedParam[]; span: Span };
  groups: DecodedGroup[];
  span: Span;
  version: number;
  isSelectorless: boolean;
};

///////////////////////////////////////////////////////////////////////////
//                               Enforce
///////////////////////////////////////////////////////////////////////////

/**
 * Execution context for context-scoped rules.
 * Each property maps to a well-known EVM execution environment value.
 * Only the properties referenced by the policy need to be supplied.
 */
export type Context = {
  msgSender?: Address;
  msgValue?: bigint;
  blockTimestamp?: bigint;
  blockNumber?: bigint;
  chainId?: bigint;
  txOrigin?: Address;
};

/** Result of enforcing a policy: pass with matched group index, or fail with one violation per failed group. */
export type EnforceResult = { ok: true; matchedGroup: number } | { ok: false; violations: Violation[] };

/** Machine-readable reason code for an enforcement violation. */
export type ViolationCode =
  | "VALUE_MISMATCH"
  | "SELECTOR_MISMATCH"
  | "MISSING_CONTEXT"
  | "CALLDATA_TOO_SHORT"
  | "OFFSET_OUT_OF_BOUNDS"
  | "QUANTIFIER_EMPTY_ARRAY"
  | "QUANTIFIER_LIMIT_EXCEEDED";

/** Details of a single rule failure during enforcement. */
export type Violation = {
  /** Group index that failed. Absent for pre-group failures (e.g. selector mismatch). */
  group?: number;
  /** Rule index within the group. Absent for pre-rule failures. */
  rule?: number;
  code: ViolationCode;
  message: string;
  /** Rule path that was being evaluated when the violation occurred. */
  path?: Hex;
  /** The actual value found in calldata or context, for diagnostic display. */
  resolvedValue?: Hex;
};

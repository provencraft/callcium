import { bytesToHex, hexToBytes, toAddress } from "./bytes";
import { PolicyFormat, Op, Scope, ContextProperty, MAX_CONTEXT_PROPERTY_ID } from "./constants";
import { CallciumError } from "./errors";
import { encodePath } from "./path";

import type { Address, Hex, Constraint } from "./types";

///////////////////////////////////////////////////////////////////////////
// Value encoding helpers
///////////////////////////////////////////////////////////////////////////

/** Accepted scalar value types for operator arguments. */
export type ScalarValue = bigint | number | boolean | string;

// Bounds of the integers a 32-byte operand word represents, spanning signed and unsigned targets.
const OPERAND_MIN = -(2n ** 255n);
const OPERAND_MAX = 2n ** 256n - 1n;

/**
 * Narrow a numeric operand to the integers a 32-byte word represents.
 * @throws {CallciumError} When a number carries no exact integer value, or the integer lies outside
 * the word's range.
 */
function toOperandValue(value: bigint | number): bigint {
  if (typeof value === "number" && !Number.isSafeInteger(value)) {
    throw new CallciumError("MALFORMED_OPERAND", `Operand must be a safe integer, got ${value}`);
  }
  const big = BigInt(value);
  if (big < OPERAND_MIN || big > OPERAND_MAX) {
    throw new CallciumError("OPERAND_OVERFLOW", `Operand ${big} is outside the range a 32-byte word represents`);
  }
  return big;
}

/** Strip an optional 0x prefix and validate a 40-hex-char (20-byte) address body. */
function addressBody(value: string): string {
  return toAddress(value).slice(2);
}

/** Convert a scalar value to a 32-byte big-endian word. */
function encodeWord(value: ScalarValue): Uint8Array {
  const word = new Uint8Array(32);

  if (typeof value === "boolean") {
    word[31] = value ? 1 : 0;
    return word;
  }

  if (typeof value === "string") {
    // Address encoding: validate 20-byte hex and right-align into 32 bytes.
    word.set(hexToBytes(addressBody(value)), 12);
    return word;
  }

  // A negative operand occupies the word in two's complement, which is the signed target's encoding.
  let bigValue = toOperandValue(value);
  for (let i = 31; i >= 0; i--) {
    word[i] = Number(bigValue & 0xffn);
    bigValue >>= 8n;
  }
  return word;
}

/** Pack a scalar value as a hex operator payload (opCode byte + 32-byte word). */
function singleOp(opCode: number, value: ScalarValue): Hex {
  const buffer = new Uint8Array(33);
  buffer[0] = opCode;
  buffer.set(encodeWord(value), 1);
  return bytesToHex(buffer);
}

/** Pack a range operator (opCode byte + min word + max word). */
function rangeOp(opCode: number, min: bigint | number, max: bigint | number): Hex {
  // Order compares the operands as written; the encoded words of a signed range run the other way.
  const minValue = toOperandValue(min);
  const maxValue = toOperandValue(max);
  if (minValue > maxValue) {
    throw new CallciumError("INVALID_RANGE", `Range min (${minValue}) must not exceed max (${maxValue})`);
  }
  const buffer = new Uint8Array(65);
  buffer[0] = opCode;
  buffer.set(encodeWord(minValue), 1);
  buffer.set(encodeWord(maxValue), 33);
  return bytesToHex(buffer);
}

/** Require a defined context property ID and return it. */
function checkContextPropertyId(contextPropertyId: number): number {
  if (!Number.isInteger(contextPropertyId) || contextPropertyId < 0 || contextPropertyId > MAX_CONTEXT_PROPERTY_ID) {
    throw new CallciumError(
      "UNKNOWN_CONTEXT_PROPERTY",
      `Unknown context property ID 0x${contextPropertyId.toString(16).padStart(4, "0")}`,
    );
  }
  return contextPropertyId;
}

/** Convert values to bigint, sort ascending (unsigned), deduplicate, and pack as set payload. */
function setOp(opCode: number, values: readonly ScalarValue[]): Hex {
  // PWF-21 orders members by their 32-byte encodings, so a negative operand and its unsigned
  // alias are one member at one position. Normalising after the domain check keeps an
  // out-of-range value an error rather than folding it into the word.
  const words = values.map((value) => {
    if (typeof value === "bigint" || typeof value === "number") return BigInt.asUintN(256, toOperandValue(value));
    if (typeof value === "boolean") return value ? 1n : 0n;
    // String address.
    return BigInt("0x" + addressBody(value));
  });

  const deduped = [...new Set(words)].toSorted((a, b) => (a < b ? -1 : a > b ? 1 : 0));

  if (deduped.length === 0) {
    throw new CallciumError("EMPTY_SET", "Set must contain at least one value");
  }
  if (deduped.length > PolicyFormat.MAX_SET_MEMBERS) {
    throw new CallciumError("SET_TOO_LARGE", `Set must contain at most ${PolicyFormat.MAX_SET_MEMBERS} values`);
  }

  const buffer = new Uint8Array(1 + deduped.length * 32);
  buffer[0] = opCode;
  for (let i = 0; i < deduped.length; i++) {
    buffer.set(encodeWord(deduped[i]!), 1 + i * 32);
  }
  return bytesToHex(buffer);
}

///////////////////////////////////////////////////////////////////////////
// Operand provenance
///////////////////////////////////////////////////////////////////////////

/**
 * Extremes of the numeric operands a builder's value operators received, as written. Encoding folds
 * a negative operand onto its unsigned alias, so the sign survives nowhere else.
 */
export type OperandExtremes = {
  /** Most negative operand written, or zero when none was negative. */
  leastNegative: bigint;
  /** Greatest operand written, or zero when none exceeded it. */
  greatest: bigint;
};

/**
 * Extremes of the numeric operands the value operators of `constraint` received, as written.
 * They outlive edits to `operators`: removing an operator does not remove what was written to
 * produce it, and a fresh builder starts at zero. Undefined for a plain `Constraint`, whose
 * operators arrive already encoded.
 */
export function readOperandExtremes(constraint: Constraint | ConstraintBuilder): OperandExtremes | undefined {
  return "operandExtremes" in constraint ? constraint.operandExtremes : undefined;
}

///////////////////////////////////////////////////////////////////////////
// ConstraintBuilder
///////////////////////////////////////////////////////////////////////////

/**
 * Mutable builder that accumulates operators targeting a single path.
 * Implements the `Constraint` interface so it can be passed directly to policy builders.
 */
export class ConstraintBuilder<Operand extends ScalarValue = ScalarValue> implements Constraint {
  readonly scope: number;
  readonly path: Hex;
  readonly operators: Hex[];
  /**
   * Extremes of the numeric operands the value operators received, as written. Only the extremes
   * can offend: an operand folds into a target's range from below it or from above it, and
   * whichever reaches furthest arrives first. Read it through {@link readOperandExtremes}.
   * @internal
   */
  readonly operandExtremes: OperandExtremes;

  /** @internal */
  constructor(scope: number, path: Hex) {
    this.scope = scope;
    this.path = path;
    this.operators = [];
    this.operandExtremes = { leastNegative: 0n, greatest: 0n };
  }

  /**
   * Push a pre-encoded operator hex string and return this for chaining.
   * `values` are the operands as written; the numeric ones join the record.
   */
  private push(opHex: Hex, values: readonly ScalarValue[] = []): this {
    for (const value of values) {
      if (typeof value !== "bigint" && typeof value !== "number") continue;
      const written = BigInt(value);
      if (written < this.operandExtremes.leastNegative) this.operandExtremes.leastNegative = written;
      if (written > this.operandExtremes.greatest) this.operandExtremes.greatest = written;
    }
    this.operators.push(opHex);
    return this;
  }

  ///////////////////////////////////////////////////////////////////////////
  // Value operators
  ///////////////////////////////////////////////////////////////////////////

  /** Assert the value equals `value`. */
  eq(value: Operand): this {
    return this.push(singleOp(Op.EQ, value), [value]);
  }

  /** Assert the value does not equal `value`. */
  neq(value: Operand): this {
    return this.push(singleOp(Op.EQ | Op.NOT, value), [value]);
  }

  /** Assert the value equals the context property `contextPropertyId`. */
  eqCtx(contextPropertyId: number): this {
    return this.push(singleOp(Op.EQ_CTX, checkContextPropertyId(contextPropertyId)));
  }

  /** Assert the value does not equal the context property `contextPropertyId`. */
  neqCtx(contextPropertyId: number): this {
    return this.push(singleOp(Op.EQ_CTX | Op.NOT, checkContextPropertyId(contextPropertyId)));
  }

  /** Assert the value is greater than `bound`. */
  gt(bound: bigint | number): this {
    return this.push(singleOp(Op.GT, bound), [bound]);
  }

  /** Assert the value is less than `bound`. */
  lt(bound: bigint | number): this {
    return this.push(singleOp(Op.LT, bound), [bound]);
  }

  /** Assert the value is greater than or equal to `bound`. */
  gte(bound: bigint | number): this {
    return this.push(singleOp(Op.GTE, bound), [bound]);
  }

  /** Assert the value is less than or equal to `bound`. */
  lte(bound: bigint | number): this {
    return this.push(singleOp(Op.LTE, bound), [bound]);
  }

  /**
   * Assert the value is within [min, max] inclusive.
   * @throws {CallciumError} If min > max.
   */
  between(min: bigint | number, max: bigint | number): this {
    return this.push(rangeOp(Op.BETWEEN, min, max), [min, max]);
  }

  ///////////////////////////////////////////////////////////////////////////
  // Set membership
  ///////////////////////////////////////////////////////////////////////////

  /**
   * Assert the value is a member of the set.
   * Values are sorted and deduplicated before encoding.
   * @throws {CallciumError} If the set is empty after deduplication.
   */
  isIn(values: readonly Operand[]): this {
    return this.push(setOp(Op.IN, values), values);
  }

  /**
   * Assert the value is not a member of the set.
   * @throws {CallciumError} If the set is empty after deduplication.
   */
  notIn(values: readonly Operand[]): this {
    return this.push(setOp(Op.IN | Op.NOT, values), values);
  }

  ///////////////////////////////////////////////////////////////////////////
  // Bitmask operators
  ///////////////////////////////////////////////////////////////////////////

  /** Assert all bits in `mask` are set. */
  bitmaskAll(mask: bigint): this {
    return this.push(singleOp(Op.BITMASK_ALL, mask));
  }

  /** Assert at least one bit in `mask` is set. */
  bitmaskAny(mask: bigint): this {
    return this.push(singleOp(Op.BITMASK_ANY, mask));
  }

  /** Assert no bit in `mask` is set. */
  bitmaskNone(mask: bigint): this {
    return this.push(singleOp(Op.BITMASK_NONE, mask));
  }

  ///////////////////////////////////////////////////////////////////////////
  // Length operators
  ///////////////////////////////////////////////////////////////////////////

  /** Assert the runtime length equals `length`. */
  lengthEq(length: bigint | number): this {
    return this.push(singleOp(Op.LENGTH_EQ, length));
  }

  /** Assert the runtime length is greater than `length`. */
  lengthGt(length: bigint | number): this {
    return this.push(singleOp(Op.LENGTH_GT, length));
  }

  /** Assert the runtime length is less than `length`. */
  lengthLt(length: bigint | number): this {
    return this.push(singleOp(Op.LENGTH_LT, length));
  }

  /** Assert the runtime length is greater than or equal to `length`. */
  lengthGte(length: bigint | number): this {
    return this.push(singleOp(Op.LENGTH_GTE, length));
  }

  /** Assert the runtime length is less than or equal to `length`. */
  lengthLte(length: bigint | number): this {
    return this.push(singleOp(Op.LENGTH_LTE, length));
  }

  /**
   * Assert the runtime length is within [min, max] inclusive.
   * @throws {CallciumError} If min > max.
   */
  lengthBetween(min: bigint | number, max: bigint | number): this {
    return this.push(rangeOp(Op.LENGTH_BETWEEN, min, max));
  }
}

///////////////////////////////////////////////////////////////////////////
// Target factories
///////////////////////////////////////////////////////////////////////////

/**
 * Target a calldata argument by path.
 * Each argument is a big-endian uint16 step; multiple steps navigate into nested types.
 */
export function arg(p0: number, ...rest: number[]): ConstraintBuilder;
export function arg(...steps: number[]): ConstraintBuilder {
  return new ConstraintBuilder(Scope.CALLDATA, encodePath(steps));
}

/** Target the `msg.sender` context property. */
export function msgSender(): ConstraintBuilder<Address> {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.MSG_SENDER]));
}

/** Target the `msg.value` context property. */
export function msgValue(): ConstraintBuilder<bigint> {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.MSG_VALUE]));
}

/** Target the `block.timestamp` context property. */
export function blockTimestamp(): ConstraintBuilder<bigint> {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.BLOCK_TIMESTAMP]));
}

/** Target the `block.number` context property. */
export function blockNumber(): ConstraintBuilder<bigint> {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.BLOCK_NUMBER]));
}

/** Target the `block.chainid` context property. */
export function chainId(): ConstraintBuilder<bigint> {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.CHAIN_ID]));
}

/** Target the `tx.origin` context property. */
export function txOrigin(): ConstraintBuilder<Address> {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.TX_ORIGIN]));
}

/** Target the `block.basefee` context property. */
export function baseFee(): ConstraintBuilder<bigint> {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.BASE_FEE]));
}

/** Target the `tx.gasprice` context property. */
export function gasPrice(): ConstraintBuilder<bigint> {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.GAS_PRICE]));
}

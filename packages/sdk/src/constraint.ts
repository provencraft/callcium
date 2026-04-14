import { bytesToHex, writeBE16 } from "./bytes";
import { Op, Scope, ContextProperty } from "./constants";
import { CallciumError } from "./errors";

import type { Hex, Constraint } from "./types";

///////////////////////////////////////////////////////////////////////////
// Value encoding helpers
///////////////////////////////////////////////////////////////////////////

/** Accepted scalar value types for operator arguments. */
export type ScalarValue = bigint | number | boolean | string;

/** Convert a scalar value to a 32-byte big-endian word. */
function encodeWord(value: ScalarValue): Uint8Array {
  const word = new Uint8Array(32);

  if (typeof value === "boolean") {
    word[31] = value ? 1 : 0;
    return word;
  }

  if (typeof value === "string") {
    // Address encoding: validate 20-byte hex and right-align into 32 bytes.
    const body = value.startsWith("0x") ? value.slice(2) : value;
    if (body.length !== 40) {
      throw new CallciumError(
        "INVALID_CONSTRAINT",
        `Invalid address length: expected 40 hex chars, got ${body.length}`,
      );
    }
    for (let i = 0; i < 20; i++) {
      const byte = parseInt(body.substring(i * 2, i * 2 + 2), 16);
      if (Number.isNaN(byte)) {
        throw new CallciumError("INVALID_CONSTRAINT", `Invalid hex character in address at position ${i * 2}`);
      }
      word[12 + i] = byte;
    }
    return word;
  }

  // bigint | number — unsigned 256-bit big-endian.
  let bigValue = typeof value === "number" ? BigInt(value) : value;
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
function rangeOp(opCode: number, min: bigint, max: bigint): Hex {
  if (min > max) {
    throw new CallciumError("INVALID_RANGE", `Range min (${min}) must not exceed max (${max})`);
  }
  const buffer = new Uint8Array(65);
  buffer[0] = opCode;
  buffer.set(encodeWord(min), 1);
  buffer.set(encodeWord(max), 33);
  return bytesToHex(buffer);
}

/** Convert values to bigint, sort ascending (unsigned), deduplicate, and pack as set payload. */
function setOp(opCode: number, values: readonly ScalarValue[]): Hex {
  const bigs = values.map((v) => {
    if (typeof v === "bigint") return v;
    if (typeof v === "number") return BigInt(v);
    if (typeof v === "boolean") return v ? 1n : 0n;
    // String address.
    const body = v.startsWith("0x") ? v.slice(2) : v;
    return BigInt("0x" + (body || "0"));
  });

  bigs.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

  const deduped: bigint[] = [];
  for (const value of bigs) {
    if (deduped.length === 0 || deduped[deduped.length - 1] !== value) {
      deduped.push(value);
    }
  }

  if (deduped.length === 0) {
    throw new CallciumError("EMPTY_SET", "Set must contain at least one value");
  }

  const buffer = new Uint8Array(1 + deduped.length * 32);
  buffer[0] = opCode;
  for (let i = 0; i < deduped.length; i++) {
    buffer.set(encodeWord(deduped[i]!), 1 + i * 32);
  }
  return bytesToHex(buffer);
}

///////////////////////////////////////////////////////////////////////////
// Path encoding
///////////////////////////////////////////////////////////////////////////

/** Encode a sequence of uint16 path steps as a big-endian hex string. */
function encodePath(steps: readonly number[]): Hex {
  const buffer = new Uint8Array(steps.length * 2);
  for (let i = 0; i < steps.length; i++) {
    writeBE16(buffer, i * 2, steps[i]!);
  }
  return bytesToHex(buffer);
}

///////////////////////////////////////////////////////////////////////////
// ConstraintBuilder
///////////////////////////////////////////////////////////////////////////

/**
 * Mutable builder that accumulates operators targeting a single path.
 * Implements the `Constraint` interface so it can be passed directly to policy builders.
 */
export class ConstraintBuilder implements Constraint {
  readonly scope: number;
  readonly path: Hex;
  readonly operators: Hex[];

  /** @internal */
  constructor(scope: number, path: Hex) {
    this.scope = scope;
    this.path = path;
    this.operators = [];
  }

  /** Push a pre-encoded operator hex string and return this for chaining. */
  private push(opHex: Hex): this {
    this.operators.push(opHex);
    return this;
  }

  ///////////////////////////////////////////////////////////////////////////
  // Value operators
  ///////////////////////////////////////////////////////////////////////////

  /** Assert the value equals `value`. */
  eq(value: ScalarValue): this {
    return this.push(singleOp(Op.EQ, value));
  }

  /** Assert the value does not equal `value`. */
  neq(value: ScalarValue): this {
    return this.push(singleOp(Op.EQ | Op.NOT, value));
  }

  /** Assert the value is greater than `bound`. */
  gt(bound: bigint | number): this {
    return this.push(singleOp(Op.GT, bound));
  }

  /** Assert the value is less than `bound`. */
  lt(bound: bigint | number): this {
    return this.push(singleOp(Op.LT, bound));
  }

  /** Assert the value is greater than or equal to `bound`. */
  gte(bound: bigint | number): this {
    return this.push(singleOp(Op.GTE, bound));
  }

  /** Assert the value is less than or equal to `bound`. */
  lte(bound: bigint | number): this {
    return this.push(singleOp(Op.LTE, bound));
  }

  /**
   * Assert the value is within [min, max] inclusive.
   * @throws {CallciumError} If min > max.
   */
  between(min: bigint | number, max: bigint | number): this {
    return this.push(rangeOp(Op.BETWEEN, BigInt(min), BigInt(max)));
  }

  ///////////////////////////////////////////////////////////////////////////
  // Set membership
  ///////////////////////////////////////////////////////////////////////////

  /**
   * Assert the value is a member of the set.
   * Values are sorted and deduplicated before encoding.
   * @throws {CallciumError} If the set is empty after deduplication.
   */
  isIn(values: readonly ScalarValue[]): this {
    return this.push(setOp(Op.IN, values));
  }

  /**
   * Assert the value is not a member of the set.
   * @throws {CallciumError} If the set is empty after deduplication.
   */
  notIn(values: readonly ScalarValue[]): this {
    return this.push(setOp(Op.IN | Op.NOT, values));
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

  /** Assert the runtime length equals `n`. */
  lengthEq(n: bigint | number): this {
    return this.push(singleOp(Op.LENGTH_EQ, n));
  }

  /** Assert the runtime length is greater than `n`. */
  lengthGt(n: bigint | number): this {
    return this.push(singleOp(Op.LENGTH_GT, n));
  }

  /** Assert the runtime length is less than `n`. */
  lengthLt(n: bigint | number): this {
    return this.push(singleOp(Op.LENGTH_LT, n));
  }

  /** Assert the runtime length is greater than or equal to `n`. */
  lengthGte(n: bigint | number): this {
    return this.push(singleOp(Op.LENGTH_GTE, n));
  }

  /** Assert the runtime length is less than or equal to `n`. */
  lengthLte(n: bigint | number): this {
    return this.push(singleOp(Op.LENGTH_LTE, n));
  }

  /**
   * Assert the runtime length is within [min, max] inclusive.
   * @throws {CallciumError} If min > max.
   */
  lengthBetween(min: bigint | number, max: bigint | number): this {
    return this.push(rangeOp(Op.LENGTH_BETWEEN, BigInt(min), BigInt(max)));
  }
}

///////////////////////////////////////////////////////////////////////////
// Target factories
///////////////////////////////////////////////////////////////////////////

/**
 * Target a calldata argument by path.
 * Each argument is a big-endian uint16 step; multiple steps navigate into nested types.
 */
export function arg(p0: number): ConstraintBuilder;
export function arg(p0: number, p1: number): ConstraintBuilder;
export function arg(p0: number, p1: number, p2: number): ConstraintBuilder;
export function arg(p0: number, p1: number, p2: number, p3: number): ConstraintBuilder;
export function arg(...steps: number[]): ConstraintBuilder {
  return new ConstraintBuilder(Scope.CALLDATA, encodePath(steps));
}

/** Target the `msg.sender` context property. */
export function msgSender(): ConstraintBuilder {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.MSG_SENDER]));
}

/** Target the `msg.value` context property. */
export function msgValue(): ConstraintBuilder {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.MSG_VALUE]));
}

/** Target the `block.timestamp` context property. */
export function blockTimestamp(): ConstraintBuilder {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.BLOCK_TIMESTAMP]));
}

/** Target the `block.number` context property. */
export function blockNumber(): ConstraintBuilder {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.BLOCK_NUMBER]));
}

/** Target the `block.chainid` context property. */
export function chainId(): ConstraintBuilder {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.CHAIN_ID]));
}

/** Target the `tx.origin` context property. */
export function txOrigin(): ConstraintBuilder {
  return new ConstraintBuilder(Scope.CONTEXT, encodePath([ContextProperty.TX_ORIGIN]));
}

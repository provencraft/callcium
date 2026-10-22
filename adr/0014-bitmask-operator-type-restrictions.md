# ADR-0014: Bitmask Operator Type Restrictions

## Status

Accepted.

## Context

`BITMASK_ALL`, `BITMASK_ANY` and `BITMASK_NONE` test the value's bits against a mask (`Comparison.apply`). The value is
the canonical ABI word (ADR-0006). A mask as wide as the type, aligned as the value is (ADR-0013), names the value's own
bits on every static type.

Some protocols keep flags in values of these types. For example, Uniswap v4 encodes a hook's permissions in the lowest
14 bits of the hook's address.

## Decision

**Bitmask comparisons apply to `uintN`, `intN`, `address` and `bytes1` to `bytes32`. Build-time validation rejects
`bool` and `function` targets** (PV-5).

- **Integers and `address`**: a mask names the value's own bits, right-aligned. On `intN`, it reads the two's-complement
  bits, so `0x80` on `int8` is the sign bit.
- **`bytesN`**: a mask names the value's own bytes, left-aligned. `0xFF000000` on `bytes4` is the first byte.
- **`bool` is excluded**: every mask test on it equals `EQ`, its negation or a constant verdict.
- **`function` is excluded until a policy needs it**: to accept it is an addition under a minor (ADR-0003). Its
  exclusion saves its matrix entry and vectors.

## Alternatives Considered

- **`uintN` and `bytes32` only**: rejected. This makes flag tests on addresses, signed fields and short byte strings
  inexpressible, while type-wide masks read their bits as they read `uintN`'s.
- **`uint256` and `bytes32` only**: rejected. Narrower unsigned integers read a mask the same way as `uint256`. To
  exclude them loses flag tests on `uint8` and `uint16` fields.
- **Every static type**: rejected. A mask test on `bool` only respells `EQ` or its negation.

## Consequences

- An author can test flags that an address encodes. For example, `hooks BITMASK_NONE 0x80` forbids a Uniswap v4 hook's
  `beforeSwap` permission. An author can also test chosen bits of `bytes4` selectors and packed fields and ignore the
  other bits.
- A mask on a signed value reads its bits, not its magnitude. `BITMASK_ALL 0x80` on `int8` holds exactly for negative
  values.
- Both build-time validators report `BITMASK_ON_INVALID` for `bool` and `function` targets, and validation vectors pin
  every accepted and rejected type.

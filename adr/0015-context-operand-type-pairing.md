# ADR-0015: Context Operand Type Pairing

## Status

Accepted.

## Context

A comparison with a context source (ADR-0013) compares a target against a context property. Both sides have a declared
type. The property's type is `address` or `uint256`. The operand is a 2-byte property ID whatever the target's type, so
without a type restriction any target would be accepted. A mis-paired rule compares words of different types, and its
verdict follows no type that the author declared.

## Decision

**A context source pairs only with targets whose type agrees with the referenced property's type, and build-time
validation checks the pairing** (PV-5).

- **Any `uintN` target pairs with a `uint256` property, under all five comparisons.** A canonical narrower unsigned
  target is zero-extended (ADR-0006), so the comparison against a full-width property is exact for equality and order
  alike.
- **An `address` target pairs with an `address` property under `EQ` only.** An address is an identity, not a magnitude.
  Ordering an address against `msg.sender` expresses a bound that no author means.
- **Every other target type does not pair.** No context property has another type, so every such pairing is a type error
  that is detectable from the blob.

A context test whose subject is itself a property follows the same rule. The subject property's type is the target's
type.

## Alternatives Considered

- **Any static elementary target**: rejected. A mis-paired rule's verdict follows no declared type, and no calldata
  reveals the mistake.
- **Exact type equality, `uint256` targets only**: rejected. Zero extension makes narrower unsigned targets compare
  exactly. To exclude them removes `uint128` amounts against `msg.value` for no gain in soundness.
- **Checking the pairing at storage**: rejected. The enforcer reads every field of a mis-paired test as the format
  defines it (`Comparison.apply` compares by the target's signedness). So the storage criterion of ADR-0002 does not
  reach it.
- **Type checks in the enforcer**: rejected. The pairing follows from the blob alone, and a check per call inverts the
  tiers of ADR-0002.

## Consequences

- For a mis-paired rule, an author gets `CONTEXT_TYPE_MISMATCH` at build time, in both validators. Validation vectors
  pin it.
- A blob that `buildUnsafe()` built can contain a mis-paired test. The enforcer compares a context source by the
  target's signedness, as the denotation does, and does not rely on the pairing.
- Comparing a `bytes32` or signed target against a context property is inexpressible.
- A context property of another type needs a pairing rule of its own.

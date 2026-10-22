# ADR-0006: Non-Canonical Calldata Rejection

## Status

Accepted.

## Context

An enforcer that compares raw calldata words lets an attacker defeat a rule with bits outside the declared width.
Normalization of each resolved word to its declared type before the comparison closes this attack. It leaves one
question unanswered: is the non-canonical word itself acceptable?

Acceptance is sound only where something guarantees that the consumer observes the same value. Solidity decodes some
parameters eagerly: value types and `memory` reference parameters. For these parameters, the dispatcher rejects a word
that has bits outside the declared width. A consumer that decodes the type that the policy declares sees the canonical
value or no value. A selectorless policy (ADR-0004) has no dispatcher. A consumer that decodes a wider type than the
policy declares sees bits that the normalization discarded.

## Decision

**Every word that the enforcer reads must be the canonical encoding of its declared type.** Solidity's ABI coder v2
makes the same requirement for each word that it decodes. **The enforcer rejects a non-canonical word and does not
normalize it, for every policy.** Rejection covers everything that normalization protects. The enforcer rejects the
out-of-width attack instead of comparing it.

## Alternatives Considered

- **Normalizing and accepting, with a model of a consumer that masks**: rejected. Normalization targets the type that
  the policy declares. This is the type that the consumer decodes only where a dispatcher enforces the match.
  Normalization approves calls that a conformant consumer of a wider type decodes differently.
- **Rejecting only for selectorless policies**: rejected. The rule would depend on a dispatcher between the caller and
  the consumer, and the policy cannot see that dispatcher.

## Consequences

- The enforcer rejects calldata that was assembled without cleanup.
- The enforcer can deny a call that a consumer accepts. Solidity checks a lazily accessed `calldata` element only when
  it reads the element. A consumer that never reads a dirty element that the policy reads accepts the call that the
  enforcer rejects.
- A policy author can rely on the enforcer having compared the bytes that the consumer decodes. The author does not need
  to know the width that the consumer declares for each value-type word, given the same layout and a conformant decoder.
- Both enforcers implement the check. The enforcement vectors pin `NON_CANONICAL_VALUE`.

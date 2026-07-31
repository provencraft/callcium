# ADR-0013: Non-Canonical Calldata Rejection

## Status

Accepted.

## Context

An enforcer that compares raw calldata words lets an attacker defeat a rule with bits outside the declared width. Normalizing each resolved word to its declared type before applying the operator closes that, and leaves open whether the non-canonical word itself is admissible.

Admitting it is sound only where something guarantees the consumer observes the same value. Solidity's dispatcher rejects a word carrying bits outside a declared parameter's width, so a consumer of the policy's type sees the canonical value or nothing. With `FLAG_NO_SELECTOR` set there is no dispatcher, and where the consumer decodes a wider type than the policy declares, every bit above that width is normalized away before the operator sees it.

## Decision

The enforcer models the admissibility of a conformant ABI decoder: a word that is not the canonical encoding of its declared type is rejected rather than normalized, for every policy. Rejection subsumes what normalization protects, since the attack above reverts instead of comparing correctly.

## Alternatives Considered

- **Normalize and admit, modelling an assembly consumer that masks:** Rejected because normalization targets the type the policy declares, which is the type the consumer decodes only where a dispatcher enforces the match. It avoids a false denial no conformant decoder produces, at the cost of a false approval one does.
- **Scope the rule to selectorless policies:** Rejected because such a rule depends on the dispatcher standing between caller and consumer, which `FLAG_NO_SELECTOR` removes. Any future flag that changes the call path reintroduces the same gap.

## Consequences

- Calldata assembled without cleanup is rejected. A Solidity consumer's callers are unaffected, since those calls already revert in the dispatcher.
- A policy author can rely on the enforcer having compared the bytes the consumer decodes, without knowing the consumer's declared types.

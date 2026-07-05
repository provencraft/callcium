# ADR-0002: Path-Sorted Rules

## Status

Accepted.

## Context

Within a DNF group, rules are evaluated with AND semantics, so their order does not affect the outcome. An unconstrained order, however, makes the encoding ambiguous: the same rule set could serialize to different byte sequences, breaking hash-based identity, and duplicate or contradictory rules on the same path could sit arbitrarily far apart, making build-time detection quadratic.

## Decision

Rules within each group are sorted by `(scope, pathDepth, pathBytes, operatorBytes)` ascending.

**Why scope-first ordering:**
- **Early cheap rejects**: Call-level checks (msg.sender, msg.value, etc.) are O(1) with no descriptor/calldata traversal. Evaluate them first; fail fast before any expensive operations.
- **Predictable execution blocks**: Validators run a tight call-level loop, then a tight calldata loop, without per-rule scope branching.

**Why path-sorted within scope:**
- **Canonical encoding**: One rule set, one byte sequence. Policy identity is its content hash; sorting makes the hash stable regardless of authoring order.
- **Adjacent duplicates and contradictions**: Rules on the same path end up next to each other, so build-time duplicate and contradiction detection is a single linear pass over neighbors.
- **Deterministic evaluation order**: The failing rule index reported by the enforcer is stable for a given policy and calldata.

## Alternatives Considered

- **User-defined rule order:** Allow policy authors to control evaluation order within groups. Rejected because AND semantics make order irrelevant to the outcome, while arbitrary ordering breaks canonical encoding and forces per-rule scope branching.
- **Path-sorted without scope separation:** Sort all rules by path only, intermixing call-level and calldata rules. Rejected because interleaving O(1) call-level checks with calldata rules destroys the cheap fail-fast block at the start of each group.

## Consequences

- Rule ordering is deterministic and canonical — no user control over evaluation order within a group.
- Same-path rules are adjacent, enabling linear-pass duplicate and contradiction detection at build time.
- Breaking the sort invariant (e.g., via manual blob construction) violates canonicalization requirements.

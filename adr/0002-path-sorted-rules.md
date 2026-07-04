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

### Walkthrough

Given rules:
```
scope=0, path=[0x0000]  // msg.sender check
scope=0, path=[0x0001]  // msg.value check
scope=1, path=[0x0000]          // param 0
scope=1, path=[0x0000, 0x0000]  // param 0, field 0
scope=1, path=[0x0000, 0x0001]  // param 0, field 1
scope=1, path=[0x0001]          // param 1
```

Validator processes:
1. **Call-level block**: msg.sender, msg.value (O(1) each, no traversal).
2. **Calldata block**: param 0 → field 0 → field 1 → param 1.

## Alternatives Considered

- **User-defined rule order:** Allow policy authors to control evaluation order within groups. Rejected because AND semantics make order irrelevant to the outcome, while arbitrary ordering breaks canonical encoding and forces per-rule scope branching.
- **Path-sorted without scope separation:** Sort all rules by path only, intermixing call-level and calldata rules. Rejected because interleaving O(1) call-level checks with calldata rules destroys the cheap fail-fast block at the start of each group.

## Consequences

- Rule ordering is deterministic and canonical — no user control over evaluation order within a group.
- Same-path rules are adjacent, enabling linear-pass duplicate and contradiction detection at build time.
- Breaking the sort invariant (e.g., via manual blob construction) violates canonicalization requirements.

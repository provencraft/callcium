# ADR-0002: Path-Sorted Rules

## Status

Accepted.

## Context

Within a DNF group, rules must be evaluated with AND semantics. The dominant cost is calldata traversal — navigating the descriptor tree to locate each rule's target value. If rules targeting nearby calldata locations are evaluated consecutively, the traversal engine can reuse intermediate state (ancestor stack frames) rather than re-navigating from the root.

## Decision

Rules within each group are sorted by `(scope, pathDepth, pathBytes, operatorBytes)` ascending.

**Why scope-first ordering:**
- **Early cheap rejects**: Call-level checks (msg.sender, msg.value, etc.) are O(1) with no descriptor/calldata traversal. Evaluate them first; fail fast before any expensive operations.
- **Traversal state preservation**: Calldata rules benefit from longest-common-prefix (LCP) reuse. Inserting call-level rules between calldata paths breaks the ancestor stack and forces redundant re-traversal.
- **Predictable execution blocks**: Validators can run a tight call-level loop, then a tight calldata loop, without per-rule branching.

**Why path-sorted within scope:**
- Adjacent calldata rules share common path prefixes.
- Validator can cache ancestor location frames.
- Reduces redundant calldata traversal operations.
- All calldata rules for a candidate group are prefix-sorted, minimizing repeated traversals from the root.

**Path prefix caching (optimization):** Validators can exploit path sorting by maintaining a fixed-size scratch buffer (MAX_PATH_DEPTH entries of 16-bit values) that caches the previous rule's path steps. For each new rule, compute the shared prefix depth by comparing steps from the start until the first mismatch. Only re-traverse the suffix (steps after the shared prefix). Quantified paths should reset the cache to avoid stale state from array iteration.

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
2. **Calldata block**: param 0 → field 0 → field 1 → param 1 (reuse traversal state).

## Alternatives Considered

- **User-defined rule order:** Allow policy authors to control evaluation order within groups. Rejected because arbitrary ordering breaks LCP prefix reuse, forces per-rule scope branching, and prevents the traversal engine from maintaining a contiguous ancestor stack.
- **Path-sorted without scope separation:** Sort all rules by path only, intermixing call-level and calldata rules. Rejected because inserting O(1) call-level checks between calldata paths would break the ancestor stack cache and force redundant re-traversal from the root.

## Consequences

- Enables scratch-buffer LCP optimization for O(suffix) traversal per rule instead of O(full path).
- Rule ordering is deterministic and canonical — no user control over evaluation order within a group.
- Breaking the sort invariant (e.g., via manual blob construction) will degrade traversal performance and may violate canonicalization requirements.

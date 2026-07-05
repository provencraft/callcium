# ADR-0001: Disjunctive Normal Form (DNF)

## Status

Accepted.

## Context

The policy format must represent compound permission rules combining AND and OR logic. Two standard normal forms are candidates: DNF (OR of AND-groups) and CNF (AND of OR-clauses).

The dominant runtime cost is locating values in calldata via descriptor traversal, not the operator evaluation itself. The layout choice must minimize traversal cost for common patterns (admin bypass, simple allowlists).

## Decision

The policy format uses DNF: groups have OR semantics, rules within groups have AND semantics.

**Early success without heavy traversal.** Common pattern: `admin_override OR (value constraints on calldata)`. In DNF, the admin group (call-level, cheap) can pass and validation stops immediately.

**Group-major layout enables O(1) short-circuit.** The blob structure `[groups...]` with `[ruleCount][groupSize]` lets DNF return true on the first passing group. On group failure, skip to the next group in O(1) using groupSize.

**Contiguous evaluation blocks.** Within a DNF group, rules are ordered scope-first, so a group evaluates as one cheap call-level block followed by one calldata block.

**Compact OR expressions via operators.** Many CNF-shaped intents map to a single operator in DNF. For example, `recipient == A OR recipient == B` becomes one `OP_IN(recipient, {A, B})` rule. This keeps AND-groups small and contiguous.

## Alternatives Considered

- **CNF (Conjunctive Normal Form):** AND of OR-clauses. Rejected because CNF's success path must touch every clause — even with optimal literal ordering, all clause paths must be visited to return true. This eliminates early-exit on common patterns like admin bypass. Additionally, CNF interleaves disjuncts from different clauses, forcing per-literal scope branching instead of contiguous evaluation blocks.

## Consequences

- Gas-optimal for common permission patterns (admin overrides, tiered allowlists).
- Users lose control over group evaluation order — OR semantics make ordering immaterial to which groups can pass, and the canonical sort fixes a single, portable evaluation order.
- OR expressions within a group must be expressed via set operators (`OP_IN`) or split into separate groups.

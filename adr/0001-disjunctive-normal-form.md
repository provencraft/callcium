# ADR-0001: Disjunctive Normal Form (DNF)

## Status

Accepted.

## Context

The policy format must represent compound permission rules combining AND and OR logic. Two standard normal forms are candidates:

- **DNF (Disjunctive Normal Form):** OR of AND-groups. A policy passes if any group passes; within a group, all rules must hold.
- **CNF (Conjunctive Normal Form):** AND of OR-clauses. A policy passes if all clauses pass; within a clause, at least one literal must hold.

The dominant runtime cost is locating values in calldata via descriptor traversal, not the operator evaluation itself. The layout choice must minimize traversal cost for common patterns (admin bypass, simple allowlists).

## Decision

The policy format uses DNF: groups have OR semantics, rules within groups have AND semantics.

**Early success without heavy traversal.** Common pattern: `admin_override OR (value constraints on calldata)`. In DNF, the admin group (call-level, cheap) can pass and validation stops immediately. In CNF, every clause must be satisfied, so an admin check must be redundantly included in every clause to achieve the same effect.

**Group-major layout enables O(1) short-circuit.** The blob structure `[groups...]` with `[ruleCount][groupSize]` lets DNF return true on the first passing group. On group failure, skip to the next group in O(1) using groupSize. CNF requires evaluating at least one literal per clause and all clauses overall.

**Path locality and LCP reuse.** Within a DNF group, rules are sorted by `(scope, pathDepth, pathBytes)`. Adjacent rules share prefixes, so the traversal engine reuses state. CNF interleaves disjuncts from different clauses, reducing locality and increasing re-traversal.

**Compact OR expressions via operators.** Many CNF-shaped intents map to a single operator in DNF. For example, `recipient == A OR recipient == B` becomes one `OP_IN(recipient, {A, B})` rule. This keeps AND-groups small and contiguous.

**Gas benefits.** DNF minimizes traversal cost:
1. **Call-level rules first**: Cheap O(1) checks (msg.sender, msg.value) can accept or reject before any calldata traversal.
2. **First-group exit**: On common paths (admin bypass, simple allowlists), validation completes after evaluating a single cheap group.

CNF's success path must touch every clause. Even with optimal literal ordering, all clause paths must be visited to return true.

## Alternatives Considered

- **CNF (Conjunctive Normal Form):** AND of OR-clauses. Rejected because CNF's success path must touch every clause — even with optimal literal ordering, all clause paths must be visited to return true. This eliminates early-exit on common patterns like admin bypass. Additionally, CNF interleaves disjuncts from different clauses, reducing path locality and increasing calldata re-traversal.

## Consequences

- Gas-optimal for common permission patterns (admin overrides, tiered allowlists).
- Users lose control over group evaluation order (groups are canonically sorted — see ADR-0003).
- OR expressions within a group must be expressed via set operators (`OP_IN`) or split into separate groups.

# ADR-0001: Disjunctive Normal Form

## Status

Accepted.

## Context

A policy combines conditions with AND and OR. Two normal forms are candidates: DNF, an OR of AND-groups, and CNF, an AND
of OR-clauses.

Common policies pair a cheap condition on the call with conditions on calldata. For example, an administrator can call
freely, and anyone else must stay within limits. A context test reads one value of the call. A calldata test reads one
word of calldata. Each dynamic offset that its path follows adds a read and a bounds check.

Separate alternatives for a disjunction inside one field, such as `recipient == A OR recipient == B`, repeat every other
condition of the original alternative.

## Decision

**A policy is a disjunction of groups, and a group is a conjunction of rules** (`Formula.holds`).

- **Early success.** A group of call-level conditions reads no calldata. If the enforcer evaluates this group first and
  the group holds, evaluation ends.
- **Disjunction inside a condition stays in the operator.** `recipient == A OR recipient == B` is one `IN` rule.

## Alternatives Considered

- **CNF**: rejected. A passing policy must evaluate every clause, so no condition ends evaluation early on success.
  Distribution of the OR copies the administrator's condition into every clause. The blob contains that condition once
  per clause, and the administrator's call evaluates it once per clause.

## Consequences

- A disjunction across fields at the root needs separate groups. Each group repeats the rules that the alternatives
  share.

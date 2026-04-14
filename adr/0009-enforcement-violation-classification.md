# ADR-0009: Enforcement Violation Classification

## Status

Accepted.

## Context

Callcium's policy enforcement produces failures from two distinct sources: the policy's declared structure (descriptor) and the actual calldata being evaluated. Before this decision, both Solidity and TypeScript implementations mixed these failure types — the SDK used generic codes like `OFFSET_OUT_OF_BOUNDS` for both descriptor-relative and calldata-relative failures, while Solidity reverted with specific errors but without a formal classification boundary.

A shared enforcement vocabulary requires a clear principle for which failures belong in the public violation API and which are structural/integrity concerns.

## Decision

Enforcement failures are classified by the **"different calldata" test**: if different calldata could change the outcome, the failure is an **enforcement violation**; if the failure is fixed by the descriptor or policy structure regardless of calldata, it is an **integrity error**.

### Enforcement violations (calldata-dependent)

These are part of the shared `ViolationCode` vocabulary. They represent runtime mismatches between valid policy expectations and specific input data.

| Code | Trigger |
|---|---|
| `VALUE_MISMATCH` | Operator not satisfied on resolved value. |
| `SELECTOR_MISMATCH` | Calldata selector does not match policy. |
| `MISSING_SELECTOR` | Calldata too short for selector. |
| `CALLDATA_OUT_OF_BOUNDS` | Calldata truncated or invalid pointers. |
| `ARRAY_INDEX_OUT_OF_BOUNDS` | Dynamic array shorter than required index. |
| `MISSING_CONTEXT` | Context property not provided at runtime. |
| `QUANTIFIER_LIMIT_EXCEEDED` | Array exceeds iteration limit. |
| `QUANTIFIER_EMPTY_ARRAY` | ANY/ALL on empty array. |

### Integrity errors (descriptor/policy-fixed)

These are **not** part of the shared violation vocabulary. They are caught by `PolicyValidator` at build time and retained in enforcers as defense-in-depth. Examples: arg index out of bounds, tuple field out of bounds, static array index out of bounds, descend into scalar, path too deep, nested quantifiers, unknown operator.

### Boundary cases

- **Dynamic array index OOB** is a violation — the array length comes from calldata at runtime.
- **Static array index OOB** is an integrity error — the array length is fixed in the descriptor.
- `ARRAY_INDEX_OUT_OF_BOUNDS` at enforcement time refers exclusively to dynamic arrays.

## Alternatives Considered

- **All navigation failures as violations**: Adding ~7 granular codes (`ARG_INDEX_OUT_OF_BOUNDS`, `TUPLE_FIELD_OUT_OF_BOUNDS`, `NOT_COMPOSITE`, etc.) to the enforcement vocabulary. Rejected because these are descriptor-fixed failures that cannot be resolved by different calldata, and exporting interpreter internals as business semantics bloats the API surface.

- **All navigation failures as integrity errors**: Moving all OOB conditions out of the violation vocabulary. Rejected because dynamic array index OOB genuinely depends on calldata content and belongs in enforcement results. The "different calldata" test correctly places it in the violation category.

## Consequences

- The shared enforcement vocabulary stays small and stable (8 codes).
- SDK reader functions must distinguish descriptor-relative failures (throw `CallciumError`) from calldata-relative failures (return violation codes). This is a classification cleanup, not just string renaming.
- Future implementors in other languages have a clear principle for categorising new failure modes.
- Integrity errors remain implementation-specific — Solidity uses custom error reverts, TypeScript uses `CallciumError` throws. No cross-language alignment required for these.
- Violation classification does not mandate identical control flow across runtimes. How an enforcer responds to a violation (revert, collect, skip) is a separate design decision.

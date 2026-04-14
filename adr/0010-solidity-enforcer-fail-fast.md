# ADR-0010: Solidity Enforcer Fail-Fast Semantics

## Status

Accepted.

## Context

Callcium evaluates policy groups with OR semantics (Disjunctive Normal Form): the first passing group succeeds. The TypeScript SDK enforcer collects all violations per group and continues to the next group when one fails. The Solidity enforcer, however, reverts immediately when `CalldataReader` encounters a calldata-relative failure (e.g., truncated calldata, dynamic array index out of bounds). This means a calldata-relative failure in group 1 prevents group 2 from being evaluated on-chain, even if group 2 would have passed.

This raises the question: is this a bug that should be fixed for DNF correctness, or an intentional design choice?

## Decision

The Solidity enforcer's fail-fast revert behaviour on calldata-relative failures is **intentional and correct for the EVM execution environment**. It is not a bug.

The two runtimes share **semantic alignment** — identical violation vocabulary, identical classification of what counts as a violation, identical policy language — but not **operational alignment**. Control flow differs where the execution environment demands it. The design goal is **shared semantics, runtime-appropriate control flow**, not identical implementation mechanics.

### Rationale

- **Gas cost**: Converting `CalldataReader` from reverting to returning result types would add memory allocation, conditional checks, and struct packing overhead throughout the hot path. The enforcer is called on every guarded transaction — gas matters.
- **Safety posture**: On-chain, if calldata cannot satisfy a rule's structural expectations, reverting the transaction is the safer default. Allowing a transaction to pass because one group couldn't fully evaluate introduces risk.
- **Practical impact**: Calldata structure is fixed per function signature. If calldata is truncated or a dynamic array is shorter than expected, it is unlikely that a different group targeting the same calldata would pass. The DNF divergence is theoretical more than practical.

### Resulting semantic model

| Concern | Solidity | TypeScript SDK |
|---|---|---|
| Violation vocabulary | Shared (ADR-0009). | Shared (ADR-0009). |
| Control flow on violation | Revert (fail-fast). | Collect violation, try next group. |
| `check()` return on violation | `false` (no group/rule detail). | `{ ok: false, violations: [...] }`. |
| `enforce()` on violation | `revert PolicyViolation(group, rule)`. | `throw PolicyViolationError`. |
| Calldata-relative reader failure | Revert (kills evaluation). | Return violation code, continue. |

## Alternatives Considered

- **Refactor CalldataReader to return result types**: This would make Solidity's DNF evaluation match the SDK's — calldata-relative failures would cause the current group to fail and the next group to be tried. Rejected because the gas overhead is real, the stricter on-chain posture is appropriate, and the practical impact of the divergence is minimal. If DNF correctness under calldata-relative failures becomes a requirement, this can be revisited.

## Consequences

- The runtimes are **interchangeable in the common case** but not identical in every failure path. The guarantee is one-directional: a policy that passes on-chain will always pass in the SDK, but an SDK pass does not guarantee on-chain pass when calldata-relative failures interact with multi-group DNF evaluation.
- The spec must document that implementations share semantics but may differ in control flow, and that on-chain enforcement is strictly more conservative.
- Developers testing multi-group policies in the SDK should be aware that edge cases involving calldata-relative failures (truncated calldata, short dynamic arrays) may produce different outcomes on-chain. This should be documented in SDK usage guidance.

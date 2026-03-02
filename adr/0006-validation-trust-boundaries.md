# ADR-0006: Validation Trust Boundaries

## Status

Accepted.

## Context

The policy pipeline has four stages: builder (off-chain), coder (off-chain), registry/storage (on-chain), and enforcer (on-chain runtime). Each stage could potentially validate the policy blob, but duplicating checks across stages wastes gas on the hot path (enforcement) and obscures which component is responsible for what.

The threat model assumes that `PolicyManager` access is gated — only trusted entities can store policies. An actor with storage access could simply delete a policy or store a trivial always-pass policy; crafting a subtly malformed blob offers no advantage.

The spec (policy-v1, Section 10.1) defines structural checks that validators MUST perform. The question is where these checks live and what the enforcer can assume about its input.

## Decision

Validation is split into three tiers. Each tier trusts the ones before it.

**Storage time (`Policy.validate()`)** performs all spec Section 10.1 structural checks:

- Version byte validity.
- Descriptor structural validity.
- `groupCount > 0` and `ruleCount > 0` per group.
- Rule size consistency (`ruleSize == fixed overhead + depth * 2 + dataLength`).
- Group and blob exact consumption (no trailing bytes at either level).
- Scope validity (`scope ∈ {0, 1}`).
- Context path depth (`scope == 0 ⇒ depth == 1`).
- Path non-emptiness (`depth >= 1`).
- Operator code validity and payload size match.

These run once at storage time — never during enforcement.

**Build time (`PolicyValidator`)** performs semantic checks: operator-type compatibility, contradiction detection, redundancy warnings, path navigability. These are advisory and run off-chain.

**Runtime (`PolicyEnforcer`)** performs only checks that depend on live transaction data:

- Selector match against calldata.
- Calldata length and bounds during ABI traversal.
- Array length cap for quantifier iteration (DoS protection).
- Nested quantifier rejection.
- Path depth <= 32 (runtime gas-safety cap).
- Unknown context property ID (inherent to the assembly switch structure).

The structural/semantic line is: **can the byte stream be parsed and interpreted without ambiguity?** Scope and opCode are structural because they are closed-set tag bytes that determine how the rule is interpreted. This follows the spec's classification.

## Alternatives Considered

- **Duplicate checks in the enforcer (defense-in-depth)**: Rejected. Costs ~530-720 gas per rule per enforcement call. The threat model makes malformed-blob attacks irrational — if you control storage, you don't need a crafted blob.
- **Exclude opCode validation from `Policy.validate()` to avoid coupling to `OpCode.sol`**: Rejected. The spec requires it (Section 10.1, MUST reject), and the coupling cost is acceptable.
- **Separate `Policy.validateStrict()` for third-party encoders**: Rejected. The pipeline is the product — third-party encoders that bypass the builder own the consequences.

## Consequences

- Enforcement costs ~530 gas less per rule. For a 32-rule policy, ~17k gas saved per transaction.
- Storage costs ~2.1k gas more per policy (one-time, amortized over all enforcement calls).
- The enforcer assumes blobs in storage are structurally valid. Calling `enforce()` on an unvalidated blob may produce undefined behavior.
- `Policy.validate()` imports `OpCode` and `OpRule`. Adding a new operator requires `OpRule` to recognise it before blobs containing it can be stored.

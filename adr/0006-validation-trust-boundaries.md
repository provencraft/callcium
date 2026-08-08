# ADR-0006: Validation Trust Boundaries

## Status

Accepted.

## Context

The policy pipeline has four stages: builder (off-chain), coder (off-chain), registry/storage (on-chain), and enforcer (on-chain runtime). Each stage could potentially validate the policy blob, but duplicating checks across stages wastes gas on the hot path (enforcement) and obscures which component is responsible for what.

The threat model assumes that `PolicyManager` access is gated — only trusted entities can store policies. An actor with storage access could simply delete a policy or store a trivial always-pass policy; crafting a subtly malformed blob offers no advantage.

The spec (policy-v2, Section 8.1) defines structural checks that validators MUST perform. The question is where these checks live and what the enforcer can assume about its input.

## Decision

Validation splits into three tiers, each trusting the ones before it.

**Storage time (`Policy.validate()`)** enforces every well-formedness invariant the spec defines (Section 8.1), once, onchain. An invariant belongs here, rather than at build time, whenever a violation would change how the enforcer evaluates the policy or leave evaluation undefined: `buildUnsafe()` bypasses build time, so nothing downstream of it would otherwise catch that case before enforcement. An invariant that only constrains what a comparison means, with evaluation otherwise unaffected, can stay at build time instead.

**Build time (`PolicyValidator`)** enforces semantic invariants — meaning, not shape — offchain, gating the strict `build()`; `buildUnsafe()` is the deliberate bypass. These never re-run onchain, except where the criterion above pulls a slice of one into storage time instead.

**Runtime (`PolicyEnforcer`)** enforces nothing about the blob itself. It checks only conditions that depend on the live transaction, and trusts storage time for everything else.

## Alternatives Considered

- **Duplicate checks in the enforcer (defense-in-depth)**: Rejected. Costs ~530-720 gas per rule per enforcement call. The threat model makes malformed-blob attacks irrational — if you control storage, you don't need a crafted blob.
- **Separate `Policy.validateStrict()` for third-party encoders**: Rejected. The pipeline is the product — third-party encoders that bypass the builder own the consequences.

## Consequences

- The enforcer assumes blobs in storage are structurally valid. Calling `enforce()` on an unvalidated blob may produce undefined behavior.

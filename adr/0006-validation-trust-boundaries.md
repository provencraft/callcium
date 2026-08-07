# ADR-0006: Validation Trust Boundaries

## Status

Accepted.

## Context

The policy pipeline has four stages: builder (off-chain), coder (off-chain), registry/storage (on-chain), and enforcer (on-chain runtime). Each stage could potentially validate the policy blob, but duplicating checks across stages wastes gas on the hot path (enforcement) and obscures which component is responsible for what.

The threat model assumes that `PolicyManager` access is gated — only trusted entities can store policies. An actor with storage access could simply delete a policy or store a trivial always-pass policy; crafting a subtly malformed blob offers no advantage.

The spec (policy-v2, Section 8.1) defines structural checks that validators MUST perform. The question is where these checks live and what the enforcer can assume about its input.

## Decision

Validation is split into three tiers. Each tier trusts the ones before it.

**Storage time (`Policy.validate()`)** performs every spec Section 8.1 well-formedness check (PWF-1 through PWF-22): header and descriptor validity, size and consumption consistency, scope and context-path rules, path-depth bounds, operator validity, IN operand ordering, and the shape of every hint block — that its header names a defined kind and that no reserved field carries a value. These run once at storage time — never during enforcement.

IN operand ordering (PWF-21) deserves emphasis: operands must be strictly ascending by lexicographic comparison of their 32-byte encodings, the invariant the enforcer's binary search relies on. An unsorted set silently mis-enforces rather than reverting, so it cannot be deferred to build time.

**Build time (`PolicyValidator`)** performs semantic checks: operator-type compatibility, contradiction detection, redundancy warnings, path navigability. These run offchain and gate the strict `build()` in every implementation — any reported issue blocks it; `buildUnsafe()` is the deliberate bypass. They are never re-checked onchain.

**Runtime (`PolicyEnforcer`)** performs only checks that depend on live transaction data:

- Selector match against calldata.
- Calldata bounds on every load along a hint's hop chain, including the requirement that offset arithmetic not wrap (spec Section 7.2).
- Element index against the live length word when a hop crosses a dynamic array.
- Calldata backing for the extent a dynamic target's declared length claims (spec Section 7.2).
- Array length cap for quantifier iteration (DoS protection).
- Empty-array rejection under the existential quantifier (spec Section 7.3).
- Canonical encoding of each resolved scalar (spec Section 7.4).
- Unknown context property ID (inherent to the assembly switch structure; also checked at storage time).

Path depth is absent from that list: the enforcer reads no path bytes, and its loops are bounded by the hint's own hop-count fields and by the iteration cap (ADR-0005). Nested quantifiers are absent because the hint header encodes one quantifier kind and one frame, so nesting has no representation to reject.

## Alternatives Considered

- **Duplicate checks in the enforcer (defense-in-depth)**: Rejected. Costs ~530-720 gas per rule per enforcement call. The threat model makes malformed-blob attacks irrational — if you control storage, you don't need a crafted blob.
- **Exclude opCode validation from `Policy.validate()` to avoid coupling to `OpCode.sol`**: Rejected. The spec requires it (Section 8.1, MUST reject), and the coupling cost is acceptable.
- **Separate `Policy.validateStrict()` for third-party encoders**: Rejected. The pipeline is the product — third-party encoders that bypass the builder own the consequences.

## Consequences

- Enforcement costs ~530 gas less per rule. For a 32-rule policy, ~17k gas saved per transaction.
- Storage costs ~2.1k gas more per policy (one-time, amortized over all enforcement calls).
- The enforcer assumes blobs in storage are structurally valid. Calling `enforce()` on an unvalidated blob may produce undefined behavior.
- `Policy.validate()` imports `OpCode` and `OpRule`. Adding a new operator requires `OpRule` to recognise it before blobs containing it can be stored.

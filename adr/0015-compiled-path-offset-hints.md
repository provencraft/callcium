# ADR-0015: Compiled Path Offset Hints

## Status

Accepted.

## Context

Enforcement resolves every calldata rule by interpreting its path against the embedded descriptor: walking argument heads, tuple fields, and array metadata to compute a byte offset. For a fully static path this walk recomputes a constant — the ABI layout of a static type is fixed by the signature — yet the cost is paid on every call and scales with path depth and quantifier iteration. The builder already holds the descriptor at build time and can compute these offsets once.

Embedding precomputed offsets creates a second representation of the rule target alongside the path, which raises two questions this ADR settles: where offset correctness is verified (ADR-0006 tiers), and which representation is authoritative at runtime.

## Decision

**Rule structure gains a compiled hint block** between path and opCode, present for calldata rules only. `typeCode` carries the descriptor type code of the resolved target (the v2 table, ADR-0014). The block is 5 or 13 bytes; its shape is a deterministic, byte-local function of the rule's own bytes (scope, the hint's sentinel prefix, and quantifier steps — never the descriptor):

- Fully static path, scalar target — 5 bytes: `headOffset(4) | typeCode(1)`.
- Static path to a depth-1 dynamic target — 5 bytes: same layout; `headOffset` addresses the head slot (the offset word), not the payload. Only `LENGTH_*` operators target dynamic types (policy spec Section 5.7), and they consume the head slot and length word only, so no further fields are needed.
- Quantifier over a dynamic array of static elements — 13 bytes: `arrayHead(4) | elemStride(4) | suffixOffset(4) | typeCode(1)`.
- Any other path — 5 bytes: sentinel `headOffset = 0xFFFFFFFF`, `typeCode = 0x00` (the reserved code, ADR-0014). This covers paths crossing a dynamic node (including quantifiers over dynamic elements) and quantifiers over static arrays, whose descriptor-declared element count the block does not carry. A parser still resolves the block size in precedence order: sentinel `headOffset`, then quantifier step.

`headOffset` is relative to the enforcement base offset, so hint bytes are identical for selector and selectorless policies. It is 4 bytes because the derivable maximum static head (255 params × 4095 static words × 32 bytes ≈ 33.4 MB) exceeds be24.

**Verification stays in the ADR-0006 tiers**, split by what each tier can check without new machinery:

| What | Who | When |
|---|---|---|
| Hint *values* (offsets, `typeCode`) | strict `build()` computes them; `PolicyValidator` checks PV-6 | build time, offchain |
| Hint *shape* (block size, sentinel canonical form) | `Policy.validate()` | storage time, onchain |
| Hint correctness | nobody | runtime |

The new validity invariant (PV-6) requires each hint to equal the deterministic compilation of its path against the descriptor — concrete iff the path is compilable, sentinel iff not. Strict `build()` computes hints itself — callers never supply them — so divergence cannot enter through the supported pipeline; decoders recompute and flag mismatches, making every stored blob permissionlessly verifiable offchain. Storage-time shape checks are byte-local, matching the existing PWF checks. A divergent hint in a well-formed blob is the same trust class as a divergent path (ADR-0006).

**Runtime dispatch is exclusive.** A concrete hint MUST be resolved via the hint; a sentinel hint MUST be resolved via path traversal. Quantified rules read exactly one thing from the path at runtime — the quantifier step, for empty-array semantics — and all addressing from the hint. Verdicts are unchanged by construction: static-path traversal performs arithmetic only and loads the same final calldata words the hint load touches, so bounds behavior and outcomes are identical.

## Alternatives Considered

- **Store-time hint recomputation (well-formedness tier)**: rejected. Requires path navigation and quantifier semantics inside `Policy.validate()`, blending build-only concepts into the storage tier, growing every registry that inlines it, and adding store gas — for protection against actors who already control gated storage (ADR-0006 threat model). The tempting precedent is PWF-21, but IN-sorting is a byte-local scan inside one rule; hint recomputation is descriptor navigation, exactly the machinery the storage tier excludes.
- **Runtime fallback from hint to traversal on mismatch**: rejected. Masks path/hint divergence instead of surfacing it, and makes the verdict depend on which representation a given enforcer consulted first.
- **Offsets replace paths entirely**: rejected. Destroys offchain verifiability (nothing to recompute against), decode semantics, and the canonical sort key, to save the path bytes only.
- **Dropping the embedded descriptor**: rejected. Still required for PV-6 recomputation, sentinel-rule traversal, and tooling; it is amortized once per policy while hints cost per rule, so the size argument is empty.

## Consequences

- Enforcement of a fully static rule drops from a per-call descriptor walk to one load plus canonicality and operator checks; deep paths and quantifiers gain the most.
- The rule layout change forces the policy wire format version to `0x2` — a v1 parser reading v2 bytes misparses silently instead of failing. Enforcer and validator are v2-only (stored v1 blobs revert `UnsupportedVersion`, the v1 spec is deleted in favor of `policy-v2.md`, no migration tooling ships); every rule coder and hint consumer in both mirrors changes, all conformance vectors regenerate, and policy hashes change for every logical policy.
- Calldata rules grow 5 or 13 bytes, shrinking rule capacity under `MAX_POLICY_SIZE` by roughly 10–25%.
- Raising `MAX_QUANTIFIED_ARRAY_LENGTH` becomes attractive once per-element cost falls; it is verdict-affecting and deferred to its own decision.

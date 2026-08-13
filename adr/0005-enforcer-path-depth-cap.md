# ADR-0005: Enforcer-Level Path Depth Cap

## Status

Accepted.

## Context

The policy format allows `pathDepth` up to 255 (1-byte field). Compiled hints (ADR-0015) resolve every calldata rule's addressing, so path bytes are not read during enforcement. The consumers that do walk paths — hint compilation, PV-6 recomputation, canonical sorting — run offchain at build time. What bound the depth needs, and which tier enforces it, follows from that division.

## Decision

`MAX_PATH_DEPTH` (32) is a well-formedness bound (PWF-17), enforced where well-formedness is checked: `Policy.validate()` at the storage boundary. It bounds per-rule path bytes and the work of hint compilation and recomputation.

The enforcer performs no runtime depth check. It reads no path bytes — paths are skipped by `ruleSize` arithmetic — and every loop enforcement executes is bounded independently of depth: hop chains by their 6-bit `hopCount` fields, quantifier iteration by `MAX_QUANTIFIED_ARRAY_LENGTH`. Those bounds also carry the self-shielding obligation for offchain `staticcall` use against unvalidated policy bytes (ADR-0006): no field a caller controls can make an enforcement loop exceed them.

No component traverses calldata by path at runtime, so no traversal carries a depth limit of its own (ADR-0015).

## Alternatives Considered

- **Retaining the runtime depth check as defense-in-depth**: rejected. It guarded a path-walking loop that no longer exists; with resolution following the hint (ADR-0015), depth influences no runtime loop, and a check that guards nothing documents a false coupling.
- **Dropping the cap from the format entirely**: rejected. Unbounded paths inflate rule size and build-time compilation work with no expressiveness gain, and the cap is only safely tunable upward — lowering it later strands already-stored policies — so the initial value carries cheap headroom instead.

## Consequences

- Enforcement cost is independent of path depth; deep paths cost bytes and build-time work only.
- Over-deep policies are rejected at the storage boundary (PWF-17), never at runtime.
- The cap can be raised in a future spec revision without a wire-format change — it is a Design-category limit (spec Section 8.4), not a wire-format field.

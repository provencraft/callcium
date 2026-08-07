# ADR-0015: Compiled Path Offset Hints

## Status

Accepted.

## Context

Enforcement resolves every calldata rule by interpreting its path against the embedded descriptor: walking argument heads, tuple fields, and array metadata to compute a byte offset. That walk recomputes what the function signature already fixes — for a fully static path, a constant — yet the cost is paid on every call and scales with path depth and quantifier iteration. The builder already holds the descriptor at build time and can compute the result once.

Embedding a precomputed result creates a second representation of the rule target alongside the path, which raises two questions this ADR settles: where its correctness is verified (ADR-0006 tiers), and which representation is authoritative at runtime.

A third force shapes the encoding. A scheme that resolves only the paths it finds convenient must keep descriptor traversal live for the rest, leaving two addressing engines on the enforcement path and a per-rule branch selecting between them. Coverage is therefore a structural question, not a performance one.

## Decision

**Rule structure gains a compiled hint block** between path and opCode, present for calldata rules only. The block encodes one thing: how to reach the target from the enforcement base offset, as a chain of hops.

A **hop** crosses one dynamic boundary. Every ABI indirection has the same shape — an offset word at a statically known position, relative to the enclosing composite's base — so a hop compiles to a delta:

```
base = baseOffset
for each hop delta d:             // hopCount hops
    base = base + word(base + d)  // bounds-checked calldata load
target = base + delta
```

Crossing a dynamic array at a concrete element index takes a second hop kind: an element hop carrying the index and the element stride. The runtime check that the index is within the array's length is what descriptor traversal used to provide, and it needs exactly those two values; separating element resolution from payload entry also keeps consecutive array crossings — an element that is itself an array — expressible without special cases.

`hopCount` is zero for a fully static path and one per dynamic node the path crosses. Every calldata path a valid policy can express compiles to this form: nested quantifiers are forbidden (PV-3) and path depth is capped, so the chain is bounded by the same limit as the path it compiles.

Quantified rules carry an **iteration frame** after the chain: the element stride, the element count (descriptor-declared for a static array, read from calldata for a dynamic one), and a second chain resolving the target within each element. The per-element step is itself a hop whose delta varies with the index, so iteration reuses the formula above instead of introducing addressing of its own.

**The hint carries the quantifier kind**, in the block's header byte alongside `hopCount`. Two properties follow. Block size becomes a byte-local function of that header, so a parser never scans the path to size a rule. And the enforcer never reads path bytes at all — at runtime the path is inert.

`typeCode` carries the descriptor type code of the resolved target (the v2 table, ADR-0014).

**Verification stays in the ADR-0006 tiers**, split by what each tier can check without new machinery:

| What | Who | When |
|---|---|---|
| Hint *values* (hops, deltas, frame, `typeCode`) | strict `build()` computes them; `PolicyValidator` checks PV-6 | build time, offchain |
| Hint *shape* (header consistency, block size) | `Policy.validate()` | storage time, onchain |
| Hint correctness | nobody | runtime |

PV-6 requires each hint to equal the deterministic compilation of its path against the descriptor. Strict `build()` computes hints itself — callers never supply them — so divergence cannot enter through the supported pipeline; decoders recompute and flag mismatches, making every stored blob permissionlessly verifiable offchain. Storage-time shape checks stay byte-local, matching the existing PWF checks. A divergent hint in a well-formed blob is the same trust class as a divergent path (ADR-0006).

**Runtime resolution is exclusive**: the hint addresses the target and nothing else does. Verdicts are unchanged by construction — a hop loads the same offset word traversal would load, in the same order, under the same bounds checks.

## Alternatives Considered

- **Per-shape layouts with a traversal fallback**: a static block, a quantified block, and a sentinel marking paths that resolve by descriptor traversal at runtime. Rejected because the fallback keeps traversal on the enforcement path — two addressing engines and a per-rule branch between them — and its cost lands on exactly the shapes real ABIs produce, where one `bytes` member makes an entire struct dynamic; on the reference enforcer a traversal-resolved rule measures roughly 1.9× its hint-resolved equivalent on the same signature. Block size also becomes non-local: sizing a rule requires scanning its path for a quantifier step.
- **A fourth layout for single-indirection paths**: extend the per-shape scheme with a block covering one dynamic boundary, discriminated by a flag bit. Rejected because it buys back the common case by adding a layout, a discriminator, and a branch to a scheme whose cost is the number of layouts it carries.
- **Store-time hint recomputation**: verify hint values in `Policy.validate()`. Rejected — it requires path navigation and quantifier semantics inside the storage tier, blending build-only concepts into it and adding store gas, for protection against actors who already control gated storage (ADR-0006 threat model). The tempting precedent is PWF-21, but IN-sorting is a byte-local scan inside one rule; hint recomputation is descriptor navigation.
- **Runtime fallback from hint to traversal on mismatch**: rejected. Masks path/hint divergence instead of surfacing it, and makes the verdict depend on which representation a given enforcer consulted first.
- **Offsets replace paths entirely**: rejected. The path is what PV-6 recomputes against, so dropping it leaves the hint as unverifiable ground truth; it is also the canonical sort key (PC-2) and the only rendering source for tooling. Resolved offsets are not injective across distinct paths, so they cannot carry either role.
- **Dropping the embedded descriptor**: rejected. PV-6 recomputation and offchain tooling both require it, and it is amortized once per policy while hints cost per rule.

## Consequences

- Descriptor traversal leaves the enforcement path. `CalldataReader` remains a public library for decoding and tooling, but the enforcer carries neither a second addressing mechanism nor a branch selecting one.
- Resolution cost scales with the number of dynamic boundaries a path crosses, not with its depth or the node count of the types it passes through. A rule targeting a field of a dynamic struct — the shape one `bytes` member produces — costs one load more than a fully static rule.
- Quantification over dynamic-element arrays and over static arrays becomes expressible through the hint, since the frame supplies the element count the descriptor declares.
- Path bytes are inert at runtime, and remain load-bearing for PV-6 recomputation, canonical sorting, duplicate detection, and rendering.
- The enforcer's operational path-depth cap (ADR-0005) loses its rationale: no runtime cost scales with path depth. Runtime work scales with hop count instead, whose bound the hint's field widths fix.
- Calldata rules grow by the hint block, and paths crossing dynamic nodes grow with each boundary, shrinking rule capacity under `MAX_POLICY_SIZE`.
- The rule layout change forces the policy wire format version to `0x2` — a v1 parser reading v2 bytes misparses silently instead of failing. Enforcer and validator are v2-only (stored v1 blobs revert `UnsupportedVersion`, the v1 spec is deleted in favor of `policy-v2.md`, no migration tooling ships); every rule coder and hint consumer in both mirrors changes, all conformance vectors regenerate, and policy hashes change for every logical policy.
- Raising `MAX_QUANTIFIED_ARRAY_LENGTH` becomes attractive once per-element cost falls; it is verdict-affecting and deferred to its own decision.

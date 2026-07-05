# ADR-0005: Enforcer-Level Path Depth Cap

## Status

Accepted.

## Context

The policy format allows `pathDepth` up to 255 (1-byte field). `CalldataReader` traverses calldata based on a be16 path and does not require a depth cap to be correct. However, `PolicyEnforcer` targets a zero-allocation, predictable-gas hot loop when evaluating rules. Supporting unbounded depth forces either per-rule allocation (`bytes(depth * 2)`) or a worst-case preallocated buffer, both increasing gas and memory expansion costs for all calls — even when typical depths are small.

## Decision

`MAX_PATH_DEPTH` is an operational cap on the reference enforcer, not a wire-format rule. The default cap is 32 steps (64-byte scratch path buffer). The constant is declared in `PolicyFormat` alongside the other spec Section 8.4 normative limits.

**Separation of concerns:**
- `CalldataReader` parses and traverses calldata generically — no depth limit in its config. Consumers enforce their own limits.
- `PolicyEnforcer` owns operational limits that impact its hot path.

**Why both tiers check:** The enforcer must be self-shielding because it can be used offchain via `staticcall` against arbitrary policy bytes that bypass storage validation, so the runtime `require` cannot be removed. The cap is additionally a well-formedness invariant (spec Section 8.1, PWF-17), so `Policy.validate()` rejects over-deep policies at the trust boundary as well; the runtime check remains as defense-in-depth.

**Error taxonomy:** `error PathTooDeep(uint256 depth, uint256 maxDepth)` is defined in `CalldataReader` for reuse by all consumers.

## Alternatives Considered

- **Unbounded depth (up to 255 by format):** Accept any format-valid policy depth. Rejected because it requires either per-rule dynamic allocation or a 510-byte worst-case preallocated buffer, regressing gas substantially on the hot path.
- **Lower fixed cap (e.g., 16 steps):** Covers practically all real-world ABIs and saves tens of gas of scratch-buffer allocation per call. Rejected because the cap is only safely tunable upward — lowering it later strands already-stored policies — so the initial value carries cheap headroom instead.

## Consequences

- Single preallocated scratch buffer (64 bytes) reused across all rules, enabling a zero-allocation hot loop.
- Policies with paths deeper than 32 steps are rejected at runtime rather than silently degrading performance or overflowing the scratch buffer.
- `CalldataReader` remains a generic, reusable traversal library with no enforcer-specific constraints baked in.
- The cap can be raised in a future spec revision without a wire-format change — it is a Design-category limit (spec Section 8.4), not a wire-format field.
- Raising the cap to 64 steps after benchmarking, or adding a per-rule adaptive fallback that allocates a temporary buffer when `depth > MAX_PATH_DEPTH` instead of rejecting, remain viable future extensions.

# ADR-0005: Enforcer-Level Path Depth Cap

## Status

Accepted.

## Context

The policy format allows `pathDepth` up to 255 (1-byte field). `CalldataReader` traverses calldata based on a be16 path and does not require a depth cap to be correct. However, `PolicyEnforcer` targets a zero-allocation, predictable-gas hot loop when evaluating rules. Supporting unbounded depth forces either per-rule allocation (`bytes(depth * 2)`) or a worst-case preallocated buffer, both increasing gas and memory expansion costs for all calls — even when typical depths are small.

## Decision

`MAX_PATH_DEPTH` is an operational cap on the reference enforcer, not a wire-format rule. The default cap is 32 steps (64-byte scratch path buffer). The constant is declared in `PolicyFormat` alongside the other spec Section 9.1 normative limits.

**Separation of concerns:**
- The policy format (encoder) defines structural limits (byte sizes, field widths) and remains versioned.
- `CalldataReader` parses and traverses calldata generically — no depth limit in its config. Consumers enforce their own limits.
- `PolicyEnforcer` owns operational limits that impact its hot path.

**Enforcement strategy:**
- Prefer validating the cap at the trust boundary (policy ingestion/storage) to avoid per-call gas: a storage-time validator walks rules and checks `pathDepth <= MAX_PATH_DEPTH`.
- If storage-time validation is not guaranteed, include a single runtime check before locating the path: `require(depth <= MAX_PATH_DEPTH)`.

**Why runtime-only was chosen:** The enforcer must be self-shielding because it can be used offchain via `staticcall` against arbitrary policy bytes that bypass storage validation. Since the runtime `require` cannot be removed, a storage-time check in `Policy.validate()` provides only marginal gas savings. Proactive validation belongs in `PolicyValidator`, which operates at the same layer as the enforcer.

**Error taxonomy:** `error PathTooDeep(uint256 depth, uint256 maxDepth)` is defined in `CalldataReader` for reuse by all consumers. Structural errors (bounds, size fields) originate from `Policy`/`Descriptor`; semantic errors (unknown operator, context IDs) originate from the enforcer.

## Alternatives Considered

- **Unbounded depth (up to 255 by format):** Accept any format-valid policy depth. Rejected because it requires either per-rule dynamic allocation or a 510-byte worst-case preallocated buffer, regressing gas substantially on the hot path.
- **Higher fixed cap (e.g., 64 steps):** May be revisited after benchmarking if real-world ABIs commonly exceed 32 depth, but doubles the scratch buffer size for an undemonstrated need.
- **Lower fixed cap (e.g., 16 steps):** Covers practically all real-world ABIs and saves tens of gas of scratch-buffer allocation per call. Rejected because the cap is only safely tunable upward — lowering it later strands already-stored policies — so the initial value carries cheap headroom instead.
- **Adaptive fallback:** Keep the 32-step fast path; if `depth > MAX_PATH_DEPTH`, allocate a temporary buffer for that rule only. Preserves common-case performance while supporting deep paths. Not adopted initially to keep the hot loop branch-free, but remains a viable future extension.

## Consequences

- Single preallocated scratch buffer (64 bytes) reused across all rules, enabling a zero-allocation hot loop.
- Longest-common-prefix (LCP) reuse across path-sorted rules (see ADR-0002) minimises per-rule writes to the path buffer.
- Policies with paths deeper than 32 steps are rejected at runtime rather than silently degrading performance or overflowing the scratch buffer.
- `CalldataReader` remains a generic, reusable traversal library with no enforcer-specific constraints baked in.
- The cap can be raised in a future version without a format change — it is an operational limit (spec Section 9.1, Design category), not a wire-format field.

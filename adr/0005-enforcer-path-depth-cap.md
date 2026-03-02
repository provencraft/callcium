# ADR-0005: Enforcer-Level Path Depth Cap

## Status

Accepted.

## Context

The policy format allows `pathDepth` up to 255 (1-byte field). `CalldataReader` traverses calldata based on a be16 path and does not require a depth cap to be correct. However, `PolicyEnforcer` targets a zero-allocation, predictable-gas hot loop when evaluating rules. Supporting unbounded depth forces either per-rule allocation (`bytes(depth * 2)`) or a worst-case preallocated buffer, both increasing gas and memory expansion costs for all calls — even when typical depths are small.

## Decision

`MAX_PATH_DEPTH` is an enforcer-level implementation constraint, not a format rule. The default cap is 32 steps (64-byte scratch path buffer).

**Separation of concerns:**
- The policy format (encoder) defines structural limits (byte sizes, field widths) and remains versioned.
- `CalldataReader` parses and traverses calldata generically — no depth limit in its config. Consumers enforce their own limits.
- `PolicyEnforcer` owns operational limits that impact its hot path.

**Enforcement strategy:**
- Prefer validating the cap at the trust boundary (policy ingestion/storage) to avoid per-call gas: a storage-time validator walks rules and checks `pathDepth <= MAX_PATH_DEPTH`.
- If storage-time validation is not guaranteed, include a single runtime check before locating the path: `require(depth <= MAX_PATH_DEPTH)`.

**Why runtime-only was chosen:** Adding the check to `Policy.validate()` (the storage-time trust boundary) would require either importing the enforcer's constant (wrong-way dependency from a format library to a consumer) or duplicating it (divergence risk). The enforcer must also be self-shielding because it can be used off-chain via `staticcall` against arbitrary policy bytes that bypass storage validation. Since the runtime `require` cannot be removed, a storage-time check provides only marginal gas savings — not enough to justify the architectural coupling. If proactive validation is desired, the appropriate location is `PolicyValidator` or `PolicyCoder`, which operate at the same layer as the enforcer.

**Error taxonomy:** `error PathTooDeep(uint256 depth, uint256 maxDepth)` is defined in `CalldataReader` for reuse by all consumers. Structural errors (bounds, size fields) originate from `Policy`/`Descriptor`; semantic errors (unknown operator, context IDs) originate from the enforcer.

## Alternatives Considered

- **Unbounded depth (up to 255 by format):** Accept any format-valid policy depth. Rejected because it requires either per-rule dynamic allocation or a 510-byte worst-case preallocated buffer, regressing gas substantially on the hot path.
- **Higher fixed cap (e.g., 64 steps):** May be revisited after benchmarking if real-world ABIs commonly exceed 32 depth, but doubles the scratch buffer size for an undemonstrated need.
- **Adaptive fallback:** Keep the 32-step fast path; if `depth > MAX_PATH_DEPTH`, allocate a temporary buffer for that rule only. Preserves common-case performance while supporting deep paths. Not adopted initially to keep the hot loop branch-free, but remains a viable future extension.

## Consequences

- Single preallocated scratch buffer (64 bytes) reused across all rules, enabling a zero-allocation hot loop.
- Longest-common-prefix (LCP) reuse across path-sorted rules (see ADR-0002) minimises per-rule writes to the path buffer.
- Policies with paths deeper than 32 steps are rejected at runtime rather than silently degrading performance or overflowing the scratch buffer.
- `CalldataReader` remains a generic, reusable traversal library with no enforcer-specific constraints baked in.
- The cap can be raised in a future version without a format change — it is an enforcer configuration, not a wire-format field.

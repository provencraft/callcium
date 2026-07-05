# ADR-0004: Selectorless Policy Flag

## Status

Accepted.

## Context

Policies were locked to function calldata: the binary format embeds a 4-byte selector, the enforcer validates it before any rule runs, and the descriptor spec defined the initial read state as `head = 4, base = 4` (since generalized to a caller-supplied `baseOffset`, descriptor spec Section 6.2). Yet `CalldataReader.Config.baseOffset` already accepts `0` as a valid value, meaning the traversal engine is ABI-generic but the policy layer above it restricts it to selector-prefixed calldata only.

This creates a missed capability. Governance proposals, bridge payloads, and stored parameters are all plain `abi.encode(...)` blobs without a selector prefix. The descriptor traversal engine can already handle them, but there is no way to express a policy that targets raw ABI data.

## Decision

Use a flag bit (`FLAG_NO_SELECTOR = 0x10`) in the header byte. The first byte is redefined from a plain version number to a composite header:

```
Bit layout: [7:5] reserved | [4] FLAG_NO_SELECTOR | [3:0] version
```

When `FLAG_NO_SELECTOR` is set:
- The 4-byte selector slot (offset 1-4) must be zeroed for canonical encoding.
- The enforcer skips selector validation and uses `baseOffset = 0`.
- The registry stores the policy under `bytes4(0)` as the selector key.

When the flag is clear, behavior is identical to the original format.

## Alternatives Considered

- **Separate policy type (`RawPolicy`):** Clean separation, but duplicates the entire encode/decode/validate pipeline. Two format parsers to maintain, two code paths in the enforcer. Rejected for unnecessary complexity given the formats are identical except for the selector field.
- **Variable-offset header:** Stores `baseOffset` directly, removing the selector field. Breaks all fixed-offset accessors (`descriptor`, `groupCount`, `groupAt`) because field positions shift. Every accessor would need to read the header first to compute offsets. Rejected for high implementation cost and fragility.
- **`FLAG_HAS_SELECTOR` (opt-in selector):** Inverts the default so the flag signals presence rather than absence. Rejected because existing blobs have header byte `0x01` (version 1, no flags set), which would be interpreted as "no selector" under this scheme, breaking backward compatibility. The flag-absent-means-present convention (`FLAG_NO_SELECTOR`) ensures existing policies decode correctly without migration.

## Consequences

- Existing policies are fully backward compatible.
- Three reserved flag bits (5-7) remain available for future extensions.
- The selector slot is always present in the wire format at fixed offset 1, preserving all existing accessor offsets. For selectorless policies it must be zeroed, ensuring deterministic hashing.
- `bytes4(0)` is used as the registry key for selectorless policies. This value cannot collide with real function selectors in practice.

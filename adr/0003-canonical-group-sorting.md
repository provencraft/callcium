# ADR-0003: Canonical Group Sorting

## Status

Accepted.

## Context

A DNF policy contains multiple groups with OR semantics. The question is whether groups should preserve user-defined order (allowing manual control of evaluation priority) or be sorted deterministically (enabling canonical encoding).

## Decision

Groups are sorted by `keccak256(sortedRules)` to ensure canonical encoding.

While this removes user control over evaluation order, the benefits outweigh the costs:
- **Deterministic blob identity** for governance and deduplication.
- **Interoperability** across builder implementations.
- **Consistent audit trail** via blob hashing.

The performance impact is minimal relative to calldata traversal. Users should focus on rule design for performance (call-level checks first, path-sorted calldata rules). The group hash is not serialized; it is derivable from the on-wire bytes.

## Alternatives Considered

- **User-defined group order:** Preserve insertion order so authors can control which group is evaluated first. Rejected because it sacrifices deterministic blob identity, breaks interoperability across builder implementations, and prevents governance-level deduplication via blob hashing. The performance impact of evaluation order is minimal relative to calldata traversal.

## Consequences

- Byte-for-byte reproducibility: any conformant builder produces identical blobs for the same logical policy.
- No user control over which group is evaluated first — all orderings produce the same boolean result (OR semantics).
- Policy identity (`keccak256(blob)`) is stable across builder implementations, enabling governance comparisons and deduplication.

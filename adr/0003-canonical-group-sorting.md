# ADR-0003: Canonical Group Sorting

## Status

Accepted.

## Context

A DNF policy contains multiple groups with OR semantics. The question is whether groups should preserve user-defined order (allowing manual control of evaluation priority) or be sorted deterministically (enabling canonical encoding).

## Decision

Groups are sorted by `keccak256(sortedRules)` to ensure canonical encoding. Groups have OR semantics, so no ordering changes which groups can pass; the canonical sort additionally fixes a single, portable evaluation order and makes blob identity deterministic. The group hash is not serialized; it is derivable from the on-wire bytes.

## Alternatives Considered

- **User-defined group order:** Preserve insertion order so authors can control which group is evaluated first. Rejected because it sacrifices deterministic blob identity, breaks interoperability across builder implementations, and prevents governance-level deduplication via blob hashing. The performance impact of evaluation order is minimal relative to calldata traversal.

## Consequences

- Byte-for-byte reproducibility: any conformant builder produces identical blobs for the same logical policy, so policy identity (`keccak256(blob)`) is stable across implementations, enabling governance comparisons and deduplication.

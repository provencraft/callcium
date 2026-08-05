# ADR-0014: Reserved Zero Type Code

## Status

Accepted.

## Context

Type code `0x00` currently encodes `uint8`. The type-code table is the one value domain in the system where zero is meaningful: the policy format already reserves opCode `0x00` as unassigned and rejected (policy spec Section 5.6), but a zero type code parses as a valid type and evaluation proceeds.

This aliasing is a standing hazard in an EVM implementation, where memory and storage zero-initialize: a forgotten struct write, a zeroed field, or a garbage read at a wrong offset all produce `0x00` and silently continue as `uint8` instead of failing loudly. Reserving zero also gives the format a natural "no type" value for any field that must encode absence.

## Decision

**Type code `0x00` is reserved and invalid.** Validators MUST reject it wherever a type code is read. Only the ranges the reservation displaces move — a chain that ends where the first gap absorbs it: `uintN` takes `0x01`, pushing `uint256` onto `int8`'s slot, pushing `int256` onto `address`'s, pushing the fixed group into the reserved gap at `0x44`:

| Range | v1 | v2 | Derivation |
| --- | --- | --- | --- |
| `uintN` | 0x00–0x1F | 0x01–0x20 | `N / 8` |
| `intN` | 0x20–0x3F | 0x21–0x40 | `0x20 + N / 8` |
| `address`, `bool`, `function` | 0x40–0x42 | 0x41–0x43 | — |
| `bytesN`, `bytes`, `string` | 0x50–0x6F, 0x70, 0x71 | unchanged | `0x50 + N − 1` |
| arrays, tuple | 0x80, 0x81, 0x90 | unchanged | — |

## Alternatives Considered

- **Keep `0x00 = uint8` and rely on contextual discrimination**: rejected. Every zero-initialized or garbage type code remains a valid `uint8` forever; the hazard is permanent and each consumer must reason about it separately.

## Consequences

- Zero-initialization defects — forgotten writes, zeroed structs, misaligned reads — surface as validation failures instead of proceeding as `uint8`.
- The relayout forces the descriptor format version to `0x02` — a v1 parser reading v2 codes would misclassify types silently rather than fail. Parsers are v2-only (`0x01` reverts `UnsupportedVersion`, the v1 spec is deleted in favor of `descriptor-v2.md`, no migration tooling ships); every type-code consumer in both mirrors renumbers the moved ranges, all descriptor-embedding conformance vectors regenerate, and descriptor hashes change.

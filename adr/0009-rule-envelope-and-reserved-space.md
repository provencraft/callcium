# ADR-0009: Rule Envelope And Reserved Space

## Status

Accepted.

## Context

An extension can only assign values or shapes that the core's validation rejects (ADR-0003). So every planned rule kind,
quantifier, path step and hop kind, listed below, needs a place in the format that the core freezes. Fields with no
planned use stay rejected as headroom.

Rule kinds differ in payload. A test contains a path, a hint and an operator. A loop contains a frame and a body
(ADR-0008). The header has no free bit (ADR-0003), so a policy-wide option cannot be a header flag.

## Decision

**Every rule is `ruleSize (2) | scope (1) | payload`, and each `scope` defines its payload layout.** A new rule kind
adds a layout and does not change an existing one. `ruleSize` frames each rule. So storage checks each rule's extent
byte-locally. The enforcer also skips a loop body that it does not read in one step, as under `ALL` over an empty array.

`scope` values: `0x00` context test, `0x01` calldata test, `0x02` loop (ADR-0008).

The core reserves the values below, and storage validation rejects them until an extension assigns them:

- **`scope` `0x03`–`0xFF`**: the OR rule, aggregates, a test that reads an outer element, decode, and a root-level
  option rule.
- **`quantifier` `0x03`–`0xFF`**: `COUNT`, with its parameter after the `quantifier` byte. `0x00` is invalid and is
  never assigned.
- **Path steps `PATH_MARKER_BASE` to `0xFFFF`**: 16 markers that name an enclosing loop's position, for parallel arrays.
  The other values stay reserved for markers that no extension plans yet.
- **Hop `index` `0xFF00`–`0xFFFE`**: `0xFFFE` for an element hop that an enclosing loop's position indexes.
- **Hint header bits 7–6**: no planned use.

Path steps below `PATH_MARKER_BASE` are field and element indices (`Path.indicesOnly`). PV-2 bounds field and
static-array indices, and only `PATH_MARKER_BASE` bounds a dynamic-array index. A hop `index` from `0x0000` to `0xFEFF`
is an element index, and `0xFFFF` is a plain hop.

The enforcer dispatches on `scope`, `quantifier` and hop `index`. So an unassigned value in one of these fields also
leaves evaluation undefined (ADR-0002).

## Alternatives Considered

- **Leaving the whole step range to indices until an extension needs markers**: rejected. Position markers must appear
  in the core's test and loop paths, so they must be step values. A marker-capable scope per rule kind would duplicate
  each core layout. A later carve-out of markers from the index range changes the meaning of index values that stored
  blobs can use. This is not an addition (ADR-0003).

## Consequences

- Every rule pays 2 bytes of `ruleSize`.
- The largest element index is `PATH_MARKER_BASE` − 1. An element index into a dynamic array past this value is
  inexpressible.
- The storage validators of both implementations reject each reserved value, and conformance vectors pin each rejection.
- An extension's payload lives inside one rule and shares the 65,535-byte `ruleSize` cap.

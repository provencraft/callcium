# ADR-0004: Selectorless Policy Flag

## Status

Accepted.

## Context

A policy constrains ABI-encoded data. Function calldata contains a 4-byte selector before its arguments. Governance
proposals, bridge payloads and stored parameters are plain `abi.encode(...)` blobs without a selector. Locating the
values is the same problem in both cases, with a different base offset.

## Decision

**Header bit 0 is `FLAG_NO_SELECTOR`** (ADR-0003). If the flag is set, the 4-byte selector slot is present and zero, so
every later field keeps its offset. The enforcer skips the selector check and reads arguments from offset 0 instead of
offset 4. If the flag is clear, the enforcer requires the calldata to start with the policy's selector. A zero slot
alone cannot mark a selectorless policy, because `0x00000000` is a valid selector.

Storage validation rejects a selectorless blob whose selector slot is not zero. This gives one encoding, and so one
hash, per policy (ADR-0003), for a 4-byte comparison at store time (ADR-0002).

## Alternatives Considered

- **A separate policy type for raw ABI data**: rejected. The two formats differ only in the selector. A second type
  duplicates the encoder, decoder, validator and enforcer paths.
- **A variable-offset header that drops the selector slot when the flag is set**: rejected. It saves 4 bytes per
  selectorless blob. But then every field offset after the header depends on the flag. This affects the enforcer and
  every reader of the descriptor, the group count and the groups.

## Consequences

- Every selectorless blob contains four zero bytes.
- Both enforcers take the base offset from bit 0. Both storage tiers reject a nonzero slot under the flag. The
  conformance vectors cover both settings of the flag.

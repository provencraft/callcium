# ADR-0005: Reserved Zero Type Code

## Status

Accepted.

## Context

The descriptor's type codes name ABI types, and policies carry them in hints. In an EVM implementation, memory and
storage zero-initialize. A forgotten struct write, a zeroed field or a read at a wrong offset can produce `0x00`. If
`0x00` names a type, a validator that reads such a defect accepts it as that type.

## Decision

**Type code `0x00` is reserved and invalid. Every validator rejects it wherever the validator reads a type code.** The
type codes start above `0x00`, with `uintN` at `N / 8`, so `uint8` is at `0x01`. The descriptor spec's type-code table
assigns the other codes.

## Alternatives Considered

- **`uintN` at `N / 8 − 1`, so `uint8` takes `0x00`**: rejected. Every zero-initialized type code that a validator reads
  stays a valid `uint8`, and each consumer must reason about the hazard separately.

## Consequences

- A zero-initialization defect shows as a validation failure wherever a validator reads the code. It does not pass as
  `uint8`.
- One of the 256 codes is permanently unavailable.
- Both implementations reject `0x00` in descriptors and in hint target blocks. The descriptor vector
  `reserved-zero-type-code` and the policy vector `hint-target-undefined-type` pin the rejection.

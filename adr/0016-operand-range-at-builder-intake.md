# ADR-0016: Operand Range At Builder Intake

## Status

Accepted.

## Context

A constant is as wide as the compared type (ADR-0013). So a value outside the type's range has no encoding. The
exception is a `bool` above 1, which build-time validation rejects. Authors write constants as values before the builder
knows the target type. `lte(-5n)` and `lte(cap - spent)` are bigints, and TypeScript `bigint` arithmetic is unbounded,
so an underflowing cap is a natural spelling. If the builder truncates such a value to the type's width, it encodes a
different bound without a trace.

Only `PolicyBuilder.add()` has both the value as written and the target type. An encoded operator contains only bytes.

## Decision

**`PolicyBuilder.add()` rejects every constant that its target type cannot represent**, in both builders. The SDK throws
`OUT_OF_PHYSICAL_BOUNDS`, and `PolicyBuilder.sol` reverts `OutOfPhysicalBounds`. A context target's type is its
property's declared type.

- **Numbers** must lie in the target's range: `uintN`, `intN`, `address` and `bool` targets.
- **Masks** must lie in `[−1, 2^(8w) − 1]` for a width of `w` bytes: a non-negative pattern within the width, or `−1`
  for the all-ones mask. An author writes a mask on a signed target as its bit pattern, `0x80` on `int8`, not `−128`,
  because a mask reads two's-complement bits (ADR-0014). `−1` stays the all-ones mask on every target.
- **Lengths** must fit their 4-byte encoding.
- **Byte strings** other than masks must have the type's width: `bytesN` and `function` targets.

The rejection is a throw, not an issue. An issue says that a policy is invalid. A throw says that the input is outside
the entry point's contract. A value that the type cannot represent is such an input. The rejection joins the intake
rejections that `add()` raises.

## Alternatives Considered

- **Truncating to the width**: rejected. `lte(-5n)` on a `uint8` would encode `lte(251)`, and `bitmaskAll(0x100n)` would
  encode an empty mask that every value passes. These policies approve what their authors wrote them to block.
- **Masks in the signed range on signed targets**: rejected. `0x80`, the sign bit of `int8`, would be out of range and
  need `−128`, so one mask would take different literals on `int8` and `uint8`.
- **An issue from `PolicyValidator`**: rejected. Outside `bool`, a constant outside its type's range has no encoding, so
  the validator never sees one.
- **Signed and unsigned method variants in the SDK**: rejected. A variant offers nothing that `add()` lacks, because
  `add()` receives the value and the target type. A variant also leaves the width unchecked.

## Consequences

- The author gets a throw from `add()` instead of a policy that approves what the author wrote it to block. Both
  builders reject the same inputs under the same name.
- `buildUnsafe()` does not bypass the rejection, because the input never becomes a draft.
- The builder API is the coverage. A constraint assembled from encoded bytes has no value as written. Storage and
  build-time validation check its widths and `bool` values only.
- The builder API is not part of the conformance surface that the vectors pin, because the vectors contain encoded
  policies. Both implementations keep unit tests.

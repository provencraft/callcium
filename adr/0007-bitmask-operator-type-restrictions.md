# ADR-0007: Bitmask Operator Type Restrictions

## Status

Accepted.

## Context

Bitmask operators (`BITMASK_ALL`, `BITMASK_ANY`, `BITMASK_NONE`) check whether specific bits are set, clear, or present in a value. The question is which types these operators should accept. The full set of 32-byte static elementary types includes unsigned integers, signed integers, fixed-byte types (`bytes1`–`bytes32`), `address`, and `bool`.

ABI encoding uses different padding directions depending on the type family. Numeric types (`uint*`, `int*`) and `address` are left-padded (value occupies the rightmost bytes of the 32-byte word). Fixed-byte types (`bytes1`–`bytes31`) are right-padded (value occupies the leftmost bytes). `bytes32` fills the entire word with no padding. Signed integers use sign extension, where negative values fill leading bytes with `0xFF`.

## Decision

Bitmask operators are restricted to unsigned integer types (`UINT*`) and `bytes32` only. Signed integers, `bytes1`–`bytes31`, `address`, `bool`, and all other types are forbidden.

- **Unsigned integers** have consistent right-alignment. A mask `0x0F` always targets the lowest 4 bits of the value regardless of the uint width. Mask semantics are intuitive and portable across uint sizes.
- **`bytes32`** fills the entire 32-byte word with no padding. Masks operate on the raw bytes with no alignment ambiguity.
- **`bytes1`–`bytes31`** are right-padded in ABI encoding, so the value occupies the leftmost bytes. A bitmask would need to be left-aligned to target value bits — the opposite convention from unsigned integers. Supporting both alignment conventions in the same operator family would create confusing, error-prone semantics.
- **Signed integers** use sign extension. The leading bytes of the 32-byte word are `0x00` for non-negative values and `0xFF` for negative values. This makes mask results value-dependent: `bitmaskAll(0xFF000..0)` would pass for all negative numbers but fail for all non-negative numbers, which is rarely the intended semantics.

## Alternatives Considered

- **Allow all 32-byte static types:** Maximally permissive, but forces policy authors to reason about padding direction and sign extension when writing masks. High risk of subtle bugs in production policies.
- **Allow fixed-byte types with left-aligned masks:** Introduce a convention where masks for `bytesN` types are left-aligned while masks for `uintN` types are right-aligned. Rejected because having two alignment conventions in the same operator family is confusing and error-prone.
- **Restrict to `uint256` and `bytes32` only:** Even narrower than the chosen option. Rejected because smaller uint widths have the same right-aligned semantics as `uint256` — there is no ambiguity to avoid.

## Consequences

- Policy authors can rely on a single mask alignment convention (right-aligned, matching unsigned integer encoding) for all bitmask operations.
- Policies that need to check bit patterns in `bytes1`–`bytes31` values must use `EQ` or `IN` operators instead. This is a minor expressiveness limitation.
- Policies cannot use bitmask operators on signed integers. Bit-level checks on signed values are rare in practice and can be expressed using range operators or equality checks.

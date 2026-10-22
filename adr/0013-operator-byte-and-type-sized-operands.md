# ADR-0013: Operator Byte And Type-Sized Operands

## Status

Accepted.

## Context

An operator applies a comparison to a target and to the values that it compares against. Those values come from
different places: constants in the blob, a context property and, with planned extensions, a value elsewhere in the
calldata. Planned comparisons add prefix and hash tests on `bytes` and `string`, and more can follow (ADR-0003). If each
source has its own family of operator codes, every comparison is copied once per source.

Equality against a context property cannot express a bound, such as an amount under `msg.value` or a deadline under
`block.timestamp`. These bounds need order.

A negation flag on every comparison gives some tests two spellings: `NOT GT` and `LTE`.

Most compared types are narrower than a word. A 32-byte constant for an `address` contains 12 bytes of padding, and for
a `uint8` it contains 31. A context property ID needs 2 bytes but would take 32. A word wider than its type also can
contain values that the type cannot represent, and validation must then reject them.

A `GTE` and `LTE` pair in a loop body walks the array once (ADR-0008). So a range comparison must earn its codes on cost
and on what the pair cannot express.

## Decision

**An operator is `opCode (1) | dataLength (2) | data`, with `opCode := NOT (bit 7) | source (bits 6–5) | comparison
(bits 4–0)`.**

`source` values:

- `00`: constants.
- `01`: a context property. Its 2-byte ID is the data.
- `10`: reserved for a value elsewhere in the calldata.
- `11`: reserved for expression operands, outside current planning.

`comparison` values:

- `0x00`: invalid.
- `0x01`–`0x07`: `EQ`, `GT`, `LT`, `GTE`, `LTE`, `BETWEEN`, `IN`.
- `0x10`–`0x12`: `BITMASK_ALL`, `BITMASK_ANY`, `BITMASK_NONE`.
- `0x18`–`0x1D`: `LENGTH_EQ`, `LENGTH_GT`, `LENGTH_LT`, `LENGTH_GTE`, `LENGTH_LTE`, `LENGTH_BETWEEN`.
- `0x08`–`0x0F`: reserved for prefix and hash tests on `bytes` and `string`.
- `0x13`–`0x17` and `0x1E`: reserved.
- `0x1F`: reserved escape. The first 2 bytes of data name an extended comparison.

Storage rejects every reserved `source` and `comparison` value, so an extension can assign it as an addition (ADR-0003).

**A context source applies to `EQ`, `GT`, `LT`, `GTE` and `LTE` only, and storage rejects it with any other
comparison.** These are the comparisons that take one word. `IN` and `BETWEEN` take several values, and a property's
word is neither a mask nor a length. The enforcer evaluates a context source under these five comparisons alone, so
another pairing would leave evaluation undefined (ADR-0002).

**NOT is canonical only where no positive comparison expresses the negation** (`Comparison.negation?`). Elsewhere,
normalization rewrites it away (`Operator.normalize`).

**The format contains `BETWEEN` and `LENGTH_BETWEEN`.** A range reads its target once, as one rule. A `GTE` and `LTE`
pair reads it twice, as two rules.

**A constant is as wide as the compared type:**

- `uintN` and `intN`: N/8 bytes. The comparison sign-extends `intN`.
- `address`: 20 bytes.
- `bool`: 1 byte.
- `bytesN`: N bytes, compared left-aligned. `function`: 24 bytes, compared left-aligned.
- A length: 4 bytes.

A mask is a bit pattern of the width of its type. `BETWEEN` contains two values. `IN` contains one or more values, in
strictly ascending order as compared words, unsigned. `dataLength` equals the width times the count.

For a calldata test, storage validation checks `dataLength` against the width of the hint's type code. For a context
test, it checks `dataLength` against the width of the property's declared type. It also checks the order of `IN`, and
that a context source names a defined property. Every byte string of the width is a value of the type, except a `bool`
operand above 1, which build-time validation rejects.

A narrow constant costs a shift per load or `IN` probe. A left-aligned or signed type costs a second shift or a sign
extension. At storage, each byte removed saves 200 gas of code deposit. An `address` operand saves 12 bytes.

## Alternatives Considered

- **A family of operator codes per source**: rejected. Each new source copies the comparisons that it applies to. With a
  `source` field, a comparison has one definition, and a source costs one of four values.
- **A context source under `EQ` only**: rejected. This cannot bound an amount under `msg.value` or a deadline under
  `block.timestamp`.
- **32-byte constants for every type**: rejected. Loading needs no extra work. But every narrow constant puts padding
  into every stored blob, and every narrow integer type accepts constants outside its range that validation must catch.
- **Negated codes instead of a NOT bit**: rejected. This removes the two spellings. But six codes (`NEQ`, `NOT_IN`,
  `NOT_BETWEEN`, `NOT_BITMASK_ALL`, `LENGTH_NEQ`, `NOT_LENGTH_BETWEEN`) would take all six unplanned comparison codes,
  `0x13`–`0x17` and `0x1E`. Every future comparison would also need a twin, including prefix and hash tests and every
  extended `0x1F` comparison. One bit gives each comparison its negation. The bit that negated codes would free has no
  planned use.
- **No range comparison, a `GTE` and `LTE` pair instead**: rejected. Under `ALL`, `NOT BETWEEN` is the only way to say
  "outside a range" while a body contains no disjunction, because `∀i.(x < a ∨ x > b)` does not split into groups. Also,
  the pair resolves the value twice per element, where `BETWEEN` resolves it once.

## Consequences

- An `IN` set of addresses is 37.5% smaller than a set of words.
- A constant outside its type's range has no encoding, except a `bool` above 1. So builders must reject it before
  encoding.
- An argument can have a bound that is known only at call time, instead of a literal that the builder sets. That operand
  names a property, not a value. So bound analysis reads a context-bounded rule only through how it orders the subject
  against that property. Rules that contradict through a test on the property itself (`x > 10`, `x < ctx(t)`, `ctx(t) <
  5`) pass validation and fail at enforcement.
- The comparison field has 31 codes, 15 of them reserved, with 65,536 extended IDs behind `0x1F`. `source` has no
  escape. A fifth operand source takes a major version (ADR-0003).
- Both implementations contain the operator coder, the storage checks, the build-time checks and narrow-constant
  evaluation. Conformance vectors pin each reserved-value rejection and each context-pairing rejection, and contain
  narrow constants.

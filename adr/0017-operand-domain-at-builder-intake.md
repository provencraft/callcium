# ADR-0017: Operand Domain At Builder Intake

## Status

Accepted.

## Context

A constraint method encodes its operand into a 32-byte word before any target type is known, in two's complement. A negative operand and its unsigned alias therefore produce identical bytes: `lte(-5n)` and `lte(2n ** 256n - 5n)` are one operator. Nothing downstream can separate them, because the constraint carries only bytes.

Where the word lands decides whether the mistake survives. A negative operand on a narrow unsigned target encodes near `2 ** 256`, far outside that type's domain, and `PolicyValidator` reports `OUT_OF_PHYSICAL_BOUNDS` (PV-5). On a full-width target there is no room above the domain to land in, so the same mistake validates clean, and a spending cap computed as `cap - spent` that underflows builds without an issue and caps the argument just below the largest value it can take. TypeScript makes that the natural spelling: `bigint` subtraction is unbounded, where Solidity's `uint256` subtraction panics before a policy exists.

The information separating the two cases exists only at the call site, in the literal the caller wrote.

## Decision

Both builders retain the operands as written, and `PolicyBuilder.add()` rejects one that two's complement folds onto a value the target admits: the SDK throws `OUT_OF_PHYSICAL_BOUNDS`, `PolicyBuilder.sol` reverts `OutOfPhysicalBounds`. The path walk `add()` already performs returns the type code it lands on, and a context path resolves to its property's declared type.

- **The record is two numbers, not a list.** Each value operator folds its operands into the most negative and the greatest the builder has seen. They suffice because an operand can only fold into the range from below or from above, and whichever reaches furthest arrives first: an unsigned target asks whether any operand was negative, a signed target whether the greatest reaches the word of that type's own minimum, which is the raw bound `getDomainLimits` returns. The proof leans on operands being confined to one word, enforced by `toOperandValue` in the SDK and by the parameter types in Solidity.
- **Each tree keeps the record where its constraint type already lives.** `Constraint.sol` adds two fields to the struct, and they travel with every copy of it. The SDK's `Constraint` is a structural type a caller spells by hand, so widening it would put authoring state into the shape every consumer reads; the operands live in a `WeakMap` keyed on the `ConstraintBuilder` instead, read back through `readOperandExtremes`.
- **The guard covers the folded case only.** An operand whose word the target also cannot hold survives encoding intact and stays a PV-5 issue, so `validate()`, its issue list and the `buildUnsafe()` bypass keep their coverage for everything but the alias.
- **Only operands the target reads as numbers are recorded.** The value operators qualify. A mask is a bit pattern, and `bitmaskAll(-1n)` is the idiomatic spelling of the all-ones mask that `Constraint.sol` can only write as `type(uint256).max`; checking masks also pre-empted `BITMASK_ON_INVALID`, which is the real fault on a signed target. Length operands carry their own domain, a context property ID names a property, and a `bytes32` target holds no number.
- **An unrecorded operand is unknown, not unsigned.** `addOp` writes bytes directly and records nothing, so raw bytes reading as a legal value are left alone. Treating them as unsigned would reject `addOp(EQ, all-ones)` on an `int256` target, which is a valid `-1`.
- **A throw, not an `Issue`.** Per ADR-0006 an `Issue` says a policy is inadmissible; a throw says the input is outside the entry point's contract. A bound the target's domain cannot describe is the latter, and it joins the intake rejections `add()` already raises. The error reuses the invariant's existing name.

## Alternatives Considered

- **Signed and unsigned method variants mirroring `Constraint.sol`'s overloads:** Rejected. TypeScript cannot overload on sign, so it means new method names or a mode selector; it asks the caller to restate a domain the descriptor already fixes, and still admits the mismatch when the caller picks the wrong variant.
- **Packing the origin into the operator bytes:** Rejected. Those bytes are the wire form; rule identity (PV-4) and rule order (PC-2) are built on them, and a spare opcode bit would have to be stripped by the encoder, the validator and both comparisons.
- **Replacing `bytes[] operators` with an array of structs:** Rejected. It binds the origin to its operator by construction, but changes the shape every consumer of `PolicyData` reads, for a guarantee two unindexed numbers already give.
- **Reporting an `Issue` from `PolicyValidator` instead:** Rejected. The validator reads encoded policy data, in which the two spellings are the same bytes, so no analysis there can separate them. Threading the operands as written into `PolicyData` would put authoring state into the type the coder and enforcer read.

## Consequences

- The author gets a throw on the line carrying the bug instead of a policy that approves what it was written to block. Both builders reject the same inputs and name the fault alike; the hazard is less reachable in Solidity, where only a deliberate `int256` detour arrives at it.
- Coverage is the fluent API only, and narrower in the SDK than in Solidity. A constraint assembled from encoded bytes carries no operand as written and is checked by `PolicyValidator` alone. A Solidity constraint keeps its record through any copy of the struct, where the SDK's is bound to the builder instance, so rebuilding the object around the operators (`add({ ...builder })`) drops it. This is narrower than universal closure, and is an author's convenience rather than an invariant.
- The record describes what was written, not what the constraint now holds. Nothing in it is indexed by operator, so reordering or removing operators cannot misattribute an operand, and equally cannot lift a rejection already earned. Editing that drops the matching origin is unsupported, and two numbers could not express it.
- A constraint with several folded operands names the one reaching furthest past the range. The rejection and the error name do not depend on which; the reported operand and the Solidity revert arguments do.
- `buildUnsafe()` does not bypass the rejection, because the input never becomes a draft. Solidity's `Constraint` gains two fields, so a caller constructing the struct literally must supply them; the SDK's type is unchanged, and a hand-built `Constraint` carries no record.
- No conformance vector can pin this: a vector carries policy data, where the operand as written is already gone. Both implementations keep unit tests instead.

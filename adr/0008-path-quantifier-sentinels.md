# ADR-0008: Path Quantifier Sentinels

## Status

Accepted.

## Context

Policies must constrain the elements of a variable-length array: every element satisfies a predicate, or at least one does. Concrete indices express neither — a rule on indices 0 through 4 says nothing about index 5 — so quantification needs an encoding of its own.

Two questions follow. Whether quantification belongs to the operator or to the path. And which quantifiers the vocabulary carries: a universal quantifier admits two readings of the empty array, vacuously true or false, and they are not interchangeable at the point of use.

## Decision

**Quantification is a property of the path**, encoded as reserved index values rather than operator variants:

```solidity
uint16 constant ALL = 0xFFFF;  // universal, vacuously true on an empty array
uint16 constant ANY = 0xFFFE;  // existential, false on an empty array
```

A quantifier step is valid only immediately after an array node, and a path carries at most one. Indices at or above `ANY` are reserved and never appear as concrete element indices.

Encoding quantification in the path keeps it orthogonal to the operator: any operator combines with any quantifier, and every rule keeps the same `(scope, path, opCode, data)` shape regardless.

**The vocabulary carries two quantifiers.** Strict universality — every element satisfies the predicate and the array is non-empty — is expressed by composing a length constraint with `ALL` in the same group. Rules within a group are conjunctive (ADR-0001) and both failure modes are group-local, so the composition and a dedicated sentinel yield the same verdict on every input.

Which universal form is primitive is not a symmetric choice. Strict universality follows from vacuous truth by adding one rule to the same group. Vacuous truth follows from strict universality only by disjunction, which requires a second group into which every other rule of the first must be duplicated. The composable primitive is the vacuous one.

## Alternatives Considered

- **Separate opcodes per quantifier**: rejected. It treats quantification as a property of the operator, multiplying the opcode table by the quantifier count and breaking the uniform rule layout.
- **A third sentinel for strict universality**: rejected. It is derivable within a single conjunctive group at the cost of one rule, while carrying it costs a three-way decode of the quantifier kind and a dedicated empty-array branch in every evaluation of every quantified rule.
- **Carrying strict universality as the primitive instead of the vacuous form**: rejected. The derivation runs one way only, so recovering vacuous truth would cost a duplicated group rather than a single added rule.

## Consequences

- Any operator combines with any quantifier, and rules keep one layout whether or not they quantify.
- A strict-universal constraint costs one additional rule in its group. Its empty-array failure surfaces as a failed length constraint, naming the cause the author wrote.
- Evaluation separates universal from existential with a single flag, which serves as both the verdict for an empty array and the polarity of the iteration loop's short-circuit test.
- Quantifier steps are evaluator markers, never element indices, and are not passed into calldata navigation.
- Concrete array indices are bounded below the reserved range, which exceeds any array length an enforcer will iterate.

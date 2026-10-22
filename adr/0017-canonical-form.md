# ADR-0017: Canonical Form

## Status

Accepted.

## Context

A policy's identity is `keccak256(blob)`. It is the registry key and what governance compares. One formula has many
spellings:

- Rules in a group, and groups in a policy, in any order.
- Repeated rules.
- Two `ALL` loops over one array, beside one loop with both bodies.
- A context test inside an `ANY` body, beside the same test outside it (ADR-0008).
- `NOT GT` beside `LTE`.
- `IN [v]` beside `EQ v`.
- `GTE a` with `LTE b`, beside `BETWEEN(a, b)` (ADR-0013).
- A context test that compares two properties, with either property as the subject.

Unless the builder picks one spelling, equal policies hash apart.

The Lean model's formulas contain no signature. The bytes contain hints, sizes and operand widths that depend on the
signature. Build-time validation reads the formula that the builder encodes (ADR-0002). So a rewrite that the builder
applies before validation can hide a defect that validation exists to report. Every rewrite is also a rule that every
third-party encoder must reproduce to match a policy's hash.

## Decision

**The builder normalizes a formula before it encodes the formula, and build-time validation applies to the normalized
formula** (`Formula.WellFormed`). Over one signature, two well-formed policies get the same bytes exactly when their
normalized formulas are equal.

**Ordering, dropping repeats and joining loops give each formula one spelling of its members. A further rewrite belongs
in normalization only if it passes three gates. Anything else stays as written, and validation reports it where it is a
defect.**

1. Its equivalence proof needs no type, width or signedness fact.
2. It fires deterministically on syntax alone and commutes with ordering, dropping repeats and joining loops. So
   `normalize` stays idempotent, and its fixed points stay the canonical forms (`normalize_idem`, `normal_iff_fixed`).
3. Every defect that validation reports on the authored formula remains reportable on the normalized formula.

The rewrites (`normalize`) form a closed table:

- **Order.** Bodies normalize first. Rules in a group or a body sort ascending by their bytes with every `ruleSize`
  (ADR-0009) removed, nested ones included. Root groups sort ascending by the concatenation of those bytes over their
  rules.
- **Repeats.** The builder drops a repeated rule in a group or a body, and a repeated root group.
- **Joins.** `ALL` loop rules over one array in one group join into one loop rule by concatenation of their bodies.
  `ANY` loop rules stay apart, as independent existentials.
- **Subjects.** A context test against another context property takes the lower property ID as its subject, with the
  comparison flipped.
- **Negation.** The builder rewrites NOT away where a positive comparison expresses it (ADR-0013).
- **Hoisting.** A context test in an `ANY` body that also contains a test that reads the element moves into the
  enclosing group, `∃i.(P ∧ Q(i)) ≡ P ∧ ∃i.Q(i)`. It then runs once instead of once per element.
- **One-member sets.** `IN [v]` becomes `EQ v`, with NOT kept. It costs one comparison instead of a set probe.
- **Range pairs.** Exactly one unnegated constant `GTE a` and one `LTE b` on one subject in a group or a body become
  `BETWEEN(a, b)`. Exactly one `LENGTH_GTE` with one `LENGTH_LTE` become `LENGTH_BETWEEN`. The range is defined as the
  pair (`Comparison.apply`) and resolves the value once.

In the **Order** rewrite, a rule's bytes without sizes delimit themselves. So a comparison of two concatenations
compares groups rule by rule, and one lexicographic byte comparison serves rules and groups. Over one signature, this
order is the order of `Rule.key`, because equal paths have equal hints and operand widths. `scope` leads. So context
tests come first in every group, and groups that start with a context test come first in the policy.

The gates leave three cases with validation. The first is a body that contains only context tests (gates 1 and 2,
ADR-0008). The second is more than one bound on a side, because the choice of the binding bound needs signedness. The
third is every contradiction, vacuity and redundancy, because their removal would erase the defect.

**Normalization is a builder obligation, and no tier checks it** (ADR-0002). No rewrite changes the denotation
(`normalize_holds`). On calldata that is not canonical or exceeds a limit, the order that normalization gives decides
which abort, if any, ends evaluation (ADR-0012). Otherwise the verdict is the denotation's verdict
(`evaluateValues_exact`). So storage accepts a well-formed blob in any spelling, and the enforcer evaluates it as its
bytes give.

**In Lean, `normalize` sorts by the signature-free `Rule.key`.** `Rule.key` serializes a rule in the field order of the
wire. It is prefix-free (`Rule.key_append_inj`) and injective (`Rule.key_injective`). Over `Rule.key`, normalizing keeps
limits (`normalize_withinLimits`) and is idempotent (`normalize_idem`). It erases authoring order and repetition at
every level (`normalize_of_sameMembers`). Its fixed points are exactly the canonical forms (`normal_iff_fixed`).

The wire model owes the rest before the first release. The encoder encodes the normal form, and decoding an encoding
yields the normal form. A proof must show that the size-free byte order agrees with the key, and that equal bytes imply
equal normal forms.

## Alternatives Considered

- **Sorting groups by the hash of their rule bytes**: rejected. The builder hashes every group for a second comparison
  beside the byte order that rules use. A hash order also does not put groups that start with a context test first.
- **Sorting by the bytes after each rule's own `ruleSize`, nested sizes included**: rejected. This saves the removal of
  sizes before a comparison. But it orders loops by the sizes of their body rules wherever those differ. So the wire
  order departs from `Rule.key`, and the wire model needs a reordering step with a theorem of its own.
- **Rejecting repeated rules**: rejected. Joining loops repeats a rule that the author wrote once in each loop: `ALL`
  over `{t, a}` and `ALL` over `{t, b}` join into `{t, t, a, b}`. So rejecting repeats in the normal form rejects that
  author. Rejecting only the author's repeats needs a check outside `Formula.WellFormed`.
- **Rejecting a non-canonical negation or subject order at build time instead of rewriting it**: rejected. The fluent
  API cannot write a non-canonical negation, so rejection adds a failure mode only for raw-op input. Rejecting the
  subject order makes authors write property pairs in ID order, which is an accident of ID assignment.
- **Ordering a context pair when the fluent builder creates the constraint**: rejected. This gives the same bytes and
  decoded form as normalization. Normalization needs the rewrite anyway for formulas that were built without the fluent
  API.
- **Rejecting a context test in an `ANY` body, a one-member `IN` or a lone range pair**: rejected. Each passes the
  gates, so rejection makes authors respell what normalization can respell. A programmatic `isIn` over a one-member
  allowlist would fail to build.
- **Hoisting context tests out of `ALL` bodies**: rejected. `∀i.(P ∧ Q(i))` holds on an empty array whatever `P` is, so
  hoisting changes the verdict on a dynamic array. On a static array, the equivalence depends on the declared length,
  which is a signature fact (gate 1).
- **Normalizing every proven equivalence, redundancy elimination included**: rejected. To drop a dominated bound or a
  tautology erases the defect that validation exists to report. Every added rewrite also grows the table that each
  encoder reproduces.
- **Checking canonical form at storage**: rejected (ADR-0002). An unnormalized well-formed blob has defined evaluation.
- **Normalizing across comparisons, `GT x` to `GTE x+1`**: rejected. The rewrite needs the type's bounds (`GT` of the
  type's maximum has no successor), and a signature-free formula lacks them.
- **Stating the canonical form over bytes in Lean**: rejected. `normalize` would take the signature, and every
  canonical-form theorem would depend on hint compilation and the codec instead of standing on the formula alone.
- **Author-controlled rule or group order, to tune gas**: rejected. This gives one policy a hash per order, and the byte
  order already runs context tests, which read no calldata, first in every group.

## Consequences

- Registry keys and governance comparisons treat policies that differ only in the spellings above as one policy.
- Equivalent formulas outside the table hash apart: `GT x` beside `GTE x+1`, and `x IN {1, 2}` beside the groups `[x ==
  1]` and `[x == 2]`.
- Inspecting a policy shows the canonical form, not the authored spelling.
- A group whose root context test fails exits before it resolves any argument.
- Authors cannot order rules or groups for gas. The builder drops a rule that the author repeated by mistake, without a
  diagnostic.
- Validation sees only normal forms. So neither validator reports a repeated rule, a fusible range pair, a NOT with a
  positive form or a one-member set. Contradiction, vacuity and redundancy analysis remain.
- The table is constant for the major. A new rewrite would change the bytes that an existing formula encodes to, against
  the one encoding per policy across releases that ADR-0003 requires. An extension adds rewrites only for the shapes
  that it introduces.
- A third-party encoder must implement the table and the size-free byte order to reproduce a policy's hash. Same-path
  `IN` rules order by member count before members, because `dataLength` precedes the data. A blob that the encoder
  leaves unnormalized passes storage and evaluates by its own order under a different hash.
- Both builders implement the rewrites, and conformance vectors pin normalized encodings.
- Joining `ALL` loops whose bodies contain loops or OR rules must re-normalize the joined body. That arrives with those
  extensions.

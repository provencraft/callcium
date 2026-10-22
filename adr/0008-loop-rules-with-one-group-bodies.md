# ADR-0008: Loop Rules With One-Group Bodies

## Status

Accepted.

## Context

Policies constrain the elements of variable-length arrays: every element satisfies a condition, or at least one element
does. Indices that name one element express neither.

Several conditions over one array must bind to one element. If each rule quantifies on its own, each condition picks its
own element. For example, `arg(0, ANY, 0).eq(T)` with `arg(0, ANY, 1).gte(1000)` accepts `[(T, 0), (X, 1000)]`. One
element satisfies each condition, but no element satisfies both. Per-rule quantification also walks the array once per
rule, and repeats the array's frame in each rule.

The planned extensions need the same construct: OR inside a loop, nested loops and parallel arrays, which read an
element's position. Nested loops multiply the work per call, and the core has no bound on that work.

A universal quantifier allows two readings of the empty array: vacuously true or false.

## Decision

**A loop is a rule, `scope = 0x02`, and its body is one nonempty group:**

```text
quantifier | pathDepth | arrayPath | hint(main hops, frame) | ruleCount (2) | rules
```

The body's rules exactly fill the rule after `ruleCount`. They form a conjunction that the enforcer evaluates against
one element at a time. The element, with its position, becomes the starting point (`StartingPoint`) that their paths
read from. Every condition in the body sees the same element. The enforcer resolves, frames and walks the array once for
all conditions. The bytes encode the join, and the enforcer does not infer it.

- **Two quantifiers**, `0x01` `ALL` and `0x02` `ANY`, read the empty array as `Rule.holds` does: `ALL` is vacuously true
  and `ANY` is false. A strict universal (every element, and at least one element) is `ALL` beside a length rule in the
  same group. The derivation runs one way only. To derive the vacuous reading from the strict one needs a second group
  that repeats the first group's other rules.
- **Paths contain no loop steps.** A body test's path is relative to the element and can be empty. An empty path reads
  the element itself.
- **The loop rule contains the main hop chain and the frame. Body tests contain the element chains** (ADR-0007).
- **The builder translates the `Path.ALL` and `Path.ANY` steps** into loop rules. It joins the constraints of one group
  that quantify one array with one quantifier into one loop rule.
- **A body contains at least one test that reads the element** (`Group.readsElement`, build time). Under `ANY`, a body
  of context tests alone, `P`, means `P ∧ (array nonempty)`. Under `ALL`, it means `P ∨ (array empty)`. A rewrite of
  either extends or splits the group and needs to know if the array is static. So the author writes the rewrite. Beside
  a test that reads the element, a context test is acceptable in either body.
- **`ANY` without a match fails its group with `QUANTIFIER_NO_MATCH` at the loop rule**, and this includes the empty
  array. If no element satisfies a body of several tests, no single test is to blame. `ALL` reports the failing
  element's first failing test.
- **The core allows no loop inside a body.** The core has no bound on the work that nested loops multiply. The
  enforcer's body evaluator reads no loop, so the evaluation of a loop inside a body is undefined, and storage rejects
  it (ADR-0002). Keeping the root evaluator out of every recursion cycle keeps that cost off every policy. The compiler
  never inlines a recursive function. So even an untaken recursive edge in the rule evaluator puts a call on every group
  and rule of a flat policy.
- **OR inside a body** takes a reserved rule scope that contains `groupCount | groups`. The scope is allowed only in
  bodies.

## Alternatives Considered

- **Per-rule quantification, a quantifier step in each rule's path**: rejected. Conditions over one array bind
  independently, so the decoy above passes. Each rule repeats the frame and walks the array again. It also offers no
  body for OR, nested loops or a shared position.
- **A body that is a disjunction of groups**: rejected. Every loop pays a `groupCount` and a `groupSize` (5 bytes), with
  or without the disjunction. Two `ALL` loops over one array join by concatenation of their conjunctive bodies. To join
  disjunctive bodies, one disjunction distributes over the other and multiplies the groups. An OR rule joins as one more
  conjunct.
- **Evaluating one constraint's operators jointly**: rejected. This relates only conditions on one path. Conditions on
  different fields of one element stay unbound, and the decoy passes.
- **Rejecting several `ANY` conditions over one array at build time**: rejected. This closes the decoy but makes "some
  element has the required shape" inexpressible. It also offers no body for the extensions.
- **Inferring the join at evaluation time from rules that share an array prefix**: rejected. Every enforcer must
  reproduce the inference. A sort key that leads with path depth separates rules over one array that have different
  suffix depths. So the enforcer scans the group. The frames also stay duplicated per rule.
- **A join flag on per-rule quantified rules**: rejected. Each joined rule repeats the frame. Storage compares adjacent
  rules instead of checking one rule's bytes. The enforcer walks the array once per rule or keeps state across rules.
- **A third quantifier for the strict universal**: rejected. The strict universal is one length rule away from `ALL`. A
  third quantifier costs a three-way decode and an empty-array branch in every loop.
- **A separate code for `ANY` over an empty array**: rejected. Both codes would report one failure, which is that no
  element satisfies the body, split by array length.

## Consequences

- The decoy `[(T, 0), (X, 1000)]` fails the joined policy, and `[(X, 5), (T, 1000)]` passes it. In Lean,
  `joint_rejects_decoy`, `joint_accepts_payment` and `perRule_accepts_decoy` pin the difference.
- Two independent `ANY` conditions over one array are expressible on the wire as separate loop rules. But the builder
  joins them and offers no spelling for the per-rule reading.
- A one-step array path with one main hop, a one-step body path without an element hop and a `uint256` operand give
  these sizes. Each further body test takes 49 bytes, against 75 bytes for another one-test loop rule over the same
  array. A one-test loop takes 5 bytes more than the same test with a per-rule quantifier step and frame (derived from
  the layouts, not measured).
- `ruleSize` caps a loop rule, body included, at 65,535 bytes.
- When a body failure is the reported violation, the Solidity `PolicyViolation` contains the loop rule's root index.
- Nested loops arrive as an extension that contains a bound on the work they multiply (ADR-0003).
- Both implementations contain the loop rule in the coder, storage validation, build-time validation and the enforcer.
  They also contain a build-time issue for a body of context tests alone. Loop-rule vectors pin the layout, the
  rejections and the effects.

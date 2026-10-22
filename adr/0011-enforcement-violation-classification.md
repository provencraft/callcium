# ADR-0011: Enforcement Violation Classification

## Status

Accepted.

## Context

Enforcement fails for two kinds of reasons: the blob is not one that the enforcer can evaluate, or the call does not
satisfy the policy. Both implementations report failures. A shared vocabulary needs a principle for which failures it
contains.

## Decision

**A failure is an enforcement violation if a change of call inputs (calldata or context) can change the outcome.
Otherwise it is an integrity error.**

- **Enforcement violations** form the shared `ViolationCode` vocabulary, which the policy spec defines normatively. The
  violations are:
  - A failed comparison.
  - A non-canonical word.
  - A read past the calldata's end.
  - A missing selector.
  - A wrong selector.
  - An index past a dynamic array's end.
  - A missing context property.
  - An array past the iteration limit.
  - An `ANY` loop without a match (ADR-0008).
- **Integrity errors** depend on the blob only, whatever the call. The enforcer detects two at entry: a blob shorter
  than the fixed-length prefix and an unsupported format version (ADR-0002, ADR-0003). Storage keeps structural faults
  out of stored policies. Build-time validation keeps path faults (PV-2) and the other validity faults out of built
  policies only.

The test settles the boundary cases. An element index past a dynamic array's end is a violation, because the length
comes from calldata. An element index past a static array's declared length is an integrity error (PV-2). Walking a
dynamic array longer than `MAX_QUANTIFIED_ARRAY_LENGTH` is a violation. A loop over a static array with a longer
declared length is a build-time defect (PV-7). A blob that bypassed build-time validation reports this defect as
`QUANTIFIER_LIMIT_EXCEEDED`.

## Alternatives Considered

- **Shared codes for integrity errors**: rejected. No call cures them, and storage or build time excludes them from the
  policies that the pipeline produces. A code per structural fault would add vocabulary that no conformant caller meets.
- **An index past a dynamic array's end as an integrity error**: rejected. It would have no normative code. Third-party
  enforcers would report a failure that the caller can cure under names of their own, and conformance can pin only its
  verdict.

## Consequences

- The SDK throws `CallciumError` on an integrity error and returns a code on a violation. Solidity reverts on both and
  tells them apart by error.
- The spec leaves integrity-error names to each implementation, and conformance pins verdicts.
- Enforcement vectors pin every violation code in both implementations, except `MISSING_CONTEXT`. The Solidity enforcer
  cannot meet this code, because it reads every property from the call. The SDK pins this code and its fields in unit
  tests.

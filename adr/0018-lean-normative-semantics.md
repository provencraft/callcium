# ADR-0018: Lean Normative Semantics

## Status

Accepted.

## Context

Prose that specifies a policy format allows readings on which implementations can disagree. Per-rule and joint
quantification (ADR-0008) are both defensible readings of a prose quantifier rule. Nothing in prose forces a build-time
validator and an enforcer to take the same reading. Conformance vectors keep two implementations in agreement on the
inputs that they pin. But neither vectors nor prose say which reading the format means.

The core freezes the meaning of the format, and the format then absorbs extensions over many minors (ADR-0003). A
semantic defect found after release costs a major version.

Assurance for deployed code comes from linking its bytecode to the definition. The candidate tools for that link, EquiVM
and EVMLean, are written in Lean 4.

A proof is only as useful as the statement of what it assumes. An auditor or integrator who relies on a theorem needs to
know where the model ends and where trust starts.

## Decision

**The definitions under `spec/lean/Callcium/`, outside `Sketch/` and `Theorems/`, are the normative definition of the
policy format.** They define formulas, their denotation (`Formula.holds`), the canonical form (`normalize`, ADR-0017),
build-time validity (`Formula.WellFormed`) and the value-level evaluator (`Formula.evaluateValues`). The byte layout,
storage validation, codec and byte-level evaluator join them before the first release, and each extension adds its own
definitions. The prose spec, the conformance vectors and both implementations answer to this one executable definition,
and the theorems are proven against it.

Where prose and model disagree, the model determines the meaning. The descriptor format stays defined by
`spec/descriptor-v2.md`, which the Lean descriptor model follows. Lean 4 keeps the model and the code-to-model link in
one toolchain.

The model proves these families of theorems before the first release:

- **Value level**: the evaluator theorems (`evaluateValues_sound`, `evaluateValues_exact`, `evaluateValues_no_abort`,
  `evaluateValues_complete`) and the canonical-form theorems of ADR-0017.
- **Descriptor**: the descriptor round trip, validity as exactly the encodings of type lists, and metadata that agrees
  with ABI sizes.
- **Byte level**: soundness of the byte-level evaluator on calldata that the decoder model accepts, and completeness and
  absence of aborts on canonical calldata within limits. The theorems also cover hint correctness, safe evaluation of
  every blob that storage validation accepts, and an encoder that emits only valid blobs. They include the wire-level
  canonical-form theorems that ADR-0017 owes, and word canonicity equal to Solidity's.
- **Per extension**: the families above, extended to the extension's cases. ADR-0003's compatibility rule also gives
  bridges from every older minor. The bridges cover storage validation, the encoder, the enforcer and build-time
  narrowing.

**The Solidity implementation, enforcer first, is the code that is linked to the model first.** It enforces onchain. The
SDK reaches the same verdicts, and conformance vectors and differential testing against the executable model keep it
there. The proofs of the SDK follow the Solidity proofs.

**The assumptions:**

- The Lean kernel and its three standard axioms. Proofs use no `native_decide`, and CI audits the axioms and replays the
  kernel check.
- Differential testing, not proof, establishes that the decoder model accepts what Solidity 0.8.30's via-IR decoder
  accepts and reads what it reads.
- The descriptor model matches `spec/descriptor-v2.md`, which the descriptor vectors check.
- Context values are inputs.
- The theorems cover the model. Code reaches them only through the code-to-model link.
- Descriptor validity is a hypothesis. Storage validation checks only the embedded descriptor's well-formedness (PWF-4),
  so offchain tooling that decodes stored blobs checks validity itself.
- Storage validation checks neither hint compilation (ADR-0007) nor canonical form (ADR-0017). So a hand-built blob that
  passes storage validation gets the safe-evaluation theorem only.

## Alternatives Considered

- **Normative prose, with Lean as a check against it**: rejected. Prose runs against no vector and has no proof. When
  prose and model disagree, only review can settle which is right, and the implementations stay bound to the text that
  allowed two readings.
- **An implementation as the definition**: rejected. Every reading that the implementation happens to implement becomes
  the specification. No theorem exists until a bytecode proof of it finishes. The definition itself would change with
  the compiler version and settings. With a model, the theorems stand on their own, and a bytecode proof only links code
  to them.

## Consequences

- Every change to the format, canonical form or semantics lands in `spec/lean/` and its proofs before either
  implementation adopts it. Contributors to the format need the Lean toolchain.
- Conformance vectors run against the executable model beside both implementations. A disagreement resolves against the
  vector or the implementation, unless the model itself changes through its proofs.
- Conformance vectors and differential testing check the blobs that the SDK builder and the Solidity builder produce
  against the model's encoder. The theorems reach these blobs once the builder is linked.
- Integrators who compile with another Solidity version or other settings rely on that compiler's decoder matching the
  model. A compiler upgrade reopens the decoder model's fidelity, which the differential check re-establishes.

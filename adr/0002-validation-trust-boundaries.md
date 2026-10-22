# ADR-0002: Validation Trust Boundaries

## Status

Accepted.

## Context

A policy passes through a builder and an encoder offchain and through a registry onchain. The registry validates and
stores the policy. An enforcer evaluates it on every guarded call. Each stage can check the blob. A check that the
enforcer repeats costs gas on every call.

The design requires integrators to gate storage, so that only trusted entities store or bind a policy. An actor with
that access can unbind a policy or bind a policy that always passes. A subtly malformed blob gains this actor nothing.

The registry and the enforcer can be inlined into separate contracts from different releases. An older enforcer can
receive a blob that a newer registry stored correctly.

## Decision

**Each stage owns a class of guarantees.**

- **Storage time (`Policy.validate()`), onchain.** This stage trusts no earlier stage, because `buildUnsafe()` bypasses
  build time. It checks every invariant without which a field that the enforcer reads is undefined or has a meaning
  other than the format defines. These invariants include framing, sizes, known values and an `IN` set's order. The
  stage checks them whatever they cost at store time. It also checks the fields of the fixed-length prefix (header byte,
  selector slot and descriptor length) that determine one encoding with a local comparison.
- **Build time (`PolicyValidator`), offchain.** This stage checks meaning, not shape, over the formula that the builder
  encodes. It gates the strict `build()`. Agreement between a field that the enforcer reads and a field that only
  offchain tooling reads is a build-time check. A hint and its path are an example. A type code and the embedded
  descriptor are another example.
- **Builder obligations** are rewrites that leave the denotation unchanged, such as the order in which the builder
  encodes rules. The builder performs them, and no stage checks them.
- **Runtime (`PolicyEnforcer`).** This stage trusts storage. At entry, it rejects a blob that is shorter than the
  fixed-length prefix and a format version that it does not support. It checks nothing else about the blob. Every other
  check depends on the live call.

## Alternatives Considered

- **Repeating storage checks in the enforcer**: rejected. This repeats every storage check on every rule of every call,
  against an actor that the storage-gating requirement already excludes.
- **Storage validation of build-time checks, for encoders that bypass the builder**: rejected. Violations of these
  checks leave every field that the enforcer reads defined. The checks need descriptor navigation and cross-rule
  comparison at store time. The actor already controls storage. An encoder that bypasses the builder owns the
  consequences.
- **No runtime version check**: rejected. The enforcer would evaluate a blob of a newer version under rules that the
  blob was not written for.

## Consequences

- If `enforce()` receives a blob that did not pass storage validation, the result is undefined beyond the entry checks.
- After storage, a blob that `buildUnsafe()` built is safe to evaluate but has no build-time guarantee.
- Store gas grows with every storage-time invariant.
- Both implementations contain the three entry points: storage-tier decoding, `PolicyValidator` and the enforcer. The
  conformance vectors split by tier: `policies.json`, `validation.json` and `enforcement.json`.

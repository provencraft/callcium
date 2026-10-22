# ADR-0003: Additions-Only Minor Versions

## Status

Accepted.

## Context

Planned features arrive over several releases:

- OR inside a loop.
- Nested loops.
- Comparisons between two calldata values.
- Aggregates.
- Parallel arrays.
- Calldata inside `bytes`.
- Prefix and hash tests on `bytes`.

A format change that alters the meaning of existing bytes strands every stored policy. Each policy must be re-encoded,
re-stored and rebound under a new hash. If this happens for each feature, every feature release forces every policy to
be re-stored and rebound.

The registry and the enforcer can come from different releases (ADR-0002). A release must therefore handle blobs from
earlier releases and from later releases, whichever contract stored them.

## Decision

**The format freezes a core with reserved space for every planned feature, and grows by additions only.** An extension
assigns a value or a shape that the core's validation rejects, and adds a normative section. An extension never changes
the meaning of an existing value, so the major version does not change.

**The header byte contains the version** and stays one byte, so no field after it moves:

| Bits 7–5 | Bits 4–1 | Bit 0 |
|---|---|---|
| `major` = 3 | `minor` | flag |

Minor 0 is the core. Fifteen minors remain for extensions, and one minor can contain several extensions. Each extension
release raises the supported minor by one.

- **A blob declares the lowest minor that covers the features it uses, and storage validation requires exactly that
  value.** Storage must verify that the declared minor covers the blob's features, because an older enforcer would
  misread an under-declared blob. Requiring equality adds one comparison against a value that storage computes anyway.
  It also gives a policy one encoding, whichever release built it. A blob that uses only the core stays readable by
  every enforcer of the major.
- **Storage validation and the enforcer reject a major other than 3 and a minor above their own.** The enforcer does
  this at entry, before it reads any rule (ADR-0002). The check reads the header byte once per call and costs a few
  opcodes (estimate).
- **A release accepts every blob whose minor is at most its own, and gives the blob the verdict that the release of that
  minor gives.** Build-time validation of a shape that an older minor covers can gain rejections but never acceptances.
  So a blob that a newer release builds at an older minor also passes that minor's build-time validation. An older
  enforcer evaluates the blob under the guarantees that this validation gave. To accept a shape that an older release
  rejects, an extension takes a new minor.
- **No release lowers a design limit, build-only limits included.** Lowering a design limit breaks the acceptance rule
  wherever storage or the enforcer applies the limit. A raise that accepts new shapes takes a minor.

## Alternatives Considered

- **A new major version per extension**: rejected. Every extension would strand every stored policy and change every
  policy hash, including the hash of a policy that uses none of the new features.
- **Reserved values without a version field**: rejected. Some extensions only lift a rejection, such as a rule kind in a
  position that the core forbids. Such an extension uses values that the core already assigns, so no value guard stops
  an older enforcer from misreading it. The guards that do apply sit at every dispatch site and run per rule. These are
  runtime blob checks, which ADR-0002 excludes. The version check runs once per call.
- **Declaring the building release's minor instead of the lowest covering minor**: rejected. A blob from a newer SDK
  would revert in an older enforcer although it uses no feature that the enforcer lacks. The same policy would encode,
  and hash, differently across SDK releases.

## Consequences

- Stored policies keep their bytes, hash and verdict across extension releases. A re-store is necessary only if an
  extension does not fit the reserved space or exhausts the fifteen minors. Such an extension takes a new major.
- The registry and the consumers upgrade in either order. A consumer older than a stored blob's minor reverts on that
  blob. If operators upgrade the registry first, they see reverts on newer blobs until the consumers follow.
- The header has one flag bit and no free bit. A further header flag takes a major version.
- Both implementations contain a supported-minor constant and a classification of features by minor.
- The storage and enforcement conformance vectors of a shipped minor stay in force, unchanged, for every later release.
  Build-time validation vectors can gain rejections.
- Raising `MAX_QUANTIFIED_ARRAY_LENGTH` changes verdicts on unchanged bytes. So no raise fits the rules above as they
  stand. A raise needs its own versioning decision, and that decision must keep the exact lowest covering minor and the
  acceptance rule.

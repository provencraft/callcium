# ADR-0007: Compiled Path Offset Hints

## Status

Accepted.

## Context

A calldata test names its target by a path of field and element indices. At enforcement, resolution of a path against
the embedded descriptor walks argument heads, tuple fields and array metadata on every call. The signature determines
most of that walk, and for a fully static path all of it. The builder has the descriptor and can compute the result
once.

A precomputed result is a second representation of the target beside the path. This raises two questions: where to check
its correctness, and which representation is authoritative at runtime. A scheme that precomputes only some paths keeps
descriptor traversal live for the rest. That scheme has two addressing engines on the enforcement path and a branch
between them.

## Decision

**Every calldata test contains a compiled hint, and only the hint addresses its target at runtime.** A hint is a chain
of hops followed by a constant delta to the target. Each hop crosses one dynamic boundary. A plain hop enters an
indirected node through its offset word. An element hop resolves one element of an array that the chain has reached, and
checks the index against a dynamic array's length.

- **Every path compiles to this form**, so descriptor traversal never runs at enforcement. A chain contains at most one
  hop per path step.
- **To walk an array, the enforcer uses an iteration frame.** Each element becomes a new base for a chain of the same
  shape as any test's hint.
- **A test's hint ends with the target's `typeCode`** (ADR-0005), so the enforcer reads the target's type without the
  descriptor.
- **Hint values are a build-time check, and hint shape is a storage check** (ADR-0002). Strict `build()` computes every
  hint, and PV-4 requires each hint to equal the compilation of its path against the descriptor. Storage checks a hint's
  header, sizes, reserved bits and target type code, byte-locally. Nothing checks hint correctness at runtime.

## Alternatives Considered

- **Per-shape layouts with a traversal fallback**: rejected. The fallback keeps traversal on the enforcement path. Its
  cost falls on the shapes that real ABIs produce, where one `bytes` member makes a whole struct dynamic. Traversal then
  walks the descriptor at every enforcement, where a hint reads only the offset words on its path.
- **Extending the per-shape layouts with one for single-indirection paths**: rejected. This keeps the traversal fallback
  for every other dynamic shape. It adds a layout, a discriminator and a branch to recover one case.
- **Falling back from hint to traversal on mismatch**: rejected. This masks a divergence between path and hint. The
  verdict would depend on which representation an enforcer consulted first.
- **Offsets that replace paths**: rejected. PV-4 checks the hint against the path, and the formula defines its tests
  over the path (`Rule.test`). A hint alone would have nothing to check against.
- **Dropping the embedded descriptor**: rejected. PV-4 recomputation and offchain tooling need the descriptor. The
  policy pays for the descriptor once, but pays for hints per rule.

## Consequences

- Resolution cost grows with the number of dynamic boundaries that a path crosses. It does not grow with the depth of
  the path or the size of the types that the path passes. A field of a dynamic struct costs one load more than a static
  field.
- A test's hint takes 8 bytes plus 8 per hop. A loop's hint takes 9 bytes plus 8 per main hop.
- A `MAX_PATH_DEPTH` up to 63 keeps every chain within the 6-bit `hopCount`.
- A stored blob is verifiable offchain. A decoder that checks the descriptor's validity itself recompiles each hint from
  its path and flags a mismatch.
- Both implementations compile hints, check PV-4 in their validators and follow hops in their enforcers. The conformance
  vectors pin compiled hints.

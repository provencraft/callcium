# ADR-0010: Path Depth Cap

## Status

Accepted.

## Context

`pathDepth` is one byte, so a path can contain up to 255 steps. The enforcer reads no path bytes, because hints address
every target (ADR-0007). Hint compilation and PV-4 recomputation walk paths offchain. A test inside a loop body reads a
path from the element, which the loop's array path reached (ADR-0008). A hint chain contains at most 63 hops, and a
compiled chain contains at most one hop per path step (ADR-0007).

## Decision

**`MAX_PATH_DEPTH` bounds the steps from the arguments to a test's target. It counts every enclosing loop's array path
and the test's own path together** (`Rule.admissible` and `Rule.admissibleTest` count `depth + path.length`). **Storage
validation enforces the bound, and the enforcer performs no depth check** (ADR-0002).

The cap bounds the bytes per path, which storage checks with every other size (ADR-0002). It also bounds the work of
hint compilation and recomputation, and keeps every compiled chain within `hopCount` (ADR-0007). The depth counts across
loops. A body test's target is as deep as the array path plus the test's own path. Hint compilation walks both.

## Alternatives Considered

- **A runtime depth check as defense in depth**: rejected. Depth drives no runtime loop, so the check guards nothing.
- **No cap below the 255 steps that `pathDepth` allows**: rejected. Paths would reach fields that nest between
  `MAX_PATH_DEPTH` and the descriptor's `MAX_NESTING_DEPTH`. The price is larger rules, more compilation work, and
  chains longer than the 63 hops that a hint encodes.
- **A cap on each path separately**: rejected. A body test would reach twice the depth that any root test can reach, and
  each enclosing loop would add another full cap.

## Consequences

- A path cannot reach a field that nests deeper than `MAX_PATH_DEPTH` steps, even where the descriptor allows the field.
- A raise changes storage validation and build-time validation only, and takes a new minor (ADR-0003). A raise past 63
  needs a wider `hopCount`. A reserved hint-header bit, or a reserved scope with its own hint layout, can supply it as
  an addition (ADR-0009).
- The storage validators of both implementations add the array path to each body test's depth. Vectors pin the cap and
  one step past it across a loop.

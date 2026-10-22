# ADR-0020: Vendored Solady Utilities

## Status

Accepted.

## Context

The contracts package uses a few Solady utilities. They are self-contained libraries of internal functions with no
transitive Solady imports, and none of them appears in a public signature. If Callcium depends on Solady as a package,
every integrator must install a second standard library and add a remapping. Every integrator must also take Callcium's
Solady version. Callcium's sources compile under the integrator's remappings, where `solady/` maps to the integrator's
own Solady if it has one.

## Decision

**Callcium vendors the Solady utilities that it uses verbatim under `src/vendor/solady/`, mirroring upstream's layout,
and `src` depends on no package.** `src` imports the vendored files by relative path, never through a remapping.

- Files are copies, verbatim, from one upstream tag, with SPDX headers and `@author Solady` attribution kept.
- The upstream MIT licence lives at `src/vendor/solady/LICENSE`. `src/vendor/solady/README.md` records the tag and the
  refresh procedure.
- Vendored types stay out of every external or public signature, so no integrator's ABI depends on the vendored copy.
  Review enforces this.
- The docs reference pipeline publishes only the contracts that its `INCLUDED_CONTRACTS` list names, and this list
  excludes `src/vendor/`.

## Alternatives Considered

- **A package dependency on Solady**: rejected. Every integrator would install Solady, add a remapping, and take
  Callcium's Solady version.
- **Upstream import paths through a `solady/` remapping**: rejected. The published package has no remappings, so an
  integrator without Solady adds one to reach the vendored files. An integrator's own `solady/` remapping replaces them,
  so Callcium compiles against an untested Solady version or fails to build.
- **A Callcium-specific remapping prefix for the vendored tree**: rejected. The published package has no remappings, so
  every integrator would add one.
- **Vendoring under renamed libraries**: rejected. This keeps a permanent diff against upstream that must be re-applied
  on every refresh.
- **Vendoring all of Solady**: rejected. This enlarges the audit surface and the refresh diff with files that Callcium
  does not use.
- **A flat `src/vendor/` without the `solady/` directory**: rejected. The path does not name the upstream, and a refresh
  replaces files one by one instead of the directory.

## Consequences

- An integrator installs Callcium alone and adds no remapping for the vendored files.
- If an integrator's project maps `solady/` to its own Solady, Callcium still compiles against the vendored files. The
  two copies are separate source units and build side by side.
- The audit surface includes the vendored files. `SSTORE2` is one of them, and it deploys policy blobs as contract code.
- Upstream security patches arrive only through the refresh procedure. The procedure must run when upstream publishes a
  relevant patch.
- `forge doc` generates pages for the vendored files. Only the docs pipeline's list keeps them off the site.

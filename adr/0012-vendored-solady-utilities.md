# ADR-0012: Vendored Solady Utilities

## Status

Accepted.

## Context

The contracts package imports five Solady utilities: `LibBytes`, `LibSort`, `DynamicBufferLib`, `EfficientHashLib`, and `SSTORE2`. Each is a self-contained, internal-function library with no transitive Solady imports. They are pulled in via `soldeer` as the `solady` package pinned to `0.1.26`.

Two costs follow:

- **Integration friction.** Downstream projects that already depend on OpenZeppelin (or anything else) must also install Solady, configure remappings, and carry an extra standard library they did not choose. Callcium positions itself as an easily integrable policy engine; every transitive dependency contradicts that framing.
- **Version coupling at the consumer.** A consumer pinned to a different Solady version than Callcium can hit subtle behavioural drift. Even when types match, the consumer inherits Callcium's choice of Solady tag.

The five files Callcium uses are stable, narrowly scoped, and never appear in any public function signature. None expose a struct that crosses the contract boundary.

## Decision

Vendor the five Solady utilities into the contracts package under `src/vendor/solady/`, mirroring upstream's `utils/` substructure. Drop `solady` from `foundry.toml` dependencies. Re-point the `solady` remapping at the vendored tree so existing import paths in Callcium sources remain unchanged.

### Layout

```
src/vendor/solady/
├── LICENSE
├── README.md
└── utils/
    ├── DynamicBufferLib.sol
    ├── EfficientHashLib.sol
    ├── LibBytes.sol
    ├── LibSort.sol
    └── SSTORE2.sol
```

### Remapping

```
solady/=src/vendor/solady/
```

Source files keep their `import { ... } from "solady/utils/...";` lines verbatim.

### Vendor rules

- Files are copied verbatim from `vectorized/solady@v0.1.26`. SPDX headers and `@author Solady` attribution are preserved.
- The upstream MIT license text lives at `src/vendor/solady/LICENSE`.
- `src/vendor/solady/README.md` records the upstream version tag and refresh procedure.
- Vendored types must not appear in any external or public function signature. Internal use only.
- `forge doc` and the docs reference pipeline exclude `src/vendor/`.

### Refresh procedure

1. Bump the recorded upstream tag in `src/vendor/solady/README.md`.
2. Replace each vendored file with its upstream counterpart from the new tag.
3. Review the diff against the upstream tag, not against the previous vendored version, to surface any change introduced by mistake.
4. Run the full contracts test suite.

## Alternatives Considered

- **Keep the `soldeer` dependency.** Rejected: imposes a second standard library on every Callcium consumer with no offsetting benefit. The five files involved change rarely enough that automatic upstream tracking is not worth the consumer-side friction.
- **Vendor under a renamed namespace (`CallciumLibBytes`, etc.).** Rejected: introduces a permanent diff against upstream that must be re-applied on every refresh, muddies attribution, and solves no real conflict. Solidity scopes library names per import; a consumer that imports both vendored and upstream Solady in the same file resolves the collision with an `import as` alias.
- **Vendor all of Solady.** Rejected: enlarges the audit surface and the refresh diff for files Callcium does not use.
- **Flat `src/vendor/` without the `solady/` directory.** Rejected: loses path-level provenance, makes the refresh procedure manual file-by-file rather than directory replacement, and does not mirror upstream layout.

## Consequences

- The contracts package becomes a zero-dependency Solidity package. Consumers install Callcium without pulling Solady.
- The audit surface includes the five vendored files. `SSTORE2` is the heaviest item because it issues raw `CREATE` and embeds runtime bytecode in deployed code.
- Security fixes that land in upstream Solady do not flow in automatically. The refresh procedure is the only mechanism; it must be exercised when upstream publishes a relevant fix.
- A future Callcium contributor who needs a Solady utility not currently vendored must either inline the function or extend the vendor set under this ADR's rules.
- Consumers that import both Callcium and Solady in the same file resolve any library-name collision with an `import as` alias. No Callcium-side change is required.
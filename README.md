<div align="center">
<img src="logo.svg" width="256" alt="Callcium Logo" />
<h1>Callcium</h1>
<p><strong>Programmable Policy Engine for ABI-Encoded Data</strong></p>
<p>Enforce offchain or onchain.</p>

[Documentation][docs-url]&ensp;&middot;&ensp;[Contributing](./CONTRIBUTING.md)

[docs-url]: https://callcium.dev

</div>

---

> [!NOTE]
> **Pre-release** — The API surface may change. Unaudited.

## Features

- **Dual enforcement** — Enforce policies onchain in Solidity or offchain in TypeScript — same binary policy artifact
- **Declarative policy builder** — Fluent API for composing policies in Solidity or TypeScript
- **Deep argument constraints** — Target calldata arguments, array elements (ANY/ALL quantifiers), and nested struct fields
- **Selectorless policies** — Apply policies to raw ABI blobs: governance proposals, bridge payloads, stored parameters
- **Context checks** — Enforce `msg.sender`, `msg.value`, `block.timestamp`, `block.chainid`
- **Rich operators** — Range checks, set membership, bitwise masks, and negation
- **Flexible logic** — OR/AND groups for complex rule paths
- **Policy introspection** — Inspect and structurally validate deployed policies onchain, no offchain dependencies

## Packages

| Package | Description |
|---------|-------------|
| [`@callcium/contracts`](./packages/contracts) | Solidity implementation |
| [`@callcium/sdk`](./packages/sdk) | TypeScript SDK |
| [`@callcium/docs`](./packages/docs) | Documentation site ([callcium.dev](https://callcium.dev)) |

## Documentation

Full documentation at [callcium.dev][docs-url].

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — PRs are by invitation.

## License

MIT License. See [LICENSE](LICENSE).

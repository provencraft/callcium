<div align="center">
<img src="logo.svg" width="256" alt="Callcium Logo" /> 
<h1>Callcium</h1> 
<p><strong>The On-Chain Policy Engine for ABI-Encoded Data</strong></p>

[Documentation][docs-url]&ensp;&middot;&ensp;[Install][install]&ensp;&middot;&ensp;[Contributing](./CONTRIBUTING.md)

[docs-url]: https://callcium.dev
[install]: #install

</div>

---

> [!NOTE]
> **Pre-release** — The API surface may change. Unaudited.

## Features

- **Declarative policy builder** — Fluent Solidity API for composing policies
- **Deep argument constraints** — Target calldata arguments, array elements (ANY/ALL quantifiers), and nested struct fields
- **Selectorless policies** — Validate raw ABI blobs: governance proposals, bridge payloads, stored parameters
- **Context checks** — Enforce `msg.sender`, `msg.value`, `block.timestamp`, `block.chainid`
- **Rich operators** — Range checks, set membership, bitwise masks, and negation
- **Flexible logic** — OR/AND groups for complex rule paths
- **On-chain validation** — Policy inspection and structural validation, no off-chain dependencies

## Requirements

- Solidity `^0.8.26`
- [Solady](https://github.com/Vectorized/solady) — install separately and ensure it is mapped in your `remappings.txt`

## Install

```
forge install provencraft/callcium
```

## Documentation

Full documentation at [callcium.dev][docs-url].

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — PRs are by invitation.

## License

MIT License. See [LICENSE](LICENSE).

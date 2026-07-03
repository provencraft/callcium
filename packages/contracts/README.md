# @callcium/contracts

Solidity implementation of the Callcium policy engine.

## Requirements

- Solidity `^0.8.28`, compiled with `via_ir = true` — the library does not compile under the legacy codegen pipeline
- EVM Cancun or later — compiled bytecode uses `push0` and `mcopy`; the target chain must support Cancun opcodes

No external Solidity dependencies.

## Install

```bash
forge soldeer install callcium~<version>
```

Or, for git-submodule consumers:

```bash
forge install provencraft/callcium
```

## Documentation

Full documentation at [callcium.dev](https://callcium.dev).

## License

MIT License. See [LICENSE](LICENSE).

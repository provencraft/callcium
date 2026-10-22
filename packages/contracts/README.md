# @callcium/contracts

Solidity implementation of the Callcium policy engine.

## Requirements

- Solidity `^0.8.28`, compiled with `via_ir = true` — the library does not compile under the legacy codegen pipeline
- EVM Cancun or later — compiled bytecode uses `push0` and `mcopy`; the target chain must support Cancun opcodes
- Every inline `assembly` block in a contract that imports the library annotated `memory-safe` — one unannotated block stops the compiler moving stack variables to memory for the whole contract, and the enforcer fails to compile ("too deep in the stack")

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

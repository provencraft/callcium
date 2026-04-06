# @callcium/contracts

Solidity implementation of the Callcium on-chain policy engine.

## Requirements

- Solidity `^0.8.26`
- [Solady](https://github.com/Vectorized/solady) — install separately and ensure it is mapped in your `remappings.txt`

## Install

```
forge install provencraft/callcium
```

## Development

```bash
forge soldeer install   # Install Solidity dependencies
forge build             # Compile contracts
forge test              # Run tests
forge fmt               # Format Solidity source
forge lint              # Lint Solidity source
```

### Benchmarks

```bash
bun run bench:baseline  # Record gas snapshot baseline
bun run bench:compare   # Compare current gas usage against baseline
```

## Documentation

Full documentation at [callcium.dev](https://callcium.dev). See the [root README](../../README.md) for project overview.

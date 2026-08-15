# @callcium/sdk

TypeScript SDK for the [Callcium](https://callcium.dev) policy engine.

Callcium defines type-safe constraints on ABI-encoded data, such as function arguments or a raw payload with no selector, using value ranges, set membership, array quantifiers, and transaction context. This SDK builds policies into canonical policy bytes and validates ABI-encoded data, such as transaction calldata, against a policy offchain, before it is signed.

## Install

```bash
npm install @callcium/sdk
```

```bash
bun add @callcium/sdk
```

## Requirements

Node.js >=22.11.0. Ships as ESM, built to ES2024 — any browser or runtime with ES2024 support works; no browser floor is tested or declared.

## Quick start

```ts
import { PolicyBuilder, PolicyEnforcer, arg } from "@callcium/sdk";

// function approve(address spender, uint256 amount)
const policy = PolicyBuilder.create("approve(address,uint256)")
  .add(arg(0).isIn(trustedSpenders))       // spender
  .add(arg(1).lte(1_000_000n * 10n ** 6n)) // amount
  .build();

// throws on a violation
PolicyEnforcer.enforce(policy, calldata);
```

## More examples

**Nested structs** — target fields deep inside struct arguments by path.

```ts
// struct SwapParams { address tokenIn; address tokenOut; uint256 amount; }
// function swap(SwapParams params)
const policy = PolicyBuilder.create("swap((address,address,uint256))")
  .add(arg(0, 0).notIn(denied)) // params.tokenIn
  .add(arg(0, 1).notIn(denied)) // params.tokenOut
  .add(arg(0, 2).gt(0n))        // params.amount
  .build();
```

**Arrays** — `ANY`/`ALL` quantifiers across array elements, with length bounds.

```ts
// struct Transfer { address to; uint256 value; }
// function batch(Transfer[] transfers)
const policy = PolicyBuilder.create("batch((address,uint256)[])")
  .add(arg(0).lengthBetween(1, 50))                    // transfers.length
  .add(arg(0, Quantifier.ALL, 0).notIn(denied))        // transfers[*].to
  .add(arg(0, Quantifier.ALL, 1).lte(1n * 10n ** 18n)) // transfers[*].value
  .build();
```

**Context** — constrain `msg.sender`, `msg.value`, `block.timestamp`, `block.number`, `block.chainid`, `tx.origin`, `block.basefee`, and `tx.gasprice`, not just calldata.

```ts
// function transfer(address to, uint256 amount)
const policy = PolicyBuilder.create("transfer(address,uint256)")
  .add(msgSender().isIn(operators))   // msg.sender
  .add(msgValue().eq(0n))             // msg.value
  .add(arg(1).lte(100n * 10n ** 18n)) // amount
  .build();
```

**OR groups** — compose alternative rule paths; all constraints hold within a group.

```ts
// function supply(address asset, uint256 amount)
const policy = PolicyBuilder.create("supply(address,uint256)")
  .add(msgSender().eq(OPERATOR)) // path A
  .or()
  .add(arg(0).isIn(allowed))     // path B
  .build();
```

## Documentation

Full API reference, guides, and the policy spec: [callcium.dev/docs/sdk](https://callcium.dev/docs/sdk).

For onchain policy enforcement in Solidity, see [callcium.dev/docs/solidity](https://callcium.dev/docs/solidity).

## License

MIT License. See [LICENSE](LICENSE).

/// Snippet source of truth
// Parallel Solidity/TypeScript pairs for the homepage. Each pair shares line count and 4-space indentation so the
// language switch swaps in place. Leading comments follow the docs style: a struct definition (when the signature has
// one) then the function signature using the struct name; trailing comments are column-aligned. The TypeScript API
// mirrors the Solidity builder; both consume
// @callcium/sdk / the Solidity library as written (illustrative, imports omitted).
///

export type CodePair = { solidity: string; typescript: string };

/** The canonical example carried through the hero and the dual-enforcement proof. */
export const APPROVE: CodePair = {
  solidity: `// function approve(address spender, uint256 amount)
bytes memory policy = PolicyBuilder
    .create("approve(address,uint256)")
    .add(arg(0).isIn(trustedSpenders))     // spender
    .add(arg(1).lte(uint256(1_000_000e6))) // amount
    .build();`,
  typescript: `// function approve(address spender, uint256 amount)
const policy = PolicyBuilder
    .create("approve(address,uint256)")
    .add(arg(0).isIn(trustedSpenders))       // spender
    .add(arg(1).lte(1_000_000n * 10n ** 6n)) // amount
    .build();`,
};

export type Feature = { id: string; label: string; blurb: string } & CodePair;

// Each entry demonstrates one capability of the engine with neutral names. The reader maps it to their own problem
// space, not use-case framing.
export const FEATURES = [
  {
    id: "structs",
    label: "Nested structs",
    blurb: "Fields deep inside struct arguments",
    solidity: `// struct SwapParams { address tokenIn; address tokenOut; uint256 amount; }
// function swap(SwapParams params)
bytes memory policy = PolicyBuilder
    .create("swap((address,address,uint256))")
    .add(arg(0, 0).notIn(denied))  // params.tokenIn
    .add(arg(0, 1).notIn(denied))  // params.tokenOut
    .add(arg(0, 2).gt(uint256(0))) // params.amount
    .build();`,
    typescript: `// struct SwapParams { address tokenIn; address tokenOut; uint256 amount; }
// function swap(SwapParams params)
const policy = PolicyBuilder
    .create("swap((address,address,uint256))")
    .add(arg(0, 0).notIn(denied)) // params.tokenIn
    .add(arg(0, 1).notIn(denied)) // params.tokenOut
    .add(arg(0, 2).gt(0n))        // params.amount
    .build();`,
  },
  {
    id: "arrays",
    label: "Arrays",
    blurb: "Every element, or one matching element",
    solidity: `// struct Transfer { address to; uint256 value; }
// function batch(Transfer[] transfers)
bytes memory policy = PolicyBuilder
    .create("batch((address,uint256)[])")
    .add(arg(0, Path.ALL, 0).notIn(denied))   // transfers[*].to
    .add(arg(0, Path.ANY, 0).eq(TREASURY))    // transfers[i].to
    .add(arg(0, Path.ANY, 1).gte(MIN_AMOUNT)) // transfers[i].value
    .build();`,
    typescript: `// struct Transfer { address to; uint256 value; }
// function batch(Transfer[] transfers)
const policy = PolicyBuilder
    .create("batch((address,uint256)[])")
    .add(arg(0, Quantifier.ALL, 0).notIn(denied))   // transfers[*].to
    .add(arg(0, Quantifier.ANY, 0).eq(TREASURY))    // transfers[i].to
    .add(arg(0, Quantifier.ANY, 1).gte(MIN_AMOUNT)) // transfers[i].value
    .build();`,
  },
  {
    id: "context",
    label: "Context",
    blurb: "Checks on msg.sender and block data",
    solidity: `// function deposit(uint256 assets, address receiver)
bytes memory policy = PolicyBuilder
    .create("deposit(uint256,address)")
    .add(arg(1).eqCtx(PolicyFormat.CTX_MSG_SENDER)) // receiver
    .add(blockTimestamp().lt(DEPOSITS_CLOSE))       // block.timestamp
    .build();`,
    typescript: `// function deposit(uint256 assets, address receiver)
const policy = PolicyBuilder
    .create("deposit(uint256,address)")
    .add(arg(1).eqCtx(ContextProperty.MSG_SENDER)) // receiver
    .add(blockTimestamp().lt(DEPOSITS_CLOSE))      // block.timestamp
    .build();`,
  },
  {
    id: "or",
    label: "OR logic",
    blurb: "Alternative groups of rules",
    solidity: `// function supply(address asset, uint256 amount)
bytes memory policy = PolicyBuilder
    .create("supply(address,uint256)")
    .add(msgSender().eq(OPERATOR)) // group 0
    .or()
    .add(arg(0).isIn(allowed))     // group 1
    .build();`,
    typescript: `// function supply(address asset, uint256 amount)
const policy = PolicyBuilder
    .create("supply(address,uint256)")
    .add(msgSender().eq(OPERATOR)) // group 0
    .or()
    .add(arg(0).isIn(allowed))     // group 1
    .build();`,
  },
  {
    id: "selectorless",
    label: "Selectorless",
    blurb: "Raw ABI payloads with no selector",
    solidity: `// raw ABI payload: (address recipient, uint256 amount)
bytes memory policy = PolicyBuilder
    .createRaw("address,uint256")
    .add(arg(0).isIn(allowed))          // recipient
    .add(arg(1).lte(uint256(1_000e18))) // amount
    .build();`,
    typescript: `// raw ABI payload: (address recipient, uint256 amount)
const policy = PolicyBuilder
    .createRaw("address,uint256")
    .add(arg(0).isIn(allowed))            // recipient
    .add(arg(1).lte(1_000n * 10n ** 18n)) // amount
    .build();`,
  },
] as const satisfies readonly Feature[];

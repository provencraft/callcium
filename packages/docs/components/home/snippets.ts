/// Snippet source of truth
// Parallel Solidity/TypeScript pairs for the homepage. Each pair shares line
// count and 4-space indentation so the language switch swaps in place. Leading
// comments follow the docs style: a struct definition (when the signature has
// one) then the function signature using the struct name; trailing comments are
// column-aligned. The TypeScript API mirrors the Solidity builder; both consume
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

/** Enforcement tail, shown once in the dual fold so the reader sees where calldata enters. */
export const ENFORCE: CodePair = {
  solidity: `// reverts on a violation
PolicyEnforcer.enforce(policy, msg.data);`,
  typescript: `// throws on a violation
PolicyEnforcer.enforce(policy, calldata);`,
};

export type Feature = { id: string; label: string; blurb: string } & CodePair;

// Each entry demonstrates one capability of the engine with neutral names.
// The reader maps it to their own problem space, not use-case framing.
export const FEATURES: Feature[] = [
  {
    id: "arguments",
    label: "Arguments",
    blurb: "Set membership, ranges, and comparisons on scalar arguments.",
    solidity: `// function withdraw(address to, uint256 amount)
bytes memory policy = PolicyBuilder
    .create("withdraw(address,uint256)")
    .add(arg(0).isIn(allowed))          // to
    .add(arg(1).lte(uint256(1_000e18))) // amount
    .build();`,
    typescript: `// function withdraw(address to, uint256 amount)
const policy = PolicyBuilder
    .create("withdraw(address,uint256)")
    .add(arg(0).isIn(allowed))            // to
    .add(arg(1).lte(1_000n * 10n ** 18n)) // amount
    .build();`,
  },
  {
    id: "structs",
    label: "Nested structs",
    blurb: "Target fields deep inside struct arguments by path.",
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
    blurb: "ANY/ALL quantifiers across array elements, with length bounds.",
    solidity: `// struct Transfer { address to; uint256 value; }
// function batch(Transfer[] transfers)
bytes memory policy = PolicyBuilder
    .create("batch((address,uint256)[])")
    .add(arg(0).lengthBetween(1, 50))            // transfers.length
    .add(arg(0, Path.ALL, 0).notIn(denied))      // transfers[*].to
    .add(arg(0, Path.ALL, 1).lte(uint256(1e18))) // transfers[*].value
    .build();`,
    typescript: `// struct Transfer { address to; uint256 value; }
// function batch(Transfer[] transfers)
const policy = PolicyBuilder
    .create("batch((address,uint256)[])")
    .add(arg(0).lengthBetween(1, 50))                    // transfers.length
    .add(arg(0, Quantifier.ALL, 0).notIn(denied))        // transfers[*].to
    .add(arg(0, Quantifier.ALL, 1).lte(1n * 10n ** 18n)) // transfers[*].value
    .build();`,
  },
  {
    id: "context",
    label: "Context",
    blurb: "Constrain msg.sender, msg.value, block, and chain, not just calldata.",
    solidity: `// function transfer(address to, uint256 amount)
bytes memory policy = PolicyBuilder
    .create("transfer(address,uint256)")
    .add(msgSender().isIn(operators)) // msg.sender
    .add(msgValue().eq(uint256(0)))   // msg.value
    .add(arg(1).lte(uint256(100e18))) // amount
    .build();`,
    typescript: `// function transfer(address to, uint256 amount)
const policy = PolicyBuilder
    .create("transfer(address,uint256)")
    .add(msgSender().isIn(operators))   // msg.sender
    .add(msgValue().eq(0n))             // msg.value
    .add(arg(1).lte(100n * 10n ** 18n)) // amount
    .build();`,
  },
  {
    id: "or",
    label: "OR logic",
    blurb: "Compose alternative rule paths. All constraints hold within a group.",
    solidity: `// function supply(address asset, uint256 amount)
bytes memory policy = PolicyBuilder
    .create("supply(address,uint256)")
    .add(msgSender().eq(OPERATOR)) // path A
    .or()
    .add(arg(0).isIn(allowed))     // path B
    .build();`,
    typescript: `// function supply(address asset, uint256 amount)
const policy = PolicyBuilder
    .create("supply(address,uint256)")
    .add(msgSender().eq(OPERATOR)) // path A
    .or()
    .add(arg(0).isIn(allowed))     // path B
    .build();`,
  },
  {
    id: "selectorless",
    label: "Selectorless",
    blurb: "Apply the same policy to a raw ABI blob with no function selector.",
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
];

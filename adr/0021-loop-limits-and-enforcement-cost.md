# ADR-0021: Loop Limits and Enforcement Cost

## Status

Accepted.

## Context

Two design limits bound the enforcer's work: `MAX_QUANTIFIED_ARRAY_LENGTH` per loop (PV-7, and a runtime violation,
ADR-0011) and `MAX_PATH_DEPTH` per path (ADR-0010). A design limit is constant for its minor version and never lowered
(ADR-0003), so its value is chosen once, before release.

The enforcer runs inside the caller's transaction. EIP-7825 caps a transaction at 2^24 gas on Ethereum mainnet. Other
EVM chains set their own caps, and forks reprice opcodes. Both limits bound work per loop or per path, not per policy. A
one-test loop rule takes 45 to 63 bytes, so a 24,575-byte policy contains about 540 of them. Each of them can iterate
the same calldata array.

## Decision

**The design limits keep verdicts independent of the chain. They do not promise that a policy fits a transaction.** The
policy author checks the fit against the enforcer's cost. The cost grows with the root rules and, in a loop, with the
number of elements times the number of body tests. Each test adds one offset read per hop on its path.

**`MAX_QUANTIFIED_ARRAY_LENGTH` is 256 and `MAX_PATH_DEPTH` is 32.** The values keep a loop at both limits under a fifth
of 2^24. The loop has a body of up to eight tests, or one test at the depth limit.

**The policy size cap is a limit of the registry's storage, not of the format.** The registry stores a blob as contract
code through SSTORE2. So its cap is the code size limit (EIP-170, 24,576 bytes) less SSTORE2's prefix byte: 24,575. The
cap is a registry constant. Storage validation, the spec and the conformance vectors contain no size limit.

## Alternatives Considered

- **A total-work bound across loops** (a count of element evaluations, with an abort past it): rejected. A count bounds
  evaluations, not gas. An element's cost varies several-fold with its body and its hops. Transaction caps differ by
  chain, forks reprice, and the guarded call shares the transaction. The bound would add a design limit and a
  per-element cost, and it would guarantee a fit on no chain.
- **Loop limits derived from the size cap**: rejected. To fit the hundreds of loops that the cap allows under 2^24, each
  loop gets a few dozen elements, which excludes ordinary batches. One loop with a heavy body still exceeds the cap.
- **The size cap as a design limit in storage validation**: rejected. An implementation that stores blobs outside
  contract code has no reason to reject a larger blob. Chains also configure larger code size limits (Arbitrum Orbit
  chains up to 96 KB). A vector that pins the cap would apply to the SSTORE2 registry alone.

## Consequences

- A policy author prices a policy against the enforcer's cost before the author stores it. No validation tier checks a
  policy's cost.
- Only `ruleCount` and `ruleSize` bound a loop body. So one loop whose body contains many tests at the depth limit can
  exceed a transaction cap on its own.
- The SDK and any offchain store accept a blob of any size that the format allows. The onchain registry rejects a blob
  above 24,575 bytes. To store a larger blob on a chain whose code size limit allows it, the integrator needs a registry
  with a larger constant.

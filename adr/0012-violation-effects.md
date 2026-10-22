# ADR-0012: Violation Effects

## Status

Accepted.

## Context

A policy holds when some group holds (ADR-0001). A violation (ADR-0011) can end its group, so that the next group tries.
A violation can also end evaluation without a verdict. The Solidity enforcer runs on every guarded call.

Two properties constrain the choice. A verdict must mean what the denotation says: a pass means that the policy holds,
and a fail means that it does not. Also, calldata that canonically encodes a call to the policy's function, within
limits, must always reach a verdict. An index past an array's end in one group must not stop a later group that holds
(`pastEndThenHolds` in Lean's tests).

## Decision

**A violation aborts exactly where the denotation is not computed. Everywhere else, it fails its group.** In a loop
body, it fails the body at that element. An abort rejects the call without a verdict on the policy. Every other outcome
is the denotation's verdict (`evaluateValues_exact` at the value level).

- **Abort, no decoded value to evaluate**: `NON_CANONICAL_VALUE` (ADR-0006), `CALLDATA_OUT_OF_BOUNDS`,
  `MISSING_SELECTOR` and `SELECTOR_MISMATCH` (ADR-0004). The calldata is not the canonical encoding of a call to the
  policy's function.
- **Abort, evaluation stopped**: `QUANTIFIER_LIMIT_EXCEEDED`. The iteration limit stops evaluation before the loop's
  value is computed.
- **Group-local, the denotation is computed and false.** The group-local codes are:
  - `VALUE_MISMATCH`: a comparison fails.
  - `ARRAY_INDEX_OUT_OF_BOUNDS`: a path leaves the value.
  - `MISSING_CONTEXT`: an absent property makes its comparison false.
  - `QUANTIFIER_NO_MATCH`: no element satisfies the body.

Further rules:

- **No abort occurs on canonical calldata within limits**, so there the enforcer always reaches the denotation's
  verdict. The value-level theorems cover the limit half (`evaluateValues_no_abort`, `evaluateValues_complete`). The
  byte-level model owes the calldata half.
- **Canonical calldata is the canonical encoding of a call, followed by any bytes** (`AbiType.decodeStrict`). Bytes past
  the encoding belong to no argument. The enforcer never reads them and never rejects calldata for them.
- **Outcomes are identical across implementations: the verdict, or the abort and its code.** The selector check precedes
  the first group (ADR-0004). `Formula.evaluateValues` determines the order of groups, rules and elements. The
  byte-level model determines the order of checks within a rule.
- **Control flow and reporting belong to each implementation.** Evaluation of further rules or groups for diagnostics
  has no effect on the outcome.

## Alternatives Considered

- **Aborting on an element index past a dynamic array's end**: rejected. This occurs on canonical calldata, where the
  index leaves the value and the denotation is false. An abort would reject calls that a later group allows.
- **Failing the group past the iteration limit**: rejected. The loop's value is not computed there. A fail would report
  the group false where it can hold, and a fail verdict would stop meaning that the policy does not hold.
- **Rejecting calldata longer than its encoding**: rejected. Bytes past the encoding reach no decoded argument, so
  rejecting them adds nothing to soundness. To locate the end of the encoding, the enforcer must walk every dynamic tail
  on each call. The rejection also rejects calls that a forwarder extends with its own data (ERC-2771).
- **Failing the group on every calldata fault**: rejected. A later group would approve a call after an earlier group
  read a non-canonical word, which ADR-0006 rejects. The fail would report a group false where no decoded value exists.

## Consequences

- On calldata that is not canonical or that exceeds a limit, the order of groups decides the outcome. An abort in an
  earlier group rejects a call that a later group allows (`failsThenAbortsThenHolds` in Lean's tests).
- The group-local index fault reuses the length comparison that an element hop into a dynamic array already makes. Its
  added cost is one fault check per resolved chain with hops, and per element inside a loop (estimate).
- Multi-group conformance vectors pin every effect in both implementations, except the effect of `MISSING_CONTEXT`,
  which only the SDK meets. SDK unit tests pin that effect.
- No policy constrains bytes past the encoding, such as the sender that an ERC-2771 forwarder appends. A consumer that
  reads those bytes relies on its own checks.

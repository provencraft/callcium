# ADR-0016: Context Reference Type Pairing

## Status

Accepted.

## Context

The `EQ_CTX` operator compares a resolved value against a context property named by its operand, so both sides of the comparison carry a declared type: the rule's target and the referenced property (`address` or `uint256`, spec §5.4). The comparison is a raw 32-byte word equality — context words are exempt from canonical-encoding checks — so without a build-time restriction any 32-byte static elementary target would be accepted, including pairings that can never or almost never match.

## Decision

`EQ_CTX` targets are restricted to `address` and unsigned integer types (`UINT*`), and the pairing must agree with the referenced property's declared type: address properties require an `address` target; `uint256` properties require an unsigned integer target. Both halves are validity checks (PV-2 via the compatibility matrix, spec §5.7), not runtime checks — the enforcer compares raw words.

- **Any `UINT*` width pairs with a `uint256` property.** Canonical encoding zero-extends narrower unsigned targets, so raw word equality against a full-width property value is exact; there is no ambiguity to forbid, mirroring the width reasoning of ADR-0007.
- **Signed, fixed-byte, and boolean targets are forbidden.** No context property carries those types, so every such pairing is a statically detectable type error.

## Alternatives Considered

- **Generic `EQ` compatibility (all 32-byte static elementary types):** Rejected because a mis-paired rule is policy-fixed dead weight — it silently makes its group unsatisfiable or vacuous under negation, and no calldata can reveal the mistake.
- **Exact type equality (`uint256` property requires a `uint256` target):** Rejected because zero-extension makes narrower unsigned targets compare exactly; forbidding them removes expressiveness (`uint128` amounts against `msg.value`) for no soundness gain.
- **Runtime type checking in the enforcer:** Rejected because the pairing is derivable entirely from the policy blob; charging every evaluation gas for a policy-fixed property inverts the validation tiering of ADR-0006.

## Consequences

- Policy authors get a build-time error (`CONTEXT_TYPE_MISMATCH`) for pairings that could only fail at enforcement, in both the Solidity and SDK validators; `spec/vectors/validation.json` carries pairing-acceptance and mismatch vectors.
- The docs policy-builder operator picker, driven by the shared compatibility check, offers `eqCtx`/`neqCtx` only on targets that can legally pair.
- Comparing a `bytes32` or signed target against a context property is inexpressible; a policy needing it must model the argument as an unsigned integer in its descriptor.
- Extending the context property set with a non-address, non-uint type requires revisiting the pairing rule alongside the property's §5.4 entry.

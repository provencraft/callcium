# ADR-0016: Context Reference Type Pairing

## Status

Accepted.

## Context

A context-reference operator compares a resolved value against a context property named by its operand, so both sides of the comparison carry a declared type: the rule's target and the referenced property (`address` or `uint256`). The comparison is a raw 32-byte word comparison — context words are exempt from canonical-encoding checks — so without a build-time restriction any 32-byte static elementary target would be accepted, including pairings that can never or almost never match.

Equality alone also leaves an argument unbindable to a runtime quantity: an amount cannot be held under `msg.value`, and every ordering bound has to be a literal fixed when the policy is built.

## Decision

The context-reference family is `EQ_CTX` for equality and `GT_CTX`, `LT_CTX`, `GTE_CTX`, `LTE_CTX` for ordering, each carrying one context property ID as its operand. Targets are restricted to `address` and unsigned integer types (`UINT*`), and the pairing must agree with the referenced property's declared type. Both halves are validity checks (PV-2 via the compatibility matrix), not runtime checks — the enforcer compares raw words.

- **Any `UINT*` width pairs with a `uint256` property.** Canonical encoding zero-extends narrower unsigned targets, so the raw word comparison against a full-width property value is exact for equality and for order alike; there is no ambiguity to forbid, mirroring the width reasoning of ADR-0007.
- **`address` pairs under `EQ_CTX` only.** An address is an identity, not a magnitude: ordering one against `msg.sender` or `tx.origin` expresses a bound no policy author means, and forbidding it keeps every context comparison unsigned.
- **Signed, fixed-byte, and boolean targets are forbidden.** No context property carries those types, so every such pairing is a statically detectable type error.

## Alternatives Considered

- **Two ordering opcodes, with the negation flag spelling the other two (`GT_CTX | NOT` for `LTE_CTX`):** Rejected because it makes the inclusive and exclusive halves of the family asymmetric on the builder surface, where the literal comparisons already offer all four; the saved opcodes buy nothing in a space the family occupies contiguously.
- **Generic `EQ` compatibility (all 32-byte static elementary types):** Rejected because a mis-paired rule is policy-fixed dead weight — it silently makes its group unsatisfiable or vacuous under negation, and no calldata can reveal the mistake.
- **Exact type equality (`uint256` property requires a `uint256` target):** Rejected because zero-extension makes narrower unsigned targets compare exactly; forbidding them removes expressiveness (`uint128` amounts against `msg.value`) for no soundness gain.
- **Runtime type checking in the enforcer:** Rejected because the pairing is derivable entirely from the policy blob; charging every evaluation gas for a policy-fixed property inverts the validation tiering of ADR-0006.

## Consequences

- Policy authors get a build-time error (`CONTEXT_TYPE_MISMATCH`) for pairings that could only fail at enforcement, in both the Solidity and SDK validators; `spec/vectors/validation.json` carries pairing-acceptance and mismatch vectors.
- An argument can be bounded by a quantity known only at call time — `msg.value`, `block.timestamp`, `block.number` — instead of by a literal chosen when the policy is built.
- The operand names a property rather than a value, so bound analysis has nothing to fold into a domain: two context-bounded rules that contradict each other pass validation and fail at enforcement.
- The docs policy-builder operator picker, driven by the shared compatibility check, offers each context operator only on targets that can legally pair.
- Comparing a `bytes32` or signed target against a context property is inexpressible; a policy needing it must model the argument as an unsigned integer in its descriptor.
- Extending the context property set with a non-address, non-uint type requires revisiting the pairing rule alongside the property's entry in the context property table.

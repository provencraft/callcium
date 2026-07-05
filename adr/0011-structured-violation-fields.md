# ADR-0011: Structured Violation Fields

## Status

Accepted.

## Context

ADR-0009 fixed the violation vocabulary but left the carrier shape implicit. The original `Violation` was `{ code, message: string, path?, resolvedValue? }`, with `message` built inside the enforcer as a presentation string. Three problems followed:

- **Type-blind rendering.** Every scalar passed through `compactHex`. Addresses, integers, bools, and `bytesN` all surfaced as raw hex bigints.
- **Silent data loss.** Hex strings truncated at 66 characters with an ellipsis, destroying long `bytes` operand payloads.
- **Wrong layer for presentation.** The SDK has the semantic context (`opCode`, `typeCode`, `operandData`, lookup tables). Display context (locale, terminal width, address shortening, decimal grouping, theming) belongs to the consumer. Today's docs UI, a future CLI, a Foundry trace decoder, and an LSP each need different rendering.

A vocabulary decision cannot serve multiple consumers without a shape that carries the semantic data each consumer renders independently.

## Decision

Violations carry structured semantic data only. The SDK preserves ABI/EVM truth and Solidity type metadata; consumers render Solidity-source-level meaning.

### Violation shape

```ts
type Violation = {
  group?: number;
  rule?: number;
  code: ViolationCode;
  scope?: number;          // Scope.CALLDATA or Scope.CONTEXT; required when path is present.
  path?: Hex;
  opCode?: number;         // Raw, NOT bit intact.
  operandData?: Hex;       // Full untruncated rule operand bytes.
  typeCode?: number;       // Type of the target value; length ops decode resolvedValue as a count.
  resolvedValue?: Hex;     // 32-byte ABI-style word for scalars; hex-encoded count for length ops and QUANTIFIER_LIMIT_EXCEEDED.
  expectedValue?: Hex;     // Expected value for applicable non-rule precheck failures (currently SELECTOR_MISMATCH).
  elementIndex?: number;   // Universal quantifier per-element failures.
};
```

### Field population

| Group | Codes | Required fields |
|---|---|---|
| Path-bearing | `VALUE_MISMATCH`, navigation/read failures, quantifier failures, `MISSING_CONTEXT` | `group`, `rule`, `scope`, `path` |
| Single-value mismatch (additional) | `VALUE_MISMATCH` for leaf, context, and universal per-element | `opCode`, `operandData`, `typeCode`, `resolvedValue` |
| Existential aggregate mismatch (additional) | `VALUE_MISMATCH` for `Quantifier.ANY` "violated by all elements" | `opCode`, `operandData`, `typeCode` when captured during iteration; no `resolvedValue` |
| Pre-rule selector codes | `MISSING_SELECTOR`, `SELECTOR_MISMATCH` | none of the path fields |

For `SELECTOR_MISMATCH`, `expectedValue` is the policy selector and `resolvedValue` is the calldata selector. `scope` is required whenever `path` is present. `elementIndex` is absent on existential (`Quantifier.ANY`) failures, where no single element is to blame.

### `PolicyViolationError.message`

A single-line, non-lossy diagnostic built from the first violation's structured fields. Not a presentation contract. Consumers rendering for humans iterate `violations` and use their own formatter.

### Encoding invariants

- Scalar `resolvedValue` is the full 32-byte ABI word for calldata leaves and context values. Going through `toBigInt` and back loses left-aligned `bytesN` semantics.
- `opCode` keeps the `Op.NOT` bit raw.
- Length operations and `QUANTIFIER_LIMIT_EXCEEDED` encode `resolvedValue` as a hex-encoded count.
- Context property `typeCode` reflects the declared type. The enforcer must not pass `UINT_MAX` for address-typed properties.

## Alternatives Considered

- **Improve the SDK-built message.** Thread `typeCode` into the existing formatter; render decimal/checksummed/literal per type. Rejected: keeps the boundary in the wrong layer. Future consumers parse the string back or duplicate the lookup tables.

- **Structured fields plus deprecated string fallback.** Keep `Violation.message` as a transitional fallback. Rejected: the fallback carries implicit formatting promises that constrain future SDK changes. `PolicyViolationError.message` covers log readability without imposing a presentation contract on every `Violation`.

- **Code-specific expected fields.** Add `expectedSelector`, `expectedLength`, etc. per use site. Rejected: a single `expectedValue: Hex` covers all current and foreseeable cases. The `code` discriminates intent.

## Consequences

- New `ViolationCode`s specify their field-population row in TSDoc and the docs renderer's switch.
- Consumers that previously read `Violation.message` migrate to structured fields. The new fields cover everything the prior message conveyed with strictly more fidelity.
- Tests assert structured fields, not message strings.
- Consumers own presentation. The docs site renders Solidity-style operators, checksummed addresses, decimal integers, bool literals, and full-fidelity hex bytes; other consumers can choose differently.
- The Solidity enforcer is unaffected. Per ADR-0010 it reverts on violation rather than carrying a structured payload onchain. A future onchain transcript decoder reconstructs this shape from raw event data; the field set is its target schema.
- Reference documentation auto-regenerates from TSDoc. The field documentation is the public contract; per-field boundary cases (diagnostic-only fields on navigation failures, optional `resolvedValue`) live there, not here.

# ADR-0008: Path Quantifier Sentinels

## Status

Accepted.

## Context

Policies must express constraints over array elements: "all recipients must be in the allowlist" (universal) or "at least one recipient must be a priority address" (existential). Two approaches were considered:

1. **Separate opcodes**: Add quantifier-specific operators (e.g., `OP_ALL_IN`, `OP_ANY_EQ`).
2. **Path sentinels**: Reserve special path indices that signal quantification, reusing existing operators.

## Decision

Array quantification uses sentinel path indices rather than separate opcodes:

```solidity
uint16 constant ALL_OR_EMPTY = 0xFFFF;  // Universal quantifier (∀), vacuous on empty
uint16 constant ALL          = 0xFFFE;  // Universal quantifier (∀), strict (non-empty required)
uint16 constant ANY          = 0xFFFD;  // Existential quantifier (∃)
```

Rationale:
- Quantification is a property of the path, not the operator.
- The same operator (e.g., `OP_IN`) can be used with any quantifier.
- Path-based encoding keeps the rule structure uniform.
- No additional fields or format changes required.

## Alternatives Considered

- **Separate opcodes per quantifier:** Add quantifier-specific operators (e.g., `OP_ALL_IN`, `OP_ANY_EQ`). Rejected because it treats quantification as a property of the operator rather than the path, causing a combinatorial explosion of opcodes (each operator × each quantifier). It also breaks the uniform `(scope, path, opCode, data)` rule layout.

## Consequences

- Uniform rule structure: all rules share the same `(scope, path, opCode, data)` layout regardless of quantification.
- Operators are orthogonal to quantifiers — any operator can be combined with any quantifier.
- Reserved index range: concrete array indices are limited to `0..0xFFFC` (65,533 elements), with `0xFFFD–0xFFFF` reserved for sentinels.
- Evaluators must pre-process quantified paths by expanding sentinels into concrete element indices before calldata traversal.

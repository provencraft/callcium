# ADR-0019: Structured Violation Fields

## Status

Accepted.

## Context

The SDK reports each violation (ADR-0011) to consumers that render it. The docs site is one consumer. A CLI, a trace
decoder or an editor integration is another, and the shape must also serve these. The enforcer has the semantic context:
operator, type, operand and location. Each consumer has its display context: locale, width, address formatting and
theming. A string that the enforcer builds determines the display choices for every consumer.

A comparison whose operand resolves at enforcement, such as one with a context source (ADR-0013), compares against a
value that appears in no operand byte.

## Decision

**An SDK violation contains structured semantic data only, and consumers render it.** Fields contain raw words and
codes, with Solidity type metadata. The Solidity revert contains the root location only (ADR-0008).

- `code`: the `ViolationCode`.
- `group`, `rule`: the root location, which is the group and the rule within it. For a failure inside a loop body,
  `rule` is the loop rule.
- `scope`, `path`: the failing test's scope and path. Inside a body, the path is relative to the element, which the loop
  rule's array path reaches.
- `operator`: the failing test's operator. It contains the operator byte with the NOT bit intact, the comparison, the
  polarity and the operand type. It also contains either the constants of the operator, each loaded to a 32-byte word
  (ADR-0013), or the context property that the operator names.
- `typeCode`: the type of the value that the violation concerns.
- `resolvedValue`: the word or count that the failing check read.
- `resolvedOperand`: the value that an operand took when it resolved at enforcement, for any source. The operator's
  source discriminates it.
- `expectedValue`: the value that a non-rule check expected, beside the actual value in `resolvedValue`.

A violation that a body test raises at an element also contains the test's position in the body. It also contains
`elementIndex`, the position of the element. `QUANTIFIER_NO_MATCH`, raised at the loop rule, contains neither, because
no element and no test is to blame (ADR-0008).

- **TSDoc defines, per code, which fields contain a value and how each field is encoded.** This documentation is the
  public contract and includes boundary cases per field. The docs renderer follows it.
- **`PolicyViolationError.message`** is one line that contains the first violation's code and root location, for logs.
  It is not a presentation contract.

## Alternatives Considered

- **A presentation string that the SDK builds**: rejected. It keeps display choices in the enforcer's layer. Every other
  consumer parses the string back or duplicates the lookup tables.
- **Structured fields plus a string on every violation**: rejected. Consumers would read the string, and its formatting
  would become a promise that constrains every later SDK change. The one log line on the error makes no such promise.
- **A field per expected-value kind, such as `expectedSelector`**: rejected. A later code that expects a value would add
  a field and change the shape. A single `expectedValue` field, which the consumer reads according to `code`, absorbs
  the new code.
- **A resolved field per operand source**: rejected. `operator` already says how to read the operand and its resolved
  value. A field per source adds shape without information.

## Consequences

- A new `ViolationCode` states its field population in TSDoc and in the docs renderer.
- Tests assert structured fields, not message strings.
- Consumers own presentation. The docs site renders Solidity-style operators, checksummed addresses, decimal integers
  and full-width hex bytes. Other consumers can choose differently.
- A consumer that needs the fields for an onchain revert re-runs the SDK enforcer offchain.

# Callcium Policy Spec

## 1. Document Control
- Version: 1.2
- Status: Normative

---

## 2. Purpose, Scope, and Exclusions

This document specifies the canonical binary format for Policies in Callcium, a policy engine for ABI-encoded data. A Policy defines constraints that ABI-encoded data must satisfy to be considered compliant.

### Scope
- Binary format and encoding rules.
- Validation semantics.
- Canonicalization requirements.

### Exclusions

This document does not define:
- Builder API design or usage patterns.
- Implementation strategies, gas optimization techniques, or evaluation order heuristics.
- Application-specific policy templates.
- Descriptor format (see Callcium Descriptor Spec).

---

## 3. Terminology and Conformance

- The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT, RECOMMENDED, MAY in this document are to be interpreted as described in RFC 2119.
- "Validator" refers to any component that checks a policy blob against the invariants of Section 8.
- "Builder" refers to any component that constructs canonical policy blobs from higher-level definitions.
- "Enforcer" refers to any component that evaluates a policy against calldata and execution context.

An implementation is conformant if and only if it meets all MUST/REQUIRED obligations in Sections 4–9.

---

## 4. Wire Format

### 4.1 Policy Structure

```
+--------+----------+------------+----------+------------+----------+
| header | selector | descLength | desc     | groupCount | groups   |
| 1 byte | 4 bytes  | 2 bytes    | variable | 1 byte     | variable |
+--------+----------+------------+----------+------------+----------+
```

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 0 | header | 1 | Composite header byte (see below) |
| 1 | selector | 4 | Function selector (must be `0x00000000` if selectorless) |
| 5 | descLength | 2 | Descriptor length in bytes (big-endian) |
| 7 | desc | descLength | Embedded function descriptor |
| 7+descLength | groupCount | 1 | Number of rule groups [1, 255] |
| 8+descLength | groups | var | Concatenated group records |

**Header byte layout:**
```
+----------+------------------+----------+
| reserved | FLAG_NO_SELECTOR | version  |
| bits 7-5 | bit 4            | bits 3-0 |
+----------+------------------+----------+
```

- **Bits 3-0 (version)**: Format version. Current value: `0x1`.
- **Bit 4 (FLAG_NO_SELECTOR)**: If set (`0x10`), the policy targets raw ABI-encoded calldata without a 4-byte function selector. The selector slot is ignored by the enforcer, which uses `baseOffset = 0` instead of `4`.
- **Bits 7-5 (reserved)**: MUST be zero. Validators MUST reject non-zero reserved bits.

**Invariants:**
- `(header & 0x0F) == 0x01`. The policy format version is independent of the descriptor format version.
- `(header & 0xE0) == 0x00`. Reserved bits must be zero.
- If `(header & 0x10) != 0`: `selector == 0x00000000` (canonical encoding).
- `descLength >= 2` (the minimum descriptor header: version + paramCount).
- `desc` is a well-formed descriptor blob (Callcium Descriptor Spec, Section 7.1).
- `groupCount >= 1` (empty policy is invalid).
- Groups are stored contiguously, group-major order.

### 4.2 Group Structure

```
+-----------+-----------+----------+
| ruleCount | groupSize | rules    |
| 2 bytes   | 4 bytes   | variable |
+-----------+-----------+----------+
```

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 0 | ruleCount | 2 | Number of rules in group (big-endian) |
| 2 | groupSize | 4 | Total bytes of rules payload (big-endian) |
| 6 | rules | var | Concatenated rule records |

**Invariants:**
- Group identity = position in blob (0-indexed).
- `ruleCount >= 1` (empty group is invalid).
- `groupSize == sum of all rule bytes in this group`.
- Rules within a group are sorted by `(scope, pathDepth, pathBytes, operatorBytes)` ascending.

**Semantics:**
- Rules within a group have AND semantics (all must pass).
- Groups have OR semantics (first passing group succeeds).
- This structure is Disjunctive Normal Form (DNF): an OR of ANDs.

### 4.3 Rule Structure

```
+----------+--------+-----------+---------------+--------+------------+------------------+
| ruleSize | scope  | pathDepth | path          | opCode | dataLength | data             |
| 2 bytes  | 1 byte | 1 byte    | 2*depth bytes | 1 byte | 2 bytes    | dataLength bytes |
+----------+--------+-----------+---------------+--------+------------+------------------+
```

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 0 | ruleSize | 2 | Total size of this rule in bytes, including this field (big-endian) |
| 2 | scope | 1 | Rule scope (0=context, 1=calldata) |
| 3 | pathDepth | 1 | Number of path steps |
| 4 | path | 2*depth | Path steps (big-endian uint16 each) |
| 4+2*depth | opCode | 1 | Comparison operator |
| 5+2*depth | dataLength | 2 | Length of data section (big-endian) |
| 7+2*depth | data | dataLength | Operator-specific data |

**Invariants:**
- `ruleSize == 4 + pathDepth*2 + 3 + dataLength`.
- When `scope == 0`: `pathDepth == 1` and `path[0]` is a reserved context property ID.
- When `scope == 1`: `pathDepth >= 1` and path navigates calldata structure.

**Type Resolution:**
- For calldata rules: type is resolved by navigating the descriptor using the rule's path (see Callcium Descriptor Spec, Section 6).
- For context rules: type is implicit from the context property ID.

### 4.4 Data Encoding

All multi-byte integers are big-endian. All values in the data section are encoded as fixed 32-byte fields.

**Operator Data Formats:**

| Operator | dataLength | Format | Description |
|----------|---------|--------|-------------|
| EQ | 32 | `[value:32]` | Single comparison value |
| GT | 32 | `[bound:32]` | Lower bound (exclusive) |
| LT | 32 | `[bound:32]` | Upper bound (exclusive) |
| GTE | 32 | `[bound:32]` | Lower bound (inclusive) |
| LTE | 32 | `[bound:32]` | Upper bound (inclusive) |
| BETWEEN | 64 | `[min:32][max:32]` | Range bounds (inclusive) |
| IN | `32*n` | `[v1:32][v2:32]...` | Set members (`n = dataLength/32`), sorted and deduped |
| BITMASK_ALL | 32 | `[mask:32]` | Required bits (all must be set) |
| BITMASK_ANY | 32 | `[mask:32]` | Any-of bits (at least one set) |
| BITMASK_NONE | 32 | `[mask:32]` | Forbidden bits (none may be set) |
| LENGTH_EQ | 32 | `[length:32]` | Exact length |
| LENGTH_GT | 32 | `[bound:32]` | Minimum length (exclusive) |
| LENGTH_LT | 32 | `[bound:32]` | Maximum length (exclusive) |
| LENGTH_GTE | 32 | `[bound:32]` | Minimum length (inclusive) |
| LENGTH_LTE | 32 | `[bound:32]` | Maximum length (inclusive) |
| LENGTH_BETWEEN | 64 | `[min:32][max:32]` | Length range (inclusive) |

Length operators apply to dynamic arrays (element count) and `bytes`/`string` (byte length). Static arrays are forbidden.

### 4.5 Type-Specific Encoding

The encodings in this section define the canonical 32-byte form for operator operands and for resolved calldata values after canonicalization (§7.4).

**Address (typeCode = 0x40):**
```
[0x000000000000000000000000][address:20]
```
Left-padded with 12 zero bytes.

**Unsigned Integers (typeCode = 0x00-0x1F):**
```
[padding][value]
```
Left-padded to 32 bytes. Value occupies rightmost N bytes where N = (typeCode + 1).

**Signed Integers (typeCode = 0x20-0x3F):**
```
[sign-extension][value]
```
Sign-extended to 32 bytes (two's complement). Comparison operators (`GT`, `LT`, `GTE`, `LTE`, `BETWEEN`) MUST use signed arithmetic (EVM `slt`/`sgt`). The `EQ` and `IN` operators use bitwise equality and are sign-agnostic.

**Boolean (typeCode = 0x41):**
```
[0x00...00][0x00 or 0x01]
```
0x00 = false, 0x01 = true. Only `EQ` and its negation are valid for booleans.

**Function (typeCode = 0x42):**
```
[address:20][selector:4][0x0000000000000000]
```
External function pointer: a 20-byte address followed by a 4-byte selector (24 bytes total). Encoded identical to `bytes24` — left-aligned in the high 24 bytes and padded with 8 trailing zero bytes.

**Fixed Bytes (typeCode = 0x50-0x6F):**
```
[value:N][0x00...00]
```
Right-padded with zeros. N = typeCode - 0x4F.

---

## 5. Constants

### 5.1 Version and Header
```
VERSION          = 0x01   // format version (lower nibble of header)
VERSION_MASK     = 0x0F   // mask to extract version from header
FLAG_NO_SELECTOR = 0x10   // bit 4: selectorless policy
RESERVED_MASK    = 0xE0   // bits 7-5: must be zero
```

### 5.2 Header Sizes
```
POLICY_HEADER_PREFIX = 7  // header(1) + selector(4) + descLength(2)
GROUP_HEADER_SIZE = 6     // ruleCount(2) + groupSize(4)
RULE_MIN_SIZE = 9         // ruleSize(2) + scope(1) + pathDepth(1) + path(2) + opCode(1) + dataLength(2)
```

### 5.3 Scope Values
```
SCOPE_CONTEXT = 0x00
SCOPE_CALLDATA = 0x01
```

### 5.4 Context Property IDs

When `scope == SCOPE_CONTEXT`, the path contains exactly one step identifying the context property:

```
CTX_MSG_SENDER = 0x0000       // msg.sender (address)
CTX_MSG_VALUE = 0x0001        // msg.value (uint256)
CTX_BLOCK_TIMESTAMP = 0x0002  // block.timestamp (uint256)
CTX_BLOCK_NUMBER = 0x0003     // block.number (uint256)
CTX_CHAIN_ID = 0x0004         // chain.id (uint256)
CTX_TX_ORIGIN = 0x0005        // tx.origin (address)
CTX_BASE_FEE = 0x0006         // block.basefee (uint256)
CTX_GAS_PRICE = 0x0007        // tx.gasprice (uint256)
```

Builders MUST validate operator-type compatibility for context rules using the declared types above (`address` or `uint256`). Enforcers MUST treat all context values as raw 32-byte words at evaluation time; runtime type checking is not required.

### 5.5 Path Quantifiers

```
ALL_OR_EMPTY = 0xFFFF     // Universal quantifier (∀): passes for ALL elements; empty arrays yield true
ALL          = 0xFFFE     // Universal quantifier (∀): passes for ALL elements; empty arrays yield false
ANY          = 0xFFFD     // Existential quantifier (∃): passes for AT LEAST ONE element; empty arrays yield false
```

Reserved index range: indices `i >= 0xFFFD` are reserved for quantifiers. Valid concrete indices are `0..0xFFFC`.

### 5.6 Operator Codes

**Encoding:** `[NOT:1 bit][OPERATOR:7 bits]`
- Bit 7 (0x80): NOT flag — inverts the operator result.
- Bits 0-6: Operator code.

Operator code `0x00` is unassigned and MUST be rejected.

**Base Operators (0x01–0x7F):**
```
OP_EQ       = 0x01        // value == operand
OP_GT       = 0x02        // value > operand
OP_LT       = 0x03        // value < operand
OP_GTE      = 0x04        // value >= operand
OP_LTE      = 0x05        // value <= operand
OP_BETWEEN  = 0x06        // min <= value <= max (inclusive)
OP_IN       = 0x07        // value in {v1, v2, ...}
OP_BITMASK_ALL  = 0x10    // (value & mask) == mask
OP_BITMASK_ANY  = 0x11    // (value & mask) != 0
OP_BITMASK_NONE = 0x12    // (value & mask) == 0
OP_LENGTH_EQ      = 0x20  // length(value) == operand
OP_LENGTH_GT      = 0x21  // length(value) > operand
OP_LENGTH_LT      = 0x22  // length(value) < operand
OP_LENGTH_GTE     = 0x23  // length(value) >= operand
OP_LENGTH_LTE     = 0x24  // length(value) <= operand
OP_LENGTH_BETWEEN = 0x25  // min <= length(value) <= max
```

**Negation:**
```
NOT_FLAG    = 0x80
```

Negated forms follow the same type restrictions as their base operators.

### 5.7 Operator-Type Compatibility Matrix

| Operator | Valid Types |
|----------|-------------|
| `EQ` | All 32-byte static elementary types. |
| `GT`, `LT`, `GTE`, `LTE`, `BETWEEN` | Numeric types (`UINT*`, `INT*`) only. |
| `IN` | All 32-byte static elementary types except `BOOL`. |
| `BITMASK_*` | Unsigned integer types (`UINT*`) and `BYTES32` only. |
| `LENGTH_*` | `BYTES`, `STRING`, `DYNAMIC_ARRAY` only. Static arrays forbidden. |

Value operators (`EQ`, `GT`, `LT`, `GTE`, `LTE`, `BETWEEN`, `IN`, `BITMASK_*`) require 32-byte static elementary types; dynamic and composite types are incompatible.

---

## 6. Path Encoding and Rule Ordering

### 6.1 Path Format

Path is encoded as a sequence of big-endian uint16 values:
```
[step0:2][step1:2]...[stepN:2]
```

### 6.2 Path Interpretation

- `path[0]`: Top-level parameter index (0-based).
- `path[1..n]`: Navigation into nested structures.
  - For tuples: field index.
  - For arrays: element index, `ALL_OR_EMPTY` (0xFFFF), `ALL` (0xFFFE), or `ANY` (0xFFFD).

### 6.3 Quantifier Constraints

- `ALL_OR_EMPTY`, `ALL`, and `ANY` steps are only valid immediately after array nodes.
- A path MUST contain at most one quantifier step. Nested quantifiers are forbidden in format version 1.
- Valid concrete indices are `0..0xFFFC`.

### 6.4 Examples

```
// Function: foo(address recipient, uint256 amount)
// Rule: amount >= 100
path = [0x0001]  // parameter index 1

// Function: bar((address token, uint256 amount) payment)
// Rule: payment.amount <= 1000
path = [0x0000, 0x0001]  // parameter 0, field 1

// Function: baz(address[] recipients)
// Rule: all recipients in allowlist (universal, vacuous)
path = [0x0000, 0xFFFF]  // parameter 0, ALL_OR_EMPTY elements

// Rule: all recipients in allowlist (strict universal)
path = [0x0000, 0xFFFE]  // parameter 0, ALL elements

// Rule: at least one recipient in allowlist (existential)
path = [0x0000, 0xFFFD]  // parameter 0, ANY element
```

### 6.5 Canonical Rule Sort Key

Rules within each group MUST be sorted by `(scope, pathDepth, pathBytes, operatorBytes)` in ascending order.

**Sort priority:**
1. `scope`: 0 (context) before 1 (calldata).
2. `pathDepth`: shorter paths before longer.
3. `pathBytes`: lexicographic comparison of path bytes.
4. `operatorBytes`: lexicographic comparison of `opCode || data` (tie-breaker for multiple rules on the same path).

### 6.6 Comparison Algorithm

```
function compareRules(a, b):
    // Primary: scope
    if a.scope != b.scope:
        return a.scope - b.scope

    // Secondary: pathDepth
    if a.pathDepth != b.pathDepth:
        return a.pathDepth - b.pathDepth

    // Tertiary: pathBytes (lexicographic)
    for i in 0 ..< a.pathDepth:      // exclusive upper bound
        if a.path[i] < b.path[i]: return -1
        if a.path[i] > b.path[i]: return +1

    // Quaternary: operatorBytes (lexicographic over opCode || data)
    return lexicographicCompare(a.operatorBytes, b.operatorBytes)
```

Lexicographic comparison of byte arrays: compare byte-by-byte from index 0. At the first differing byte, the array with the smaller byte value sorts first. If all bytes of the shorter array match the corresponding prefix of the longer array, the shorter array sorts first.

### 6.7 Sort Invariants

- `scope == 0` ⇒ `pathDepth == 1` with reserved context property ID.
- `scope == 1` ⇒ `pathDepth >= 1` with BE16 path steps.

---

## 7. Evaluation

### 7.1 Evaluation Algorithm

1. Extract version from header byte (`header & VERSION_MASK`); verify `== 0x01`.
2. If `FLAG_NO_SELECTOR` is not set: verify selector in calldata matches policy selector; set `baseOffset = 4`.
3. If `FLAG_NO_SELECTOR` is set: skip selector validation; set `baseOffset = 0`.
4. Extract descriptor from policy header.
5. Evaluate groups in order; first passing group succeeds (OR semantics).
6. Within each group, all rules must pass (AND semantics).

### 7.2 Rule Evaluation

- Context rules (`scope == 0`) resolve the value from the execution environment using the context property ID in `path[0]`.
- Calldata rules (`scope == 1`) resolve the value by traversing calldata using the descriptor and path (see Callcium Descriptor Spec, Section 6) and loading the scalar at the resolved location.
- The resolved value is canonicalized to its declared type per §7.4, then the canonical value and type code are checked against the operator and data.
- For `LENGTH_*` operators, the resolved value is the declared length read at the target's payload base: the element count for dynamic arrays, the byte length for `bytes` and `string`. Enforcers MUST verify that the declared payload extent — `length × stride` bytes, where the stride is 1 for `bytes`/`string`, 32 for arrays of dynamic elements (one offset word per element), and the element's ABI head size (`elemStaticWords × 32`; Callcium Descriptor Spec, Section 4.4) for arrays of static elements — lies within calldata bounds before applying the operator; an overrun is a `CALLDATA_OUT_OF_BOUNDS` violation.

### 7.3 Quantifier Handling

When a path contains `ALL_OR_EMPTY`, `ALL`, or `ANY`, the enforcer expands the quantifier into concrete element indices and evaluates each. Empty-array semantics are defined in Section 5.5.

Sentinels (`ALL_OR_EMPTY`, `ALL`, `ANY`) are enforcer-level markers and MUST NOT be passed into calldata traversal functions. Enforcers MUST pre-process quantified paths by expanding them into concrete element paths.

### 7.4 Value Canonicalization

Before applying an operator, an enforcer MUST canonicalize the resolved calldata value to the encoding defined in §4.5 for its declared type. The declared type is the type code resolved by descriptor navigation (Callcium Descriptor Spec, Section 6). Given the raw 32-byte word loaded at the resolved location:

- **Unsigned integers (`0x00`–`0x1F`), `address`, `bool`**: zero all bits above the type's value width — `N * 8` bits for `uintN`, 160 for `address`, 1 for `bool`.
- **Signed integers (`0x20`–`0x3F`)**: sign-extend from the type's most-significant byte (EVM `SIGNEXTEND`).
- **Fixed bytes (`0x50`–`0x6F`) and `function` (`0x42`)**: zero the low `(32 − N)` padding bytes (the value is left-aligned in the high `N` bytes; `N = 24` for `function`, encoded identical to `bytes24`).
- **`uint256`, `int256`, `bytes32`**: no change; the value occupies the full word.

Canonicalization normalizes the value; it MUST NOT reject non-canonical calldata. A word carrying bits outside the declared width is evaluated by its canonical value, not its raw bytes.

`bool` is canonicalized by masking to the low bit (`value & 1`): a word whose low bit is clear is `false`, otherwise `true`. This is deliberate and matches an assembly consumer computing `and(x, 1)`; it is not an `x != 0` test. No canonically-encoded `bool` (0 or 1) is affected.

Context values (`scope == 0`) are exempt: per §5.4 they are evaluated as raw 32-byte words.

### 7.5 Conformance Boundary

This specification defines evaluation semantics for well-formed policies (Section 8.1). Enforcers are not required to verify validity (Section 8.2) or canonical form (Section 8.3). Evaluating a well-formed but invalid policy may surface implementation-defined integrity errors (Section 9.2). Canonical form affects byte identity only, not the verdict.

---

## 8. Validation Rules

### 8.1 Well-Formedness

A policy is well-formed if it satisfies all of the following invariants. Validators MUST reject a policy that is not well-formed before evaluating it. Where that rejection happens — decoding, storage, or a standalone validation pass — is implementation-defined.

- **PWF-1**: The policy is at least 8 bytes (minimum fixed header).
- **PWF-2**: `(header & VERSION_MASK) == 0x01`.
- **PWF-3**: `(header & RESERVED_MASK) == 0x00`.
- **PWF-4**: If `FLAG_NO_SELECTOR` is set, `selector == 0x00000000`.
- **PWF-5**: `descLength >= 2`.
- **PWF-6**: `7 + descLength + 1` does not exceed the policy blob size.
- **PWF-7**: `desc` is a well-formed descriptor (Callcium Descriptor Spec, Section 7.1).
- **PWF-8**: `groupCount >= 1`.
- **PWF-9**: Every group has `ruleCount >= 1`.
- **PWF-10**: Every group has `groupSize >= ruleCount * RULE_MIN_SIZE`.
- **PWF-11**: The rules of every group exactly fill its declared `groupSize`.
- **PWF-12**: No trailing bytes remain after the last group.
- **PWF-13**: Every rule's `ruleSize` equals the computed size (`4 + pathDepth*2 + 3 + dataLength`).
- **PWF-14**: Every rule's `scope` is 0 or 1.
- **PWF-15**: Every context rule (`scope == 0`) has `pathDepth == 1`.
- **PWF-16**: Every context rule's `path[0]` is a defined context property ID (Section 5.4).
- **PWF-17**: Every rule has `pathDepth <= MAX_PATH_DEPTH` (Section 8.4).
- **PWF-18**: Every rule's path is non-empty and an even number of bytes.
- **PWF-19**: Every rule's `opCode` (masked with `0x7F`) is a defined operator.
- **PWF-20**: Every rule's `dataLength` matches its operator's data format (Section 4.4).
- **PWF-21**: Every `IN` operator's operands are strictly ascending by lexicographic comparison of their 32-byte encodings. Strict ascent implies deduplication.

### 8.2 Validity

A policy is valid if it is well-formed and satisfies the following invariants. Builders MUST NOT emit an invalid policy. Enforcers are not required to verify these invariants (Section 7.5).

- **PV-1**: Every calldata rule's path navigates the descriptor without stepping into an elementary type or past a tuple's field count.
- **PV-2**: Every operator is compatible with its target's declared type per the compatibility matrix (Section 5.7).
- **PV-3**: Quantifier steps (`ALL_OR_EMPTY`/`ALL`/`ANY`) appear only immediately after array nodes, and reserved indices (`>= 0xFFFD`) do not appear as explicit indices.
- **PV-4**: No two rule definitions within a group target the same `(pathBytes, quantifier)` pair. A single definition may still compile to multiple binary rules on the same path — range composition (e.g., `gte(5)` + `lte(10)`) produces two rules, or may be optimized into a single `BETWEEN`.
- **PV-5**: Every group is satisfiable. Builders MUST detect at least: bound contradictions (conflicting equalities, values outside type range, impossible ranges), set contradictions (empty intersection, all values excluded), and bitmask contradictions (conflicting `bitmaskAll`/`bitmaskNone` bits). Builders MAY detect more.

### 8.3 Canonical Form

A policy is canonical if it is valid and its encoding satisfies the following invariants. Builders MUST emit canonical policies: two canonical encodings of the same policy are byte-identical, so `keccak256(policy)` identifies the policy. Canonical form does not affect verdicts (Section 7.5).

- **PC-1**: Operator operands use the canonical 32-byte encodings of Section 4.5.
- **PC-2**: Rules within each group are sorted by `(scope, pathDepth, pathBytes, operatorBytes)` ascending (Sections 6.5–6.6).
- **PC-3**: Groups are sorted ascending by group hash, where `groupHash = keccak256(ruleBytes)` and `ruleBytes` is the concatenation of the group's rule byte sequences in their already-sorted order (PC-2). The group hash is not serialized; it is derived from the on-wire rule bytes for sorting purposes only.

### 8.4 Normative Limits

| Constant | Value | Category | Invariant | Derivation |
|:---|:---|:---|:---|:---|
| `MAX_PATH_DEPTH` | 32 steps | Design | PWF-17 | The 1-byte `pathDepth` field allows 255; capped for evaluation cost. |
| `MAX_QUANTIFIED_ARRAY_LENGTH` | 256 elements | Design | — | Evaluation-time bound on `ANY`/`ALL`/`ALL_OR_EMPTY` iteration; exceeding it is a `QUANTIFIER_LIMIT_EXCEEDED` violation (Section 9.1). |
| `MAX_POLICY_SIZE` | 24,575 bytes | Design | — | Storage bound enforced by the onchain registry at store time; not a wire-format invariant. |
| `RULE_MIN_SIZE` | 9 bytes | Derived | PWF-10 | Minimal rule: one path step, no data (Section 5.2). |
| `IN` set cardinality | [1, 2,047] | Derived | PWF-20 | Lower bound: variadic data is a positive multiple of 32 (Section 4.4); upper bound: `⌊65,535 / 32⌋` from the 2-byte `dataLength`. |
| Groups per policy | 255 | Format | — | 1-byte `groupCount`. |
| Rules per group | 65,535 | Format | — | 2-byte `ruleCount`. |
| Rule size | 65,535 bytes | Format | — | 2-byte `ruleSize`. |
| Group size | 4,294,967,295 bytes | Format | — | 4-byte `groupSize`. |
| Operator payload | 65,535 bytes | Format | — | 2-byte `dataLength`. |
| Path depth (encoded) | 255 | Format | — | 1-byte `pathDepth`; the effective cap is `MAX_PATH_DEPTH`. |
| Descriptor length | 65,535 bytes | Format | — | 2-byte `descLength`. |

Limits without an invariant reference (—) are either bounds of the encoding itself (no byte string can exceed them) or enforced outside policy validation, as noted.

Limit categories:

- **Format**: Structural constraint from the binary encoding field width. Cannot change without a format version bump.
- **Derived**: Mechanically follows from other limits.
- **Design**: Operational cap chosen for evaluation cost, storage, or usability. Normative and fixed for format version 1: all conformant implementations enforce the same value.

Descriptor format limits are defined in the Callcium Descriptor Spec, Section 7.3. Conformant policy encoders MUST respect those limits when constructing embedded descriptors.

---

## 9. Enforcement Outcome Semantics

### 9.1 Enforcement Violations

Violations are calldata-dependent failures: different calldata could change the outcome. Conformant implementations SHOULD use these codes when exposing machine-readable enforcement outcomes. Implementations MAY map them to reverts, return values, exceptions, or other diagnostics as appropriate for the execution environment.

| Code | Description |
|:---|:---|
| `VALUE_MISMATCH` | Logical operator not satisfied on the resolved value. |
| `SELECTOR_MISMATCH` | Calldata selector does not match the policy header. |
| `MISSING_SELECTOR` | Calldata too short to contain a 4-byte selector. |
| `CALLDATA_OUT_OF_BOUNDS` | Runtime calldata read failure: calldata truncated or offset points beyond available bytes. |
| `ARRAY_INDEX_OUT_OF_BOUNDS` | Dynamic array in calldata is shorter than the index required by the rule. |
| `MISSING_CONTEXT` | Recognized context property not provided at runtime. |
| `QUANTIFIER_LIMIT_EXCEEDED` | Array length exceeds the enforcer iteration limit. |
| `QUANTIFIER_EMPTY_ARRAY` | `ANY` or `ALL` quantifier evaluated over an empty array. |

### 9.2 Integrity Errors

Integrity errors are descriptor-fixed or policy-fixed failures: no calldata can resolve them. They correspond to violations of validity invariants (Section 8.2), such as a path targeting a non-existent tuple field: builders MUST NOT emit policies containing them, and enforcers MAY retain checks for them as defense-in-depth. Names and granularity are implementation-specific.

### 9.3 Violation Effects and Control Flow

Each violation code has a normative effect on evaluation:

| Code | Effect |
|:---|:---|
| `VALUE_MISMATCH` | Group-local |
| `SELECTOR_MISMATCH` | Abort |
| `MISSING_SELECTOR` | Abort |
| `CALLDATA_OUT_OF_BOUNDS` | Abort |
| `ARRAY_INDEX_OUT_OF_BOUNDS` | Abort |
| `MISSING_CONTEXT` | Group-local |
| `QUANTIFIER_LIMIT_EXCEEDED` | Abort |
| `QUANTIFIER_EMPTY_ARRAY` | Group-local |

- **Group-local**: the containing group fails; evaluation continues with the next group.
- **Abort**: evaluation stops; the policy rejects without evaluating further groups.

Enforcers MUST produce the same accept/reject verdict for identical policy, calldata, and context. Control flow and reporting MAY differ: a fail-fast enforcer that stops at the first failure and a collect-all enforcer that reports every violation of the evaluated groups are both conformant, provided the verdict is identical.

---

## 10. References

- [ABI Specification](https://docs.soliditylang.org/en/latest/abi-spec.html) (Solidity documentation, applicable to all EVM languages).
- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) — Key words for use in RFCs to Indicate Requirement Levels.
- Callcium Descriptor Spec.
- Callcium reference implementation (non-normative).

---

## Appendix A. Changelog
- v1.2 (2026-07-05): Added `basefee` and `gasprice` context property IDs (Section 5.4).
- v1.1 (2026-07-04): Sections 7–9 restructured into labeled well-formedness, validity, and canonical-form invariants; violation effects made normative (Section 9.3).
- v1.0 (2026-02-22): Initial specification.

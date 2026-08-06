# Callcium Policy Spec

## 1. Document Control
- Version: 2.0
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

- **Bits 3-0 (version)**: Format version (`VERSION`, Section 5.1).
- **Bit 4 (FLAG_NO_SELECTOR)**: If set, the policy targets raw ABI-encoded calldata without a 4-byte function selector. The selector slot is ignored by the enforcer, which uses `baseOffset = 0` instead of `4`.
- **Bits 7-5 (reserved)**: MUST be zero. Validators MUST reject non-zero reserved bits.

**Invariants:**
- `(header & VERSION_MASK) == VERSION`. The policy format version is independent of the descriptor format version.
- `(header & RESERVED_MASK) == 0x00`. Reserved bits must be zero.
- If `(header & FLAG_NO_SELECTOR) != 0`: `selector == 0x00000000` (canonical encoding).
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
+----------+--------+-----------+---------------+--------------+--------+------------+------------------+
| ruleSize | scope  | pathDepth | path          | hint         | opCode | dataLength | data             |
| 2 bytes  | 1 byte | 1 byte    | 2*depth bytes | 0|5|13 bytes | 1 byte | 2 bytes    | dataLength bytes |
+----------+--------+-----------+---------------+--------------+--------+------------+------------------+
```

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 0 | ruleSize | 2 | Total size of this rule in bytes, including this field (big-endian) |
| 2 | scope | 1 | Rule scope (0=context, 1=calldata) |
| 3 | pathDepth | 1 | Number of path steps |
| 4 | path | 2*depth | Path steps (big-endian uint16 each) |
| 4+2*depth | hint | hintSize | Compiled hint block (calldata rules only; see below) |
| 4+2*depth+hintSize | opCode | 1 | Comparison operator |
| 5+2*depth+hintSize | dataLength | 2 | Length of data section (big-endian) |
| 7+2*depth+hintSize | data | dataLength | Operator-specific data |

**Invariants:**
- `ruleSize == 4 + pathDepth*2 + hintSize + 3 + dataLength`.
- When `scope == 0`: `pathDepth == 1`, `path[0]` is a reserved context property ID, and `hintSize == 0` (context rules carry no hint block).
- When `scope == 1`: `pathDepth >= 1`, the path navigates calldata structure, and the rule carries a hint block.

**Compiled Hint Block:**

The hint block embeds the precomputed calldata offsets of the rule's target, compiled from the rule's path against the embedded descriptor. All offset fields are big-endian uint32, relative to `baseOffset` (Section 7.1), so hint bytes are identical for selector and selectorless policies. `typeCode` carries a descriptor type code (Callcium Descriptor Spec, Section 5). Hint constants are defined in Section 5.8.

A calldata path is **compilable** when every navigation offset is fixed by the descriptor alone:

- **Unquantified**: every node the path traverses before its final node is static (nonzero `staticWords`, Callcium Descriptor Spec, Section 4.3). The final node itself may be static or dynamic.
- **Quantified**: every node the path traverses before the quantified array node is static, the array node is a dynamic array, and its element type is static (hence every suffix node after the quantifier is static). A quantifier over a static array is not compilable: its element count is descriptor-declared, which the hint block does not carry.

A compilable path compiles to a concrete layout; a non-compilable path compiles to the sentinel:

| Layout | Size | Fields | Compiled from |
|--------|------|--------|---------------|
| Static | `HINT_STATIC_SIZE` (5) | `[headOffset:4][typeCode:1]` | Compilable unquantified path |
| Quantified | `HINT_QUANTIFIED_SIZE` (13) | `[arrayHead:4][elemStride:4][suffixOffset:4][typeCode:1]` | Compilable quantified path |
| Sentinel | `HINT_STATIC_SIZE` (5) | `[HINT_SENTINEL_OFFSET:4][HINT_TYPE_NONE:1]` | Any non-compilable path |

Field semantics:

- `headOffset`: byte offset of the final path node's head slot. For a static target this addresses the value word; for a dynamic target (`bytes`, `string`, dynamic array — reachable only by `LENGTH_*` operators, Section 5.7) it addresses the offset word, not the payload.
- `arrayHead`: byte offset of the quantified dynamic array's head slot (its offset word).
- `elemStride`: element ABI head size in bytes (`elemStaticWords × 32`; Callcium Descriptor Spec, Section 4.4).
- `suffixOffset`: byte offset of the target within each element (0 when the quantifier is the final path step).
- `typeCode`: descriptor type code of the resolved target; `HINT_TYPE_NONE` in the sentinel layout only.

**Hint size resolution.** `hintSize` is a deterministic function of the rule's own bytes, resolved in precedence order:

1. If the first 4 hint bytes equal `HINT_SENTINEL_OFFSET`: the block is the 5-byte sentinel.
2. Else, if the path contains a quantifier step (Section 5.5): the block is `HINT_QUANTIFIED_SIZE` bytes.
3. Else: the block is `HINT_STATIC_SIZE` bytes.

A concrete `headOffset` or `arrayHead` can never collide with `HINT_SENTINEL_OFFSET`: both are head-slot offsets reached through static navigation, and the maximum derivable static head offset (255 parameters × 4,095 static words × 32 bytes) is below it.

**Type Resolution:**
- For calldata rules with a concrete hint: the target type is the hint's `typeCode`; for valid policies it equals the code resolved by navigating the descriptor using the rule's path (PV-6).
- For calldata rules with a sentinel hint: the target type is resolved by navigating the descriptor using the rule's path (see Callcium Descriptor Spec, Section 6).
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

The encodings in this section define the canonical 32-byte form for operator operands and the form required of resolved calldata values (§7.4).

**Address (typeCode = 0x41):**
```
[0x000000000000000000000000][address:20]
```
Left-padded with 12 zero bytes.

**Unsigned Integers (typeCode = 0x01-0x20):**
```
[padding][value]
```
Left-padded to 32 bytes. Value occupies rightmost N bytes where N = typeCode.

**Signed Integers (typeCode = 0x21-0x40):**
```
[sign-extension][value]
```
Sign-extended to 32 bytes (two's complement). Comparison operators (`GT`, `LT`, `GTE`, `LTE`, `BETWEEN`) MUST use signed arithmetic (EVM `slt`/`sgt`). The `EQ` and `IN` operators use bitwise equality and are sign-agnostic.

**Boolean (typeCode = 0x42):**
```
[0x00...00][0x00 or 0x01]
```
0x00 = false, 0x01 = true. Only `EQ` and its negation are valid for booleans.

**Function (typeCode = 0x43):**
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
VERSION          = 0x02   // format version (lower nibble of header)
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

### 5.8 Compiled Hint Constants

```
HINT_STATIC_SIZE = 5               // headOffset(4) + typeCode(1)
HINT_QUANTIFIED_SIZE = 13          // arrayHead(4) + elemStride(4) + suffixOffset(4) + typeCode(1)
HINT_SENTINEL_OFFSET = 0xFFFFFFFF  // first hint field: the path is not compilable
HINT_TYPE_NONE = 0x00              // sentinel typeCode: the reserved descriptor code (Callcium Descriptor Spec, Section 5.3)
```

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
- A path MUST contain at most one quantifier step. Nested quantifiers are forbidden in this format version.
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

The hint block does not participate in the sort key: it is a deterministic function of the path and the descriptor (PV-6).

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

1. Extract version from header byte (`header & VERSION_MASK`); verify `== VERSION`.
2. If `FLAG_NO_SELECTOR` is not set: verify selector in calldata matches policy selector; set `baseOffset = 4`.
3. If `FLAG_NO_SELECTOR` is set: skip selector validation; set `baseOffset = 0`.
4. Extract descriptor from policy header.
5. Evaluate groups in order; first passing group succeeds (OR semantics).
6. Within each group, all rules must pass (AND semantics).

### 7.2 Rule Evaluation

- Context rules (`scope == 0`) resolve the value from the execution environment using the context property ID in `path[0]`.
- Calldata rules (`scope == 1`) resolve the target location per the hint block, exclusively: a rule with a concrete hint MUST be resolved through the hint, and a rule with a sentinel hint MUST be resolved by traversing calldata using the descriptor and path (see Callcium Descriptor Spec, Section 6) and loading the value at the resolved location. Hint-resolved reads are subject to the same calldata bounds checks as traversal reads (Callcium Descriptor Spec, Section 6.5).
  - Static hint, static target: the value is the 32-byte word at `baseOffset + headOffset`.
  - Static hint, dynamic target: the word at `baseOffset + headOffset` is the ABI offset of the target's payload; the payload base is `baseOffset` plus that word (`LENGTH_*` rules only).
  - Quantified hint: element addressing per Section 7.3.
- The resolved value is checked against the canonical encoding of its declared type per §7.4, then the value and type code are checked against the operator and data.
- For `LENGTH_*` operators, the resolved value is the declared length read at the target's payload base: the element count for dynamic arrays, the byte length for `bytes` and `string`. Enforcers MUST verify that the declared payload extent — `length × stride` bytes, where the stride is 1 for `bytes`/`string`, 32 for arrays of dynamic elements (one offset word per element), and the element's ABI head size (`elemStaticWords × 32`; Callcium Descriptor Spec, Section 4.4) for arrays of static elements — lies within calldata bounds before applying the operator; an overrun is a `CALLDATA_OUT_OF_BOUNDS` violation.

### 7.3 Quantifier Handling

When a path contains `ALL_OR_EMPTY`, `ALL`, or `ANY`, the enforcer evaluates the rule against concrete elements. Empty-array semantics are defined in Section 5.5. Dispatch follows the hint block (Section 7.2):

- Quantified (13-byte) hint: the array base is `baseOffset` plus the offset word at `baseOffset + arrayHead`; the element count is the length word at the array base; the target of element `i` is at `arrayBase + 32 + i*elemStride + suffixOffset`. The quantifier step is the only part of the path consulted at runtime — it selects the empty-array semantics; all addressing comes from the hint.
- Sentinel hint: the enforcer expands the quantifier into concrete element indices and evaluates each via traversal.

Quantifier steps (`ALL_OR_EMPTY`, `ALL`, `ANY`) are enforcer-level markers and MUST NOT be passed into calldata traversal functions. When expanding via traversal, enforcers MUST substitute concrete element indices.

### 7.4 Canonical Value Encoding

Before applying an operator, an enforcer MUST verify that the resolved calldata value carries the encoding defined in §4.5 for its declared type. The declared type is the rule's target type code (Section 4.3, Type Resolution). For the raw 32-byte word loaded at the resolved location, that encoding requires:

- **Unsigned integers (`0x01`–`0x20`), `address`, `bool`**: all bits above the type's value width are zero — `N * 8` bits for `uintN`, 160 for `address`, 1 for `bool`.
- **Signed integers (`0x21`–`0x40`)**: the word is sign-extended from the type's most-significant byte (EVM `SIGNEXTEND`).
- **Fixed bytes (`0x50`–`0x6F`) and `function` (`0x43`)**: the low `(32 − N)` padding bytes are zero (the value is left-aligned in the high `N` bytes; `N = 24` for `function`, encoded identical to `bytes24`).
- **`uint256`, `int256`, `bytes32`**: unconstrained; the value occupies the full word.

A word that does not meet the requirement for its declared type is a `NON_CANONICAL_VALUE` violation.

Context values (`scope == 0`) are exempt: per §5.4 they are evaluated as raw 32-byte words.

### 7.5 Conformance Boundary

This specification defines evaluation semantics for well-formed policies (Section 8.1). Enforcers are not required to verify validity (Section 8.2) or canonical form (Section 8.3). Evaluating a well-formed but invalid policy may surface implementation-defined integrity errors (Section 9.2). When such a policy is evaluated rather than rejected, a calldata rule's stored hint remains authoritative even where it diverges from the compilation of its path: dispatch follows the hint (Section 7.2). Hint–path agreement is a validity property (PV-6), not an evaluation-time check. Canonical form affects byte identity only, not the verdict.

---

## 8. Validation Rules

### 8.1 Well-Formedness

A policy is well-formed if it satisfies all of the following invariants. Validators MUST reject a policy that is not well-formed before evaluating it. Where that rejection happens — decoding, storage, or a standalone validation pass — is implementation-defined.

- **PWF-1**: The policy is at least 8 bytes (minimum fixed header).
- **PWF-2**: `(header & VERSION_MASK) == VERSION`.
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
- **PWF-13**: Every rule's `ruleSize` equals the computed size (`4 + pathDepth*2 + hintSize + 3 + dataLength`, where `hintSize` is 0 for context rules and resolved per Section 4.3 for calldata rules).
- **PWF-14**: Every rule's `scope` is 0 or 1.
- **PWF-15**: Every context rule (`scope == 0`) has `pathDepth == 1`.
- **PWF-16**: Every context rule's `path[0]` is a defined context property ID (Section 5.4).
- **PWF-17**: Every rule has `pathDepth <= MAX_PATH_DEPTH` (Section 8.4).
- **PWF-18**: Every rule has `pathDepth >= 1`.
- **PWF-19**: Every rule's `opCode` (masked with `0x7F`) is a defined operator.
- **PWF-20**: Every rule's `dataLength` matches its operator's data format (Section 4.4).
- **PWF-21**: Every `IN` operator's operands are strictly ascending by lexicographic comparison of their 32-byte encodings. Strict ascent implies deduplication.
- **PWF-22**: In every calldata rule's hint block, the first 4 bytes equal `HINT_SENTINEL_OFFSET` if and only if the final byte (`typeCode`) equals `HINT_TYPE_NONE`.

### 8.2 Validity

A policy is valid if it is well-formed and satisfies the following invariants. Builders MUST NOT emit an invalid policy. Enforcers are not required to verify these invariants (Section 7.5).

- **PV-1**: Every calldata rule's path navigates the descriptor without stepping into an elementary type or past a tuple's field count.
- **PV-2**: Every operator is compatible with its target's declared type per the compatibility matrix (Section 5.7).
- **PV-3**: Quantifier steps (`ALL_OR_EMPTY`/`ALL`/`ANY`) appear only immediately after array nodes, and reserved indices (`>= 0xFFFD`) do not appear as explicit indices.
- **PV-4**: No group contains two byte-identical rules. Rules sharing a path are otherwise permitted: a single rule definition may compile to multiple binary rules on the same path — range composition (e.g., `gte(5)` + `lte(10)`) produces two rules, or may be optimized into a single `BETWEEN`. Definition-level uniqueness — at most one definition per `(scope, pathBytes)` pair within a group — is a builder obligation, not observable in the encoded policy: a multi-operator definition and multiple single-operator definitions on the same path encode identically.
- **PV-5**: Every group is satisfiable. Builders MUST detect at least: bound contradictions (conflicting equalities, values outside type range, impossible ranges), set contradictions (empty intersection, all values excluded), and bitmask contradictions (conflicting `bitmaskAll`/`bitmaskNone` bits). Builders MAY detect more.
- **PV-6**: Every calldata rule's hint block equals the deterministic compilation of its path against the embedded descriptor (Section 4.3): the concrete layout with its defined field values when the path is compilable, the sentinel layout when it is not.

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
| `RULE_MIN_SIZE` | 9 bytes | Derived | PWF-10 | Minimal parseable rule record: a context rule (no hint block) with one path step and an empty data section (Section 5.2). Not attainable by a well-formed rule — every operator payload is at least 32 bytes (PWF-20); this is a structural lower bound for PWF-10 only. |
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
- **Design**: Operational cap chosen for evaluation cost, storage, or usability. Normative and fixed for this format version: all conformant implementations enforce the same value.

Descriptor format limits are defined in the Callcium Descriptor Spec, Section 7.3. Conformant policy encoders MUST respect those limits when constructing embedded descriptors.

---

## 9. Enforcement Outcome Semantics

### 9.1 Enforcement Violations

Violations are calldata-dependent failures: different calldata could change the outcome. Conformant implementations SHOULD use these codes when exposing machine-readable enforcement outcomes. Implementations MAY map them to reverts, return values, exceptions, or other diagnostics as appropriate for the execution environment.

| Code | Description |
|:---|:---|
| `VALUE_MISMATCH` | Logical operator not satisfied on the resolved value. |
| `NON_CANONICAL_VALUE` | Resolved word is not the canonical encoding of its declared type (§7.4). |
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
| `NON_CANONICAL_VALUE` | Abort |
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
- v2.0 (2026-08-05): Initial specification.

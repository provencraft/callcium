# Callcium Policy Spec

## 1. Document Control
- Version: 3.0
- Status: Normative

---

## 2. Purpose, Scope, and Exclusions

This document specifies format version 3 of the binary format of Callcium policies. Callcium is a policy engine for ABI-encoded data. A policy defines the constraints that compliant ABI-encoded data satisfies.

### Scope
- Policy model and semantics.
- Binary format and encoding rules.
- Canonical form.
- Validation and enforcement semantics.
- Version rules.

### Exclusions

This document does not define:
- Builder API design or usage patterns.
- Implementation strategies or gas optimization techniques.
- Error names. This document defines violation codes (Section 11). The names of well-formedness, validity and integrity failures are implementation-defined.
- Descriptor format (see [Callcium Descriptor Spec](descriptor-v2.md)).

---

## 3. Terminology and Conformance

- This document uses the key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT, RECOMMENDED and MAY. RFC 2119 defines their meaning.
- "Storage validator" refers to any component that checks a policy blob against the well-formedness invariants of Section 9.1.
- "Build-time validator" refers to any component that checks a policy against the validity invariants of Section 9.2.
- "Builder" refers to any component that constructs policy blobs from higher-level definitions.
- "Enforcer" refers to any component that evaluates a policy against calldata and execution context.

An implementation is conformant if and only if it meets all MUST/REQUIRED obligations in Sections 4–11.

**Normative model.** The executable Lean model in [`spec/lean/Callcium/`](lean/Callcium/), outside `Sketch/` and `Theorems/`, is the normative definition of this format. This document states the model in prose. Each section names the Lean definitions that the section follows. If this document and the model do not agree, the model has priority. PV-5, PV-7 and PV-9 (Section 9.2) have no Lean definition. This document defines these invariants.

**Conformance vectors.** [`spec/vectors/descriptors.json`](vectors/descriptors.json), [`spec/vectors/policies.json`](vectors/policies.json), [`spec/vectors/encoding.json`](vectors/encoding.json), [`spec/vectors/enforcement.json`](vectors/enforcement.json) and [`spec/vectors/validation.json`](vectors/validation.json) pin storage verdicts, canonical flags (Section 7.4), normalized encodings (Section 7.1), enforcement verdicts and abort codes, and validity verdicts (Section 9.2). [`spec/lean/Vectors.lean`](lean/Vectors.lean) states how to check each vector. Error names in the vectors come from the reference implementation and are not normative. In `encoding.json`, `input` is a blob that storage accepts. `expected` is the blob that the encoder gives for the policy in `input`, over the signature that `input` embeds. An empty `expected` means that the encoder refuses the policy. In `enforcement.json`:

- `context` sets every property that the policy reads. The keys `msgSender`, `msgValue`, `blockTimestamp`, `blockNumber`, `chainId`, `txOrigin`, `baseFee`, `gasPrice` name the properties of Section 6.5.
- Exactly one of `expected`, `expectedError` and `integrityError` is present. `expected` is the verdict, `true` for pass and `false` for fail. `expectedError` is the abort code.
- On a fail, `violations` lists one group-local code per group. Otherwise, `violations` is absent.
- `integrityError: true` means that storage validation rejects the blob and enforcement ends in an integrity error (Section 11.2).

---

## 4. Policy Model

Normative definitions: [`Formula.lean`](lean/Callcium/Formula.lean), [`Evaluate.lean`](lean/Callcium/Evaluate.lean), [`Abi/Value.lean`](lean/Callcium/Abi/Value.lean).

### 4.1 Structure

A policy is in Disjunctive Normal Form (DNF): an OR of groups, where each group is an AND of rules. A rule is a test, a context test, or a loop whose body is one group.

```text
Policy   ::= Group₁ ∨ … ∨ Groupₙ                   n ≥ 1
Group    ::= Rule₁ ∧ … ∧ Ruleₘ                     m ≥ 1
Rule     ::= Test(path, Operator)                   -- the value at path, compared
           | ContextTest(property, Operator)        -- a context property, compared
           | Loop(quantifier, arrayPath, Body)      -- quantifier ∈ {ALL, ANY}
Body     ::= BodyRule₁ ∧ … ∧ BodyRuleₖ              k ≥ 1
BodyRule ::= Test(path, Operator) | ContextTest(property, Operator)
Operator ::= (negated, comparison, Operand)
Operand  ::= Constant(values) | Context(property)
```

- Groups have OR semantics: the policy holds if some group holds.
- Rules within a group have AND semantics: a group holds if every rule holds.
- A loop's body is one group, evaluated against each element of an array. A body contains tests and context tests, never a loop.

### 4.2 Values, Starting Points and Paths

- **Value**: a static elementary value is its 32-byte word. A `bytes` or `string` value is its bytes. A tuple or array is its list of fields or elements.
- **Path**: a sequence of field and element indices. A path is read from a starting point. A step that leaves the value (an element past an array's length) gives no value.
- **Starting point**: the value that a path is read from. At the root, the starting point is the function arguments, a tuple of the parameters. Inside a loop body, the starting point is the current element. A root path's first step is a parameter index. A body path's first step indexes into the element, and an empty body path is the element itself.
- **Context**: the properties of the execution environment (Section 6.5). Each property is a 32-byte word or absent. A provided property is present for every value, zero included.

### 4.3 Semantics

```text
holds(policy)                  = ∃ group ∈ policy. holds(group, arguments)
holds(group, point)            = ∀ rule ∈ group. holds(rule, point)
holds(Test(path, op), point)   = apply(op, point.at(path))
holds(ContextTest(p, op), _)   = apply(op, context[p])                      -- compared unsigned
holds(Loop(ALL, path, body), point)
                               = ∀ i < |elements|. holds(body, elements[i])  where elements = point.at(path)
holds(Loop(ANY, path, body), point)
                               = ∃ i < |elements|. holds(body, elements[i])
```

A loop holds over an empty array under `ALL` and fails under `ANY`. If the path of a loop does not give a list, the loop fails.

`apply(op, subject)` is the comparison's result, inverted when `negated`. In these cases, `apply` is false, negated or not:

- The subject is missing.
- A context operand is absent.
- The comparison does not apply to the subject.

| Comparison | Holds when (subject `v`) |
|---|---|
| `EQ a` | `v = a` |
| `GT a` | `v > a` |
| `LT a` | `v < a` |
| `GTE a` | `v ≥ a` |
| `LTE a` | `v ≤ a` |
| `BETWEEN min max` | `min ≤ v ≤ max` |
| `IN S` | `v ∈ S` |
| `BITMASK_ALL m` | `(v & m) = m` |
| `BITMASK_ANY m` | `(v & m) ≠ 0` |
| `BITMASK_NONE m` | `(v & m) = 0` |
| `LENGTH_EQ`, `LENGTH_GT`, `LENGTH_LT`, `LENGTH_GTE`, `LENGTH_LTE`, `LENGTH_BETWEEN` | The comparison without the `LENGTH_` prefix holds on the subject's length: the number of items of a list value, the byte length of `bytes` or `string`. |

If the subject is a signed integer, order comparisons on words are signed (two's complement). Otherwise, order comparisons are unsigned. `EQ`, `IN` and the bitmask comparisons compare bits. Context property values compare unsigned. Lengths and their operands compare unsigned.

Lean: `Formula.holds`, `Operator.holds`, `Comparison.apply`, `lessThan`, `Value.at`, `Value.length?`.

### 4.4 Path Examples

```
// Function: transfer(address to, uint256 amount)
// Rule: amount <= 1000
Test, path = [0x0001]          LTE 1000        // parameter 1

// Function: pay((address token, uint256 amount) payment)
// Rule: payment.amount <= 1000
Test, path = [0x0000, 0x0001]  LTE 1000        // parameter 0, field 1

// Function: batch((address to, uint256 amount)[] transfers)
// Rule: every transfer pays T, with an amount of at most 1000
Loop ALL, arrayPath = [0x0000]                 // parameter 0
    Test, path = [0x0000]   EQ T               // field 0 of the element
    Test, path = [0x0001]   LTE 1000           // field 1 of the same element

// Function: sweep(address[] recipients)
// Rule: at least one recipient is T
Loop ANY, arrayPath = [0x0000]
    Test, path = []         EQ T               // the element itself

// Function: route(uint256[] hops)
// Rule: the first hop is below 10
Test, path = [0x0000, 0x0000]  LT 10           // parameter 0, element 0
```

Every test in one loop body reads the same element. Each loop binds its own element: two `ANY` loops over one array can match different elements.

---

## 5. Wire Format

Normative definitions: [`Wire/Format.lean`](lean/Callcium/Wire/Format.lean), [`Hint.lean`](lean/Callcium/Hint.lean). All multi-byte fields are big-endian.

### 5.1 Policy Structure

```
+--------+----------+------------+----------+------------+----------+
| header | selector | descLength | desc     | groupCount | groups   |
| 1 byte | 4 bytes  | 2 bytes    | variable | 1 byte     | variable |
+--------+----------+------------+----------+------------+----------+
```

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 0 | header | 1 | Format version and flags (see below) |
| 1 | selector | 4 | Function selector, or zero for a selectorless policy |
| 5 | descLength | 2 | Descriptor length in bytes |
| 7 | desc | descLength | Embedded descriptor of the parameter types |
| 7+descLength | groupCount | 1 | Number of root groups |
| 8+descLength | groups | var | Concatenated root groups |

**Header byte layout:**
```
+----------+----------+------------------+
| major    | minor    | FLAG_NO_SELECTOR |
| bits 7-5 | bits 4-1 | bit 0            |
+----------+----------+------------------+
```

- **Bits 7–5 (`major`)**: `MAJOR`.
- **Bits 4–1 (`minor`)**: the lowest minor version that covers the features the blob uses (Section 10). For every blob of this document, `minor` is `MINOR`.
- **Bit 0 (`FLAG_NO_SELECTOR`)**: if this bit is set, the policy applies to raw ABI-encoded arguments that start at calldata offset 0, and the selector slot is zero. Otherwise, calldata starts with the selector and the arguments start at offset `SELECTOR_SIZE`.

### 5.2 Group Structure

**Root group:**
```
+-----------+-----------+----------+
| ruleCount | groupSize | rules    |
| 2 bytes   | 4 bytes   | variable |
+-----------+-----------+----------+
```

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 0 | ruleCount | 2 | Number of rules in the group |
| 2 | groupSize | 4 | Total bytes of the rules |
| 6 | rules | var | Concatenated rules |

**Loop body:** `ruleCount (2) | rules`, inside its loop rule (Section 5.6). The body's rules fill the loop rule after `ruleCount`.

The identity of a group is its 0-indexed position in the blob.

### 5.3 Rule Structure

Every rule starts with the same envelope:

```
+----------+--------+----------+
| ruleSize | scope  | payload  |
| 2 bytes  | 1 byte | variable |
+----------+--------+----------+
```

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 0 | ruleSize | 2 | Total size of the rule in bytes, including this field and any body |
| 2 | scope | 1 | Rule kind: `SCOPE_CONTEXT`, `SCOPE_CALLDATA` or `SCOPE_LOOP` |
| 3 | payload | var | Per scope (Sections 5.4–5.6) |

Root rules use any of the three scopes. Body rules use `SCOPE_CONTEXT` or `SCOPE_CALLDATA` and carry their own `ruleSize`.

### 5.4 Context Test (`scope = SCOPE_CONTEXT`)

```
+----------+--------+-----------+------------+----------+
| ruleSize | scope  | pathDepth | propertyId | operator |
| 2 bytes  | 1 byte | 1 byte    | 2 bytes    | variable |
+----------+--------+-----------+------------+----------+
```

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 3 | pathDepth | 1 | Always 1 |
| 4 | propertyId | 2 | Context property compared (Section 6.5) |
| 6 | operator | var | Operator (Section 5.8). The target type of the operator is the property's type |

A context test carries no hint.

### 5.5 Calldata Test (`scope = SCOPE_CALLDATA`)

```
+----------+--------+-----------+---------------+----------------+----------+
| ruleSize | scope  | pathDepth | path          | testHint       | operator |
| 2 bytes  | 1 byte | 1 byte    | 2*depth bytes | 8+8*hops bytes | variable |
+----------+--------+-----------+---------------+----------------+----------+
```

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 3 | pathDepth | 1 | Number of path steps |
| 4 | path | 2*depth | Path steps, 2 bytes each, from the rule's starting point |
| 4+2*depth | testHint | 8+8*hopCount | Compiled hint (Section 5.7) |
| 12+2*depth+8*hopCount | operator | var | Operator (Section 5.8). The target type of the operator is the hint's `typeCode` |

At the root, the path is nonempty and its first step is a parameter index. In a body, the path starts at the element. An empty body path reads the element itself.

### 5.6 Loop Rule (`scope = SCOPE_LOOP`)

```
+----------+--------+------------+-----------+---------------+----------------+-----------+----------+
| ruleSize | scope  | quantifier | pathDepth | arrayPath     | frameHint      | ruleCount | rules    |
| 2 bytes  | 1 byte | 1 byte     | 1 byte    | 2*depth bytes | 9+8*hops bytes | 2 bytes   | variable |
+----------+--------+------------+-----------+---------------+----------------+-----------+----------+
```

| Offset | Field | Size | Description |
|--------|-------|------|-------------|
| 3 | quantifier | 1 | `ALL` or `ANY` (Section 6.3) |
| 4 | pathDepth | 1 | Number of array path steps |
| 5 | arrayPath | 2*depth | Path to the array, from the arguments |
| 5+2*depth | frameHint | 9+8*hopCount | Compiled frame hint (Section 5.7) |
| 14+2*depth+8*hopCount | ruleCount | 2 | Number of body rules |
| 16+2*depth+8*hopCount | rules | var | Body rules: context tests and calldata tests, each with its own `ruleSize` |

The array path is nonempty. Body tests read paths from the element. Their paths and hints start at the element's encoding.

### 5.7 Compiled Hints

A hint addresses a value in calldata without the descriptor. A hint is a chain of hops from the starting point's encoding, then a final delta. Each hop crosses one offset word or selects one array element. Every path that a valid policy admits compiles to a hint (PV-2, PV-3).

**Test hint:**
```
+--------+------------------+-------------+------------+----------+
| header | hops             | targetDelta | targetMeta | typeCode |
| 1 byte | 8*hopCount bytes | 4 bytes     | 2 bytes    | 1 byte   |
+--------+------------------+-------------+------------+----------+
```

**Frame hint:**
```
+--------+------------------+------------+---------+---------+
| header | hops             | arrayDelta | count   | meta    |
| 1 byte | 8*hopCount bytes | 4 bytes    | 2 bytes | 2 bytes |
+--------+------------------+------------+---------+---------+
```

| Field | Size | Description |
|-------|------|-------------|
| header | 1 | Bits 7–6: reserved, zero. Bits 5–0: `hopCount`. |
| hops | 8 × hopCount | Hop entries, in order. |
| targetDelta | 4 | Test hint. Byte offset of the target from the base after the hops. |
| targetMeta | 2 | Test hint. Meta word of the target if `typeCode` is `DYNAMIC_ARRAY`, zero otherwise. |
| typeCode | 1 | Test hint. Descriptor type code of the target ([Descriptor Spec](descriptor-v2.md), Section 5). `BYTES`, `STRING` and `DYNAMIC_ARRAY` name the codes of `bytes`, `string` and dynamic arrays. |
| arrayDelta | 4 | Frame hint. Byte offset of the array from the base after the hops: the length word of a dynamic array, the first element of a static array. |
| count | 2 | Frame hint. Declared length of a static array, or 0 for a dynamic array. The enforcer reads the length of a dynamic array from calldata. A static array's declared length is at least 1 (Descriptor Spec DWF-6). |
| meta | 2 | Frame hint. Meta word of the array. |

**Hop entry:**
```
+---------+---------+---------+
| delta   | index   | meta    |
| 4 bytes | 2 bytes | 2 bytes |
+---------+---------+---------+
```

- **Plain hop** (`index == HINT_NO_INDEX`): enters the node whose offset word lies `delta` bytes past the current base. `meta` is zero.
- **Element hop** (`index < PATH_MARKER_BASE`): moves to element `index` of the array whose encoding starts at the current base. `meta` is the array's meta word. `delta` is zero.

**Meta word:**
```
+----------------------+--------------------+------------+-------------+
| META_ELEMENT_DYNAMIC | META_DYNAMIC_ARRAY | reserved   | strideWords |
| bit 15               | bit 14             | bits 13-12 | bits 11-0   |
+----------------------+--------------------+------------+-------------+
```

- `META_ELEMENT_DYNAMIC`: the element type is dynamic. An offset word points to each element.
- `META_DYNAMIC_ARRAY`: the array is dynamic. A length word is before the elements.
- `strideWords`: the head size of the element in words: 1 for dynamic elements, the element's `staticWords` otherwise. The element stride in bytes is `strideWords * 32`.

**Compilation.** A hint is a deterministic function of a path and the type of the path's starting point. At the root, this type is the tuple of parameter types. In a body, this type is the element type. Compilation walks the path with:

- `delta`: a byte accumulator, initially 0.
- `entered`: a flag, initially true, set when the chain's base is where the current node's encoding starts.
- *Entering* a node: emit plain hop `[delta, HINT_NO_INDEX, 0]` and reset `delta` to 0.
- `staticWords(T)`: the head size in words of a static type `T`, 0 for a dynamic type ([Descriptor Spec](descriptor-v2.md), Section 4).
- `headSize(T)`: 32 when `T` is dynamic, `32 * staticWords(T)` otherwise.

For each step:

1. Field `k` of a tuple: if the tuple is dynamic and not entered, enter the tuple. Add the `headSize` of fields `0..k-1` to `delta`. The field is not entered.
2. Element `i` of a static array of static elements (`i` below its length): add `i * headSize(element)` to `delta`. The element is not entered.
3. Element `i` of a static array of dynamic elements (`i` below its length): if the array is not entered, enter the array. Emit element hop `[0, i, meta(array)]` and set `delta` to 0. The element is entered.
4. Element `i` of a dynamic array: if the array is not entered, enter the array. Emit element hop `[0, i, meta(array)]` and set `delta` to 0. If the element is dynamic, the element is entered.

A path with a step into an elementary type, past a tuple's last field, or past a static array's length does not compile.

- **Test hint**: after the last step, if the target is dynamic and not entered, enter the target. `targetDelta = delta`. `typeCode` is the target's code. `targetMeta` is `meta(target)` for a dynamic array, zero otherwise.
- **Frame hint**: the path ends at a dynamic array or at a static array of at least one element. If the array is dynamic and not entered, enter the array. `arrayDelta = delta`. `count` and `meta` come from the array. Body tests compile from the element type.

Hint bytes are identical for selector and selectorless policies: chains start at the starting point's encoding.

Lean: `AbiType.walk`, `AbiType.compile?`, `AbiType.compileLoop?`, `ArrayMeta.of`, `Hint.wire`, `LoopHint.frame`.

### 5.8 Operators

```
+--------+------------+------------------+
| opCode | dataLength | data             |
| 1 byte | 2 bytes    | dataLength bytes |
+--------+------------+------------------+
```

**opCode layout:**
```
+-------+----------+------------+
| NOT   | source   | comparison |
| bit 7 | bits 6-5 | bits 4-0   |
+-------+----------+------------+
```

- **NOT**: inverts the comparison's result (Section 4.3).
- **source**: with `SOURCE_CONSTANT`, the data contains constants. With `SOURCE_CONTEXT`, the data contains a 2-byte context property ID, and the value of that property is the operand. Other values are reserved.
- **comparison**: Section 6.4.

**Operator data formats.** `w` is the width of the operand type (Section 5.9): the target's type for word comparisons, `LENGTH_TYPE` for length comparisons.

| Comparison | Constant source data | Context source data |
|---|---|---|
| `EQ` | `[value:w]` | `[propertyId:2]` |
| `GT`, `LT`, `GTE`, `LTE` | `[bound:w]` | `[propertyId:2]` |
| `BETWEEN` | `[min:w][max:w]` | — |
| `IN` | `[v1:w][v2:w]...[vn:w]`, n ≥ 1, strictly ascending as loaded words compared unsigned | — |
| `BITMASK_ALL`, `BITMASK_ANY`, `BITMASK_NONE` | `[mask:w]` | — |
| `LENGTH_EQ`, `LENGTH_GT`, `LENGTH_LT`, `LENGTH_GTE`, `LENGTH_LTE` | `[length:4]` | — |
| `LENGTH_BETWEEN` | `[min:4][max:4]` | — |

`dataLength` is `w` times the number of values, or 2 for a context source. Length comparisons apply to `bytes`, `string` and dynamic arrays. Every other comparison applies to static elementary types.

Lean: `Operator.opCode`, `Operator.data`, `Comparison.arity`, `operandType`.

### 5.9 Operand Encoding

A constant is as wide as its operand type. The constant loads into a 32-byte word as shown below. Comparisons use the loaded word (Section 4.3).

**Unsigned integers (`uintN`):**
```
data:   [value:N/8]
loaded: [0x00...00][value:N/8]
```
Big-endian, zero-extended on load.

**Signed integers (`intN`):**
```
data:   [value:N/8]
loaded: [sign-extension][value:N/8]
```
Two's complement, sign-extended on load. A mask on a signed target is its bit pattern of width N/8 and loads sign-extended.

**Address:**
```
data:   [address:20]
loaded: [0x000000000000000000000000][address:20]
```

**Boolean:**
```
data:   [0x00 or 0x01]
loaded: [0x00...00][0x00 or 0x01]
```

**Fixed bytes (`bytesN`):**
```
data:   [value:N]
loaded: [value:N][0x00...00]
```
Left-aligned on load.

**Function:**
```
data:   [address:20][selector:4]
loaded: [address:20][selector:4][0x0000000000000000]
```
Left-aligned on load, as `bytes24`.

**Length (`LENGTH_*` operands):**
```
data:   [length:4]
loaded: [0x00...00][length:4]
```
`LENGTH_TYPE`, unsigned.

A numeric constant outside its type's range, or a mask wider than its type, has no encoding.

Lean: `WordType.width`, `WordType.narrow`, `WordType.load`, `LENGTH_TYPE`, `contextPropertyType`.

### 5.10 Embedded Descriptor

`desc` is a descriptor ([Callcium Descriptor Spec](descriptor-v2.md)) of the function's parameter types. Storage requires a well-formed `desc` (PWF-4). Builders emit a valid `desc` (PV-1). Hints compile from `desc` (Section 5.7). Target type codes and operand widths follow the type codes in `desc`. Enforcers never read `desc`.

---

## 6. Constants

Normative definitions: [`Wire/Format.lean`](lean/Callcium/Wire/Format.lean), [`Formula.lean`](lean/Callcium/Formula.lean).

### 6.1 Version and Header
```
MAJOR            = 3      // format major version (header bits 7-5)
MINOR            = 0      // lowest minor of a blob that uses no extension (header bits 4-1)
MAJOR_SHIFT      = 5
MINOR_SHIFT      = 1
MINOR_MASK       = 0x0F   // minor after its shift
FLAG_NO_SELECTOR = 0x01   // header bit 0: selectorless policy
                          // header byte: 0x60 with a selector, 0x61 selectorless
SELECTOR_SIZE    = 4      // selector slot, and calldata bytes before the arguments
RULE_SIZE_SIZE   = 2      // ruleSize field, which counts itself
```

### 6.2 Scope Values
```
SCOPE_CONTEXT  = 0x00     // context test
SCOPE_CALLDATA = 0x01     // calldata test
SCOPE_LOOP     = 0x02     // loop rule, root only
```

### 6.3 Quantifiers
```
ALL = 0x01                // the body holds for every element; an empty array passes
ANY = 0x02                // the body holds for some element; an empty array fails
```

`0x00` is invalid.

### 6.4 Operator Codes

**opCode fields:**
```
NOT_FLAG        = 0x80    // bit 7
SOURCE_SHIFT    = 5       // source in bits 6-5
SOURCE_CONSTANT = 0
SOURCE_CONTEXT  = 1
```

**Comparisons (bits 4–0):**
```
EQ             = 0x01     // value == operand
GT             = 0x02     // value > operand
LT             = 0x03     // value < operand
GTE            = 0x04     // value >= operand
LTE            = 0x05     // value <= operand
BETWEEN        = 0x06     // min <= value <= max
IN             = 0x07     // value in {v1, v2, ...}
BITMASK_ALL    = 0x10     // (value & mask) == mask
BITMASK_ANY    = 0x11     // (value & mask) != 0
BITMASK_NONE   = 0x12     // (value & mask) == 0
LENGTH_EQ      = 0x18     // length(value) == operand
LENGTH_GT      = 0x19     // length(value) > operand
LENGTH_LT      = 0x1A     // length(value) < operand
LENGTH_GTE     = 0x1B     // length(value) >= operand
LENGTH_LTE     = 0x1C     // length(value) <= operand
LENGTH_BETWEEN = 0x1D     // min <= length(value) <= max
```

`0x00` is invalid. Every other value is reserved (Section 10).

### 6.5 Context Property IDs
```
CTX_MSG_SENDER      = 0x0000   // msg.sender (address)
CTX_MSG_VALUE       = 0x0001   // msg.value (uint256)
CTX_BLOCK_TIMESTAMP = 0x0002   // block.timestamp (uint256)
CTX_BLOCK_NUMBER    = 0x0003   // block.number (uint256)
CTX_CHAIN_ID        = 0x0004   // block.chainid (uint256)
CTX_TX_ORIGIN       = 0x0005   // tx.origin (address)
CTX_BASE_FEE        = 0x0006   // block.basefee (uint256)
CTX_GAS_PRICE       = 0x0007   // tx.gasprice (uint256)
CTX_MAX             = CTX_GAS_PRICE
```

The declared type determines operand widths and compatibility (Section 6.7). Enforcers treat context values as raw 32-byte words and do not check their encoding.

### 6.6 Path and Hint Constants
```
PATH_MARKER_BASE     = 0xFF00   // path steps and hop indices from here are reserved
HINT_NO_INDEX        = 0xFFFF   // hop index: plain hop
MAX_HOP_COUNT        = 63       // 6-bit hopCount
META_ELEMENT_DYNAMIC = 0x8000   // meta bit 15
META_DYNAMIC_ARRAY   = 0x4000   // meta bit 14
META_STRIDE_LIMIT    = 0x1000   // strideWords fills bits 11-0
LENGTH_TYPE          = uint32   // operand type of LENGTH_* comparisons
```

### 6.7 Operator-Type Compatibility Matrix

| Comparison | Constant source: target types | Context source: target and property types |
|---|---|---|
| `EQ` | `uintN`, `intN`, `address`, `bool`, `function`, `bytesN` | `uintN` with a `uint256` property, or `address` with an `address` property |
| `GT`, `LT`, `GTE`, `LTE` | `uintN`, `intN` | `uintN` with a `uint256` property |
| `BETWEEN` | `uintN`, `intN` | — |
| `IN` | `uintN`, `intN`, `address`, `function`, `bytesN` | — |
| `BITMASK_ALL`, `BITMASK_ANY`, `BITMASK_NONE` | `uintN`, `intN`, `address`, `bytesN` | — |
| `LENGTH_*` | `bytes`, `string`, dynamic arrays | — |

The target type of a context test is the type of its subject property. Static arrays and tuples are not targets.

---

## 7. Canonical Form

Normative definitions: [`Formula.lean`](lean/Callcium/Formula.lean) (`normalize`, `Formula.normal`), [`Wire/Encode.lean`](lean/Callcium/Wire/Encode.lean) (`Policy.encode`).

A builder encodes the normal form of a policy. Two policies well-formed over one signature get the same bytes, and so the same `keccak256`, exactly when their normal forms are equal. Policies with equal meaning but different normal forms encode differently.

### 7.1 Normalization

`normalize` applies the rewrites below in this order:

```
normalize(policy)      = sortDedupe([normalizeGroup(group) for group in policy])
normalizeGroup(rules)  = finish(hoistContext(joinAllLoops([normalizeRule(rule) for rule in rules])))
normalizeRule(test)    = test with its operator made positive, then a one-member set made EQ,
                         then, for a context test against a context operand, the lower ID as subject
normalizeRule(loop)    = loop with body = normalizeGroup(body)
joinAllLoops(rules)    = each ALL loop joined, at its first position, with every later ALL loop over the same
                         array path; the joined body = finish(concatenated bodies)
hoistContext(rules)    = every ANY loop whose body contains a calldata test gives its context tests to the group
finish(rules)          = sortDedupe(fuseRanges(sortDedupe(rules)))
sortDedupe(items)      = sorted ascending (Section 7.2), repeats dropped
fuseRanges(rules)      = lone range pairs fused (Range fusion below), counted on the distinct rules
```

| Rewrite | Authored | Normal form |
|---|---|---|
| Positive comparison | `NOT GT a`, `NOT LT a`, `NOT GTE a`, `NOT LTE a` | `LTE a`, `GTE a`, `LT a`, `GT a` |
| | `NOT BITMASK_ANY m`, `NOT BITMASK_NONE m` | `BITMASK_NONE m`, `BITMASK_ANY m` |
| | `NOT LENGTH_GT a`, `NOT LENGTH_LT a`, `NOT LENGTH_GTE a`, `NOT LENGTH_LTE a` | `LENGTH_LTE a`, `LENGTH_GTE a`, `LENGTH_LT a`, `LENGTH_GT a` |
| One-member set | `IN {a}`, `NOT IN {a}` | `EQ a`, `NOT EQ a` |
| Context subject | context test `ctx(q) op ctx(p)`, `p < q` | `ctx(p) op' ctx(q)`, `op'` the swapped comparison |
| Loop join | `ALL path: B₁` and `ALL path: B₂` in one group | `ALL path: (B₁ ∧ B₂)` |
| Context hoist | `ANY path: (C ∧ T)`, `C` context tests, `T` containing a calldata test | `C ∧ ANY path: T` |
| Range fusion | exactly one unnegated constant `GTE a` and exactly one unnegated constant `LTE b` on one subject | `BETWEEN a b` |
| | exactly one unnegated `LENGTH_GTE a` and exactly one unnegated `LENGTH_LTE b` on one subject | `LENGTH_BETWEEN a b` |
| Order and repeats | rules and groups in any order, repeated | sorted ascending (Section 7.2), repeats dropped |

- The swapped comparisons: `EQ`↔`EQ`, `GT`↔`LT`, `GTE`↔`LTE`.
- A subject is a path from the rule's starting point or a context property.
- `ANY` loops over one array are not joined. `normalize` never distributes a disjunction.

Lean: `Operator.normalize`, `Rule.contextTestBySubject`, `joinLoops`, `hoistContext`, `fuseRanges`, `finishRules`, `sortGroups`.

### 7.2 Rule and Group Order

Builders MUST sort the rules in each group and each loop body ascending by their **size-free bytes**. The size-free bytes of a rule are the rule's bytes without its `ruleSize`. For a loop rule, the size-free bytes also omit the `ruleSize` of every body rule:

```
sizeFree(test) = scope || payload
sizeFree(loop) = scope || quantifier || pathDepth || arrayPath || frameHint || ruleCount
                 || sizeFree(body rule 1) || ... || sizeFree(body rule k)
```

Builders MUST sort root groups ascending by the concatenation of their rules' size-free bytes, without `ruleCount` and `groupSize`.

Because `scope` is the first byte, context tests sort first in every group. Groups that start with a context test sort first in the policy.

### 7.3 Comparison Algorithm

```
function compareRules(a, b):
    return lexicographicCompare(sizeFree(a), sizeFree(b))

function compareGroups(a, b):
    return lexicographicCompare(concat(sizeFree(r) for r in a.rules),
                                concat(sizeFree(r) for r in b.rules))
```

Lexicographic comparison of byte arrays: compare byte by byte from index 0. At the first different byte, the array with the smaller byte sorts first. If the shorter array is a prefix of the longer array, the shorter array sorts first.

Lean: `CompiledRule.sizeFree`, `CompiledPolicy.ordered`. Agreement with the order of `normalize`: `Policy.ordered_compile`.

### 7.4 Canonical Blobs

A blob is canonical if a new encoding of its policy gives the same blob:

1. Decode the policy from the blob (`Policy.decode`).
2. Decode the parameter types from the blob's descriptor (`Descriptor.decode`, [Descriptor Spec](descriptor-v2.md)).
3. Encode the policy over those types and the blob's selector (`Policy.encode`).
4. The blob is canonical if the result equals the blob. If either decode fails, the blob is not canonical.

- `Policy.encode` returns an empty byte string if:
  - a path does not compile,
  - a comparison does not apply to the path's target type, or
  - a constant is not a value of its operand type.
- A canonical blob satisfies PV-1 to PV-4, PV-6 and PC-1 to PC-8.
- Canonical and valid are independent: a canonical blob can fail PV-5, PV-7, PV-8 or PV-9, and a valid blob can be out of canonical form.

Builders MUST emit blobs that are canonical and valid. Normalization keeps the meaning of a policy (Section 4.3). Rule and group order decide only which abort, if any, ends evaluation (Section 11.3).

---

## 8. Evaluation

Normative definitions: [`Enforce.lean`](lean/Callcium/Enforce.lean) (`Policy.outcome`), [`Hint.lean`](lean/Callcium/Hint.lean). An outcome is pass, fail, or abort with a violation code.

### 8.1 Evaluation Algorithm

```
evaluate(blob, calldata, context):
    if len(blob) < 7: integrity error                                  // header, selector and descLength
    if major != MAJOR or minor > SUPPORTED_MINOR: integrity error      // before reading any rule
    if FLAG_NO_SELECTOR is not set:
        if len(calldata) < SELECTOR_SIZE: abort MISSING_SELECTOR
        if calldata[0 : SELECTOR_SIZE] != selector: abort SELECTOR_MISMATCH
        start = SELECTOR_SIZE
    else:
        start = 0
    for group in groups:                         // stored order
        outcome = evaluateGroup(group.rules, start)
        if outcome != fail: return outcome       // pass or abort
    return fail

evaluateGroup(rules, start):
    for rule in rules:                           // stored order
        outcome = evaluateRule(rule, start)
        if outcome != pass: return outcome       // fail or abort
    return pass
```

`SUPPORTED_MINOR` is the highest minor the enforcer implements: `MINOR` for an enforcer of this document. Enforcers evaluate groups and rules in stored order, not in canonical order. `start` is the offset of the starting point's encoding: the arguments at the root, the element in a loop body.

### 8.2 Calldata Reads and Chain Resolution

Positions add modulo 2^256. Lengths and counts read from calldata are full 256-bit words. Bounds checks use the exact sum or product, with no reduction modulo 2^256.

```
word(p):
    if p + 32 > len(calldata): abort CALLDATA_OUT_OF_BOUNDS
    return calldata[p : p + 32]

follow(base, head):
    offset = word(head)
    if base + offset > len(calldata): abort CALLDATA_OUT_OF_BOUNDS
    return base + offset

elementAt(meta, elements, index):
    slot = elements + index * meta.strideWords * 32
    return meta.ELEMENT_DYNAMIC ? follow(elements, slot) : slot

chain(base, hops):
    for hop [delta, index, meta] in hops:
        if index == HINT_NO_INDEX:
            base = follow(base, base + delta)
        else if meta.DYNAMIC_ARRAY:
            if index >= word(base): fail ARRAY_INDEX_OUT_OF_BOUNDS     // group-local (Section 11.3)
            base = elementAt(meta, base + 32, index)
        else:
            base = elementAt(meta, base, index)
    return base
```

Lean: `loadWord`, `follow`, `ArrayMeta.elementAt`, `Hop.apply`, `resolveHops`.

### 8.3 Rule Evaluation

```
evaluateRule(ContextTest(property, op), start):
    if context[property] is absent: fail MISSING_CONTEXT
    return compare(op, context[property])                // unsigned

evaluateRule(CalldataTest(hint, op), start):
    target = chain(start, hint.hops) + hint.targetDelta
    w = word(target)
    if hint.typeCode in {BYTES, STRING, DYNAMIC_ARRAY}:
        stride = hint.typeCode == DYNAMIC_ARRAY ? hint.targetMeta.strideWords * 32 : 1
        if target + 32 + w * stride > len(calldata): abort CALLDATA_OUT_OF_BOUNDS
        return compare(op, w)                            // the length, unsigned
    if not canonical(hint.typeCode, w): abort NON_CANONICAL_VALUE
    return compare(op, w)                                // signed for intN

compare(op, subject):
    if op.source == SOURCE_CONTEXT and context[op.property] is absent: fail MISSING_CONTEXT
    result = op.comparison(subject, operand values)      // Section 4.3
    return (result XOR op.NOT) ? pass : fail VALUE_MISMATCH
```

The checks of a calldata test run in this order: hint resolution, the target word, the payload extent or canonicity, then the context operand and the comparison. The hint, not the path, decides what a test reads.

Lean: `CompiledTest.outcome`, `TestHint.resolve`, `TestHint.compare`, `TestHint.payloadStride`, `Operator.holds`, `Operator.holdsLength`.

### 8.4 Canonical Value Encoding

Before an enforcer compares a static target's word, the enforcer MUST verify that the word is the canonical ABI encoding of the target type:

- **Unsigned integers (`uintN`), `address`, `bool`**: all bits above the type's value width are zero: N bits for `uintN`, 160 for `address`, 1 for `bool`.
- **Signed integers (`intN`)**: the word equals the sign extension of its low N bits.
- **Fixed bytes (`bytesN`) and `function`**: all bytes below the value are zero: the low `32 − N` bytes for `bytesN`, the low 8 bytes for `function`.
- **`uint256`, `int256`, `bytes32`**: unconstrained.

A word that does not meet the requirement is a `NON_CANONICAL_VALUE` violation. The requirement does not apply to lengths and context values.

Lean: `WordType.isCanonical`.

### 8.5 Loop Evaluation

```
evaluateRule(Loop(quantifier, frame, body), start):
    array = chain(start, frame.hops) + frame.arrayDelta
    if frame.count == 0:
        count = word(array); elements = array + 32
    else:
        count = frame.count; elements = array
    if count > MAX_QUANTIFIED_ARRAY_LENGTH: abort QUANTIFIER_LIMIT_EXCEEDED   // before any element
    for i in 0 ..< count:                                                    // index order
        element = elementAt(frame.meta, elements, i)
        outcome = evaluateGroup(body, element)
        if quantifier == ALL and outcome != pass: return outcome
        if quantifier == ANY and outcome != fail: return outcome
    if quantifier == ALL: return pass
    return fail QUANTIFIER_NO_MATCH                                          // the empty array included
```

A group-local violation in a body fails the body at that element. Under `ALL`, the violation fails the loop. Under `ANY`, evaluation moves to the next element.

Lean: `CompiledRule.run`, `FrameHint.resolveArray`, `FrameHint.resolveElement`, `Quantifier.run`.

### 8.6 Conformance Boundary

- This document defines evaluation for blobs that pass storage validation (Section 9.1). Enforcers check the blob's length and version at entry (Section 8.1). Enforcers do not validate the blob further. After those checks, the outcome on a blob that fails storage validation is undefined.
- Enforcers are not required to verify validity (Section 9.2) or canonical form (Section 9.3). A stored hint is authoritative, even if the hint is different from the compilation of its path.
- Canonical calldata is calldata that contains the canonical encoding of the arguments, after the selector, followed by any bytes. Enforcers MUST NOT reject calldata because of bytes after the encoding.

---

## 9. Validation Rules

### 9.1 Well-Formedness

Normative definition: [`Wire/Validate.lean`](lean/Callcium/Wire/Validate.lean) (`Policy.validate`).

A policy is well-formed if it satisfies all of the following invariants. A storage validator MUST reject a policy that is not well-formed.

- **PWF-1**: `major` is `MAJOR`.
- **PWF-2**: `minor` is the lowest minor that covers the features the blob uses: `MINOR` for every blob of this document.
- **PWF-3**: If `FLAG_NO_SELECTOR` is set, the selector is zero.
- **PWF-4**: `desc` is a well-formed descriptor (Descriptor Spec DWF-1 to DWF-8).
- **PWF-5**: `groupCount` is at least 1.
- **PWF-6**: Every group and every loop body has `ruleCount` at least 1.
- **PWF-7**: `desc` lies within the blob. The groups fill the blob after `groupCount`. Each group's rules fill its `groupSize`. Each rule's content fills its `ruleSize`. Each loop's body rules fill the loop rule after its `ruleCount`.
- **PWF-8**: Every rule's `scope` is `SCOPE_CONTEXT`, `SCOPE_CALLDATA` or `SCOPE_LOOP`.
- **PWF-9**: No loop body contains a loop.
- **PWF-10**: Every `quantifier` is `ALL` or `ANY`.
- **PWF-11**: Every context test has `pathDepth` 1 and a property ID at most `CTX_MAX`.
- **PWF-12**: Every root calldata test's path and every loop's array path is nonempty.
- **PWF-13**: Every path step is below `PATH_MARKER_BASE`.
- **PWF-14**: Every root path, every array path, and every body path together with its loop's array path, has at most `MAX_PATH_DEPTH` steps.
- **PWF-15**: Every hint `header` has bits 7–6 zero.
- **PWF-16**: Every hop is a plain hop with `index` `HINT_NO_INDEX` and `meta` zero, or an element hop with `index` below `PATH_MARKER_BASE` and `delta` zero.
- **PWF-17**: Every meta word has bits 13–12 zero. If `typeCode` is not `DYNAMIC_ARRAY`, `targetMeta` is zero.
- **PWF-18**: Every `comparison` is defined, and every `source` is `SOURCE_CONSTANT` or `SOURCE_CONTEXT`.
- **PWF-19**: Every comparison applies to its target type. A length comparison applies to `bytes`, `string` or a dynamic array. Every other comparison applies to a static elementary type.
- **PWF-20**: Every constant operand's `dataLength` is the operand width times the number of values: one, two for `BETWEEN` and `LENGTH_BETWEEN`, one or more for `IN` (Section 5.8).
- **PWF-21**: Every `IN` operand's members strictly ascend as loaded words compared unsigned.
- **PWF-22**: Every context source has `comparison` `EQ`, `GT`, `LT`, `GTE` or `LTE`, `dataLength` 2, and a property ID at most `CTX_MAX`.

### 9.2 Validity

Normative definitions: [`Wire/Encode.lean`](lean/Callcium/Wire/Encode.lean) (`Policy.WellFormed`), [`Formula.lean`](lean/Callcium/Formula.lean) (`Formula.WellFormed`).

A policy is valid if it is well-formed, satisfies PV-1 to PV-7, and its normal form (Section 7.1) satisfies PV-8 and PV-9. A build-time validator MUST reject an invalid policy. Builders MUST NOT emit an invalid policy. Enforcers are not required to verify validity (Section 8.6).

- **PV-1**: `desc` is a valid descriptor (Descriptor Spec DV-1, DV-2).
- **PV-2**: Every calldata test's path compiles from its starting point (Section 5.7): no step into an elementary type, past a tuple's last field, or past a static array's length.
- **PV-3**: Every loop's array path ends at a dynamic array or at a static array of at least one element.
- **PV-4**: Every hint equals the compilation of its path (Section 5.7).
- **PV-5**: Every operator is compatible with its target type per the compatibility matrix (Section 6.7).
- **PV-6**: Every `bool` constant is 0 or 1.
- **PV-7**: No loop walks a static array declared longer than `MAX_QUANTIFIED_ARRAY_LENGTH`.
- **PV-8**: Every loop body contains a calldata test.
- **PV-9**: In every group and every loop body, the rules on each subject (a path or a context property) meet these conditions:
  - The rules are satisfiable together.
  - No rule is implied by the others or holds for every value.
  - At most one rule bounds each side.

PV-9 reads the rules on one subject as conditions on the subject's value and the call's context. A context property is absent or has one value of its type. A rule fails on an absent property (Section 4.3). Rules are satisfiable together when some value and some context make all of the rules hold. A rule is implied by the others when every value and context that make the others hold make that rule hold too. A rule holds for every value when every value and every context make the rule hold.

### 9.3 Canonical Form

Normative definition: [`Formula.lean`](lean/Callcium/Formula.lean) (`Formula.normal`).

A policy is in canonical form if it satisfies the following invariants (Section 7).

- **PC-1**: NOT appears only on `EQ`, `BETWEEN`, `IN`, `BITMASK_ALL`, `LENGTH_EQ` and `LENGTH_BETWEEN`.
- **PC-2**: No `IN` has one member.
- **PC-3**: A context test with a context operand has a subject property ID at most the operand's.
- **PC-4**: No group contains two `ALL` loops over the same array path.
- **PC-5**: No `ANY` loop body that contains a calldata test contains a context test.
- **PC-6**: No group or body contains exactly one unnegated constant `GTE` and exactly one unnegated constant `LTE` on one subject. The same rule applies to `LENGTH_GTE` and `LENGTH_LTE`.
- **PC-7**: The rules of every group and every loop body strictly ascend by size-free bytes (Section 7.2).
- **PC-8**: The groups strictly ascend by the concatenation of their rules' size-free bytes (Section 7.2).

### 9.4 Normative Limits

| Constant | Value | Category | Invariant | Derivation |
|:---|:---|:---|:---|:---|
| `MAX_PATH_DEPTH` | 32 steps | Design | PWF-14 | Counted from the arguments across the enclosing loop. |
| `MAX_QUANTIFIED_ARRAY_LENGTH` | 256 elements | Design | PV-7 | A calldata length above this limit is a `QUANTIFIER_LIMIT_EXCEEDED` violation. A declared static length above this limit is a validity defect. |
| Groups per policy | 255 | Format | — | 1-byte `groupCount`. |
| Rules per group or body | 65,535 | Format | — | 2-byte `ruleCount`. |
| Rule size | 65,535 bytes | Format | — | 2-byte `ruleSize`, loop body included. |
| Group size | 4,294,967,295 bytes | Format | — | 4-byte `groupSize`. |
| Operator payload | 65,535 bytes | Format | — | 2-byte `dataLength`. |
| Descriptor length | 65,535 bytes | Format | — | 2-byte `descLength`. |
| Path depth (encoded) | 255 | Format | — | 1-byte `pathDepth`. The effective limit is `MAX_PATH_DEPTH`. |
| Hops per chain | `MAX_HOP_COUNT` | Format | PWF-15 | 6-bit `hopCount`. |
| Path step and element hop index | below `PATH_MARKER_BASE` | Format | PWF-13, PWF-16 | Steps and indices from `PATH_MARKER_BASE` are reserved. |
| `delta`, `targetDelta`, `arrayDelta` | 4,294,967,295 | Format | — | 4-byte fields. |
| `strideWords` | `META_STRIDE_LIMIT` − 1 | Format | — | 12 bits of the meta word. |
| `IN` set cardinality | [1, ⌊65,535 / width⌋] | Derived | PWF-20, PC-2 | 2-byte `dataLength` over the operand width: 2,047 at 32 bytes, 3,276 at 20. At least 2 in canonical form. |

Limit categories:

- **Format**: a field width bounds the limit. Builders MUST NOT emit a policy past a format limit.
- **Derived**: follows from other limits.
- **Design**: does not change within a minor version. Every conformant implementation enforces the same value for every blob of that minor.

Descriptor limits are defined in the [Callcium Descriptor Spec](descriptor-v2.md), Section 7.3.

---

## 10. Version Rules

- A blob declares the lowest minor version that covers the features the blob uses (PWF-2).
- A minor version assigns reserved values or shapes only. A minor version never changes the meaning of a blob that an earlier minor accepts.
- A release that supports minor `M` accepts every blob of a minor at most `M`. The release gives each such blob the outcome that the release of that minor gives. The release rejects a higher minor at storage (PWF-2) and at enforcement (Section 8.1).
- A later release MAY add build-time rejections for policies of an earlier minor, but never acceptances.
- A later minor MAY raise `MAX_PATH_DEPTH`, up to `MAX_HOP_COUNT`. A later minor MUST NOT lower either design limit.

**Reserved space:**

| Field | Reserved |
|---|---|
| `major` | every value other than `MAJOR` |
| `minor` | 1–15 |
| `scope` | `0x03`–`0xFF`, and a loop inside a body |
| `quantifier` | `0x03`–`0xFF` |
| `source` | 2, 3 |
| `comparison` | `0x08`–`0x0F`, `0x13`–`0x17`, `0x1E`, `0x1F` |
| Path steps | `PATH_MARKER_BASE`–`0xFFFF` |
| Hop `index` | `PATH_MARKER_BASE`–`0xFFFE` |
| Hint `header` | bits 7–6 |
| Meta word | bits 13–12 |

---

## 11. Enforcement Outcome Semantics

### 11.1 Enforcement Violations

Violations are calldata-dependent failures: different calldata or context can change the outcome. Conformant implementations that expose machine-readable enforcement outcomes SHOULD use these codes. Implementations MAY map these codes to reverts, return values, exceptions or other diagnostics.

| Code | Description |
|:---|:---|
| `VALUE_MISMATCH` | An operator is not satisfied on the resolved value. |
| `NON_CANONICAL_VALUE` | A target word is not the canonical encoding of its type (Section 8.4). |
| `SELECTOR_MISMATCH` | The calldata selector does not match the policy's. |
| `MISSING_SELECTOR` | Calldata is shorter than the selector. |
| `CALLDATA_OUT_OF_BOUNDS` | A read, an offset or a declared payload extends past the end of calldata. |
| `ARRAY_INDEX_OUT_OF_BOUNDS` | An element hop's index is at or past a dynamic array's length. |
| `MISSING_CONTEXT` | A context property the policy reads is absent. |
| `QUANTIFIER_LIMIT_EXCEEDED` | A loop's array is longer than `MAX_QUANTIFIED_ARRAY_LENGTH`. |
| `QUANTIFIER_NO_MATCH` | No element satisfies an `ANY` loop's body, the empty array included. |

### 11.2 Integrity Errors

The blob alone determines integrity errors: no calldata corrects an integrity error. An enforcer reports an integrity error at entry, before it reads any rule (Section 8.1). The causes are a blob shorter than its header, selector and `descLength` fields, and an unsupported version. The policy rejects without a violation code. Names and granularity are implementation-defined.

### 11.3 Violation Effects and Control Flow

| Code | Effect |
|:---|:---|
| `VALUE_MISMATCH` | Group-local |
| `NON_CANONICAL_VALUE` | Abort |
| `SELECTOR_MISMATCH` | Abort |
| `MISSING_SELECTOR` | Abort |
| `CALLDATA_OUT_OF_BOUNDS` | Abort |
| `ARRAY_INDEX_OUT_OF_BOUNDS` | Group-local |
| `MISSING_CONTEXT` | Group-local |
| `QUANTIFIER_LIMIT_EXCEEDED` | Abort |
| `QUANTIFIER_NO_MATCH` | Group-local |

- **Group-local**: the containing group fails and evaluation continues with the next group. Inside a loop body, the body fails at that element (Section 8.5).
- **Abort**: evaluation stops. The policy rejects with the code, and the enforcer does not evaluate further groups.

A group's first violation determines that group's outcome. The enforcer does not evaluate later rules of the group. On canonical calldata within limits, no abort occurs, so the outcome is the policy's meaning (Section 4.3). On other calldata, an abort in an earlier group rejects the calldata, even when a later group accepts that calldata.

Enforcers MUST produce the same outcome for identical policy, calldata and context: the verdict, or the abort and its code. Group-local codes and their locations are diagnostics, and their reporting MAY differ. If an enforcer evaluates further rules or groups for diagnostics, the outcome does not change.

---

## 12. Proven Properties

This section is informative. The theorems are in [`spec/lean/Callcium/Theorems/`](lean/Callcium/Theorems/). The `Policy` theorems other than `Policy.enforce_safe` hold for the blob that `Policy.encode` writes from a policy well-formed over its signature (`Policy.WellFormed`).

| Theorem | Statement |
|---|---|
| `normalize_holds` | Normalization keeps the meaning. |
| `normalize_idem`, `normal_iff_fixed` | Canonical forms are exactly the fixed points of `normalize`. |
| `normalize_of_sameMembers` | Rule and group order and repetition have no effect on the normal form. |
| `evaluateValues_exact` | A value-level evaluation that does not abort gives the meaning. |
| `evaluateValues_no_abort` | Within limits, value-level evaluation does not abort. |
| `WordType.isCanonical_eq_solcAcceptsWord` | The canonicity check (Section 8.4) equals the Solidity decoder's. |
| `Descriptor.valid_iff_encoded` | Valid descriptors are exactly the encodings of type lists within `Descriptor.withinLimits`. |
| `AbiType.decodeSolc_at_compile?` | Where a compiled hint resolves, the decoder reads the value at its path. |
| `Policy.validate_encode` | The blob of a well-formed policy is well-formed. |
| `Policy.encode_normalize`, `Policy.normalize_of_encode` | Over one signature, two well-formed policies encode alike exactly when their normal forms are equal. |
| `Policy.enforce_sound` | A pass means the policy holds on the arguments the decoder reads. |
| `Policy.enforce_exact` | An outcome that is not an abort is the policy's meaning. |
| `Policy.enforce_no_abort` | On canonical calldata within limits, enforcement does not abort. |
| `Policy.enforce_safe` | On every blob that storage accepts, the enforcer reads the blob as storage does, and its work is bounded. Bytes appended to calldata do not change an outcome that is not an abort. |

Assumptions: the decoder model `AbiType.decodeSolc` reads calldata as the Solidity 0.8.30 via-IR decoder does. Differential testing establishes this assumption. Context values are inputs. If a blob is built without the encoder and passes storage validation, only `Policy.enforce_safe` applies to the blob.

---

## 13. References

- [ABI Specification](https://docs.soliditylang.org/en/latest/abi-spec.html) (Solidity documentation, applicable to all EVM languages).
- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) — Key words for use in RFCs to Indicate Requirement Levels.
- [Callcium Descriptor Spec](descriptor-v2.md).
- [Callcium Lean model](lean/) (normative).
- Callcium reference implementation (non-normative).

---

## Appendix A. Encoding Examples

Both blobs are canonical storage vectors in [`spec/vectors/policies.json`](vectors/policies.json).

### A.1 Context Test and Calldata Test

`context-and-calldata`: `f(uint256 amount)` with `msg.sender == 0x…01` and `amount == 42` in one group.

```
60                          header: major 3, minor 0, selector present
2fbebd38                    selector
0003                        descLength = 3
020120                      desc: version 2, 1 parameter, uint256
01                          groupCount = 1
0002 0000004e               group 0: ruleCount = 2, groupSize = 78
  001d                      rule 0: ruleSize = 29
  00                        scope = SCOPE_CONTEXT
  01 0000                   pathDepth = 1, propertyId = CTX_MSG_SENDER
  01 0014                   opCode = EQ, dataLength = 20
  0000000000000000000000000000000000000001
  0031                      rule 1: ruleSize = 49
  01                        scope = SCOPE_CALLDATA
  01 0000                   pathDepth = 1, path = [0]
  00 00000000 0000 20       testHint: no hops, targetDelta = 0, targetMeta = 0, typeCode = uint256
  01 0020                   opCode = EQ, dataLength = 32
  000000000000000000000000000000000000000000000000000000000000002a
```

### A.2 Loop Rule

`loop-all`: `f(uint256[] values)` with every element above 0.

```
60                          header: major 3, minor 0, selector present
8b44cef1                    selector
0007                        descLength = 7
02018100000520              desc: version 2, 1 parameter, uint256[]
01                          groupCount = 1
0001 00000049               group 0: ruleCount = 1, groupSize = 73
  0049                      rule 0: ruleSize = 73
  02                        scope = SCOPE_LOOP
  01                        quantifier = ALL
  01 0000                   pathDepth = 1, arrayPath = [0]
  01                        frameHint: hopCount = 1
    00000000 ffff 0000      plain hop: delta = 0, the array's offset word
    00000000 0000 4001      arrayDelta = 0, count = 0 (dynamic), meta = META_DYNAMIC_ARRAY, strideWords = 1
  0001                      body ruleCount = 1
    002f                    body rule 0: ruleSize = 47
    01                      scope = SCOPE_CALLDATA
    00                      pathDepth = 0: the element itself
    00 00000000 0000 20     testHint: no hops, targetDelta = 0, targetMeta = 0, typeCode = uint256
    02 0020                 opCode = GT, dataLength = 32
    0000000000000000000000000000000000000000000000000000000000000000
```

---

## Appendix B. Changelog
- v3.0: Initial specification.

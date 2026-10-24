import Callcium.Formula
import Callcium.Hint
import Callcium.Descriptor.Codec

/-!
# Wire format

The byte layout of a policy blob in format v3: `header | selector | descLength | desc | groupCount | groups`. The header
byte carries `major` in bits 7–5, `minor` in bits 4–1 and `FLAG_NO_SELECTOR` in bit 0. A root group is `ruleCount |
groupSize | rules`. A rule is `ruleSize | scope | payload`. Its payload depends on `scope`: a context test, a calldata
test with its hint, or a loop with its hint and a body of tests. An operator is `opCode | dataLength | data`, and a
constant is as wide as its operand type. Multi-byte fields are big-endian.

`CompiledRule` is a rule as the blob carries it, with its hints and loaded operands. `CompiledRule.write` writes one,
and `CompiledRule.sizeFree` gives the bytes the canonical order compares: the rule's bytes with every `ruleSize`
removed, nested ones included.
-/

namespace Callcium

/-! ## Constants -/

namespace Policy

/-- The format's major version. -/
def MAJOR : Nat := 3

/-- The minor version of the core, the lowest minor covering a blob that uses no extension. -/
def MINOR : Nat := 0

/-- The position of `major` in the header byte. -/
def MAJOR_SHIFT : Nat := 5

/-- The position of `minor` in the header byte. -/
def MINOR_SHIFT : Nat := 1

/-- The mask of `minor` after its shift. -/
def MINOR_MASK : Nat := 0x0F

/-- Header bit 0: the policy reads arguments from offset 0, and its selector slot is zero. -/
def FLAG_NO_SELECTOR : Nat := 0x01

/-- A rule's `ruleSize` field, which counts itself. -/
def RULE_SIZE_SIZE : Nat := 2

/-- The function selector: the selector slot of the blob, and the calldata bytes before the arguments. -/
def SELECTOR_SIZE : Nat := 4

end Policy

/-- `scope` of a context test. -/
def SCOPE_CONTEXT : UInt8 := 0x00
/-- `scope` of a calldata test. -/
def SCOPE_CALLDATA : UInt8 := 0x01
/-- `scope` of a loop. -/
def SCOPE_LOOP : UInt8 := 0x02

/-- `source` of constant operand values. -/
def SOURCE_CONSTANT : Nat := 0
/-- `source` of a context property operand. -/
def SOURCE_CONTEXT : Nat := 1

/-- `opCode` bit 7: the result is negated. -/
def NOT_FLAG : Nat := 0x80
/-- The position of `source` in `opCode`. `comparison` fills the bits below it. -/
def SOURCE_SHIFT : Nat := 5

/-- A hop `index` naming a plain hop. -/
def HINT_NO_INDEX : Nat := 0xFFFF

/-- The most hops a chain carries: the 6-bit `hopCount` of a hint header, whose `kind` bits 7–6 are reserved. -/
def MAX_HOP_COUNT : Nat := 2 ^ 6 - 1

/-- Meta word bit 15: the elements are dynamic. -/
def META_ELEMENT_DYNAMIC : Nat := 0x8000
/-- Meta word bit 14: the array is dynamic. -/
def META_DYNAMIC_ARRAY : Nat := 0x4000
/-- One past the largest `strideWords`, which fills meta word bits 11–0. Bits 13–12 are reserved. -/
def META_STRIDE_LIMIT : Nat := 0x1000

/-! ## Codes -/

/-- The `comparison` value of a comparison. -/
def Comparison.code : Comparison → UInt8
  | .eq => 0x01
  | .gt => 0x02
  | .lt => 0x03
  | .gte => 0x04
  | .lte => 0x05
  | .between => 0x06
  | .in_ => 0x07
  | .bitmaskAll => 0x10
  | .bitmaskAny => 0x11
  | .bitmaskNone => 0x12
  | .lengthEq => 0x18
  | .lengthGt => 0x19
  | .lengthLt => 0x1A
  | .lengthGte => 0x1B
  | .lengthLte => 0x1C
  | .lengthBetween => 0x1D

/-- The comparison a `comparison` value names. None for `0x00` and the reserved values. -/
def Comparison.ofCode? (code : Nat) : Option Comparison :=
  [Comparison.eq, .gt, .lt, .gte, .lte, .between, .in_, .bitmaskAll, .bitmaskAny, .bitmaskNone, .lengthEq, .lengthGt,
    .lengthLt, .lengthGte, .lengthLte, .lengthBetween].find? (·.code.toNat == code)

/-- Whether the comparison reads a length rather than a word. -/
def Comparison.isLength : Comparison → Bool
  | .lengthEq | .lengthGt | .lengthLt | .lengthGte | .lengthLte | .lengthBetween => true
  | _ => false

/-- How many values a constant operand contains. None for `IN`, which contains one or more. -/
def Comparison.arity : Comparison → Option Nat
  | .between | .lengthBetween => some 2
  | .in_ => none
  | _ => some 1

/-- The `quantifier` value of a quantifier. -/
def Quantifier.code : Quantifier → UInt8
  | .all => 0x01
  | .any => 0x02

/-- The quantifier a `quantifier` value names. None for `0x00` and the reserved values. -/
def Quantifier.ofCode? (code : UInt8) : Option Quantifier :=
  if code = Quantifier.all.code then some .all else if code = Quantifier.any.code then some .any else none

/-- The type code of a type's node. -/
def AbiType.code : AbiType → UInt8
  | .word wordType => wordType.code
  | .bytes => TypeCode.BYTES
  | .string => TypeCode.STRING
  | .staticArray .. => TypeCode.STATIC_ARRAY
  | .dynamicArray _ => TypeCode.DYNAMIC_ARRAY
  | .tuple _ => TypeCode.TUPLE

/-! ## Operand widths -/

/-- The type a length is compared as: an unsigned integer. -/
def LENGTH_TYPE : WordType := .uint ⟨3⟩

/-- The type of a context property's value: `address` for `msg.sender` and `tx.origin`, `uint256` for every other ID. -/
def contextPropertyType (property : PropertyId) : WordType :=
  if property = CTX_MSG_SENDER ∨ property = CTX_TX_ORIGIN then .address else .uint ⟨31⟩

/-- Whether a value of type code `code` starts with a length word: `bytes`, `string` and dynamic arrays. -/
def hasCalldataLength (code : UInt8) : Bool :=
  code = TypeCode.BYTES ∨ code = TypeCode.STRING ∨ code = TypeCode.DYNAMIC_ARRAY

/-- The type a comparison's constants take against a target of type code `code`. A length comparison applies to a type
with a calldata length, and it compares as `LENGTH_TYPE`. Any other comparison applies to a word type and compares as
that type. None where the comparison does not apply. -/
def operandType (comparison : Comparison) (code : UInt8) : Option WordType :=
  if comparison.isLength then
    if hasCalldataLength code then some LENGTH_TYPE else none
  else WordType.ofCode? code

/-- The width of a value of the type in bytes. -/
def WordType.width : WordType → Nat
  | .uint width | .int width | .fixedBytes width => width.index.val + 1
  | .address => 20
  | .bool => 1
  | .function => 24

/-- Whether the type's value fills the high bytes of its word. -/
def WordType.leftAligned : WordType → Bool
  | .fixedBytes _ | .function => true
  | _ => false

/-- The bits below a value of the type in its word: 0 unless it is left-aligned. -/
def WordType.shift (wordType : WordType) : Nat :=
  if wordType.leftAligned then 256 - 8 * wordType.width else 0

/-- A word of the type as an operand: the `width` bytes its value occupies. -/
def WordType.narrow (wordType : WordType) (word : Word) : Bytes :=
  beBytes wordType.width (word.toNat / 2 ^ wordType.shift)

/-- The word an operand of the type loads to: placed at its alignment, and sign-extended for `intN`. -/
def WordType.load (wordType : WordType) (bytes : Bytes) : Word :=
  let word := BitVec.ofNat 256 (beNat bytes * 2 ^ wordType.shift)
  match wordType with
  | .int width => Word.signExtendFrom width word
  | _ => word

/-! ## Meta words -/

/-- The meta word of an array. -/
def ArrayMeta.word (array : ArrayMeta) : Nat :=
  (if array.elementDynamic then META_ELEMENT_DYNAMIC else 0) + (if array.dynamicArray then META_DYNAMIC_ARRAY else 0) +
    array.strideWords

/-- The array a meta word describes, its reserved bits ignored. -/
def ArrayMeta.ofWordMasked (word : Nat) : ArrayMeta :=
  ⟨word / META_DYNAMIC_ARRAY % 2 = 1, word / META_ELEMENT_DYNAMIC % 2 = 1, word % META_STRIDE_LIMIT⟩

/-- The array a 16-bit meta word describes. None when a reserved bit is set. -/
def ArrayMeta.ofWord? (word : Nat) : Option ArrayMeta :=
  if word % META_DYNAMIC_ARRAY < META_STRIDE_LIMIT then some (.ofWordMasked word) else none

/-! ## Compiled rules -/

/-- A test's hint as the blob carries it. It contains the hops, the target's offset from the last base, the target's
meta word when it is a dynamic array, and its type code. -/
structure TestHint where
  /-- The hops, in order. -/
  hops : List Hop
  /-- The target's offset from the last base. -/
  targetDelta : Nat
  /-- The target's meta word when it is a dynamic array. -/
  targetMeta : Option ArrayMeta
  /-- The target's type code. -/
  typeCode : UInt8
  deriving Repr, DecidableEq

/-- A loop's hint as the blob carries it. It contains the hops, the array's offset from the last base, its declared
length or 0 for a dynamic array, and its meta word. -/
structure FrameHint where
  /-- The hops, in order. -/
  hops : List Hop
  /-- The array's offset from the last base. -/
  arrayDelta : Nat
  /-- A static array's declared length, or 0 for a dynamic array. -/
  count : Nat
  /-- The array's meta word. -/
  array : ArrayMeta
  deriving Repr, DecidableEq

/-- The test's hint as the blob carries it. -/
def Hint.wire (hint : Hint) : TestHint :=
  ⟨hint.hops, hint.targetDelta,
    match hint.target with
    | .dynamicArray element => some (.of element true)
    | _ => none,
    hint.target.code⟩

/-- The loop's hint as the blob carries it. -/
def LoopHint.frame (hint : LoopHint) : FrameHint :=
  ⟨hint.hops, hint.arrayDelta, hint.count, hint.array⟩

/-- A test or a context test as the blob carries it. -/
inductive CompiledTest where
  /-- A context property, compared. -/
  | contextTest (property : PropertyId) (operator : Operator)
  /-- The value at `path`, reached by `hint`, compared. -/
  | test (path : Path) (hint : TestHint) (operator : Operator)
  deriving Repr, DecidableEq

/-- A rule as the blob carries it. A loop's body contains no loop. -/
inductive CompiledRule where
  /-- A test or a context test. -/
  | test (compiled : CompiledTest)
  /-- The body over each element of the array at `arrayPath`, reached by `hint`. -/
  | loop (quantifier : Quantifier) (arrayPath : Path) (hint : FrameHint) (body : List CompiledTest)
  deriving Repr, DecidableEq

/-- A policy as the blob carries it: its selector, none when selectorless, its descriptor and its groups. -/
structure CompiledPolicy where
  /-- The function selector. None for a policy over raw ABI-encoded arguments. -/
  selector : Option UInt32
  /-- The embedded descriptor. -/
  desc : Bytes
  /-- The root groups. -/
  groups : List (List CompiledRule)
  deriving Repr, DecidableEq

/-- The test without what the blob carries beside it. -/
def CompiledTest.rule : CompiledTest → Rule
  | .contextTest property operator => .contextTest property operator
  | .test path _ operator => .test path operator

/-- The rule without what the blob carries beside it. -/
def CompiledRule.rule : CompiledRule → Rule
  | .test compiled => compiled.rule
  | .loop quantifier arrayPath _ body => .loop quantifier arrayPath (body.map CompiledTest.rule)

/-- The formula the policy's groups state. -/
def CompiledPolicy.formula (policy : CompiledPolicy) : Formula :=
  policy.groups.map (·.map CompiledRule.rule)

/-! ## Writing -/

/-- A hop: `delta (4) | index (2) | meta (2)`. A plain hop carries `HINT_NO_INDEX` and meta 0. An element hop carries a
delta of 0 and its own index. -/
def Hop.write : Hop → Bytes
  | .plain delta => beBytes 4 delta ++ beBytes 2 HINT_NO_INDEX ++ beBytes 2 0
  | .element index array => beBytes 4 0 ++ beBytes 2 index ++ beBytes 2 array.word

/-- A hint header with its `kind` bits zero, then the hops. -/
def writeHops (hops : List Hop) : Bytes :=
  UInt8.ofNat hops.length :: hops.flatMap Hop.write

/-- A test's hint: `header | hops | targetDelta (4) | targetMeta (2) | typeCode (1)`, `targetMeta` 0 unless the target
is a dynamic array. -/
def TestHint.write (hint : TestHint) : Bytes :=
  writeHops hint.hops ++ beBytes 4 hint.targetDelta ++ beBytes 2 ((hint.targetMeta.map ArrayMeta.word).getD 0) ++
    [hint.typeCode]

/-- A loop's hint: `header | hops | arrayDelta (4) | count (2) | meta (2)`. -/
def FrameHint.write (hint : FrameHint) : Bytes :=
  writeHops hint.hops ++ beBytes 4 hint.arrayDelta ++ beBytes 2 hint.count ++ beBytes 2 hint.array.word

/-- A path: `pathDepth (1)`, then each step in 2 bytes. -/
def writePath (path : Path) : Bytes :=
  UInt8.ofNat path.length :: path.flatMap (beBytes 2)

/-- The operator's `opCode`: NOT in bit 7, `source` in bits 6–5, `comparison` in bits 4–0. -/
def Operator.opCode (operator : Operator) : UInt8 :=
  UInt8.ofNat (operator.negated.toNat * NOT_FLAG + operator.operand.source * 2 ^ SOURCE_SHIFT +
    operator.comparison.code.toNat)

/-- The operator's data against a target of type code `code`. Each constant is as wide as its operand type, and a
context property contributes its 2-byte ID. -/
def Operator.data (operator : Operator) (code : UInt8) : Bytes :=
  match operator.operand, operandType operator.comparison code with
  | .constant values, some wordType => values.flatMap wordType.narrow
  | .constant _, none => []
  | .context property, _ => beBytes 2 property

/-- An operator against a target of type code `code`: `opCode (1) | dataLength (2) | data`. -/
def Operator.write (operator : Operator) (code : UInt8) : Bytes :=
  operator.opCode :: beBytes 2 (operator.data code).length ++ operator.data code

/-- The test's `scope`. -/
def CompiledTest.scope : CompiledTest → UInt8
  | .contextTest .. => SCOPE_CONTEXT
  | .test .. => SCOPE_CALLDATA

/-- The test's payload: `pathDepth = 1 | propertyId (2) | operator` for a context test, `pathDepth | path | hint |
operator` for a calldata test. -/
def CompiledTest.payload : CompiledTest → Bytes
  | .contextTest property operator => 1 :: beBytes 2 property ++ operator.write (contextPropertyType property).code
  | .test path hint operator => writePath path ++ hint.write ++ operator.write hint.typeCode

/-- A test's bytes after `ruleSize`: its `scope`, then its payload. -/
def CompiledTest.sizeFree (test : CompiledTest) : Bytes :=
  test.scope :: test.payload

/-- A rule framed by its `ruleSize`, which counts itself. -/
def frameRule (content : Bytes) : Bytes :=
  beBytes 2 (content.length + Policy.RULE_SIZE_SIZE) ++ content

/-- A test: `ruleSize (2)`, then its size-free bytes. -/
def CompiledTest.write (test : CompiledTest) : Bytes :=
  frameRule test.sizeFree

/-- A rule's bytes after `ruleSize`, its body tests written by `writeTest`: a test's size-free bytes, or for a loop
`scope | quantifier | pathDepth | arrayPath | hint | ruleCount (2) | rules`. -/
def CompiledRule.content (writeTest : CompiledTest → Bytes) : CompiledRule → Bytes
  | .test compiled => compiled.sizeFree
  | .loop quantifier arrayPath hint body =>
    SCOPE_LOOP :: quantifier.code :: writePath arrayPath ++ hint.write ++ beBytes 2 body.length ++
      body.flatMap writeTest

/-- A rule: `ruleSize (2)`, then its content with each body test framed. -/
def CompiledRule.write (rule : CompiledRule) : Bytes :=
  frameRule (rule.content CompiledTest.write)

/-- The bytes the canonical order compares: the rule's bytes with every `ruleSize` removed, nested ones included. -/
def CompiledRule.sizeFree (rule : CompiledRule) : Bytes :=
  rule.content CompiledTest.sizeFree

/-- A root group: `ruleCount (2) | groupSize (4) | rules`. -/
def writeGroup (rules : List CompiledRule) : Bytes :=
  let ruleBytes := rules.flatMap CompiledRule.write
  beBytes 2 rules.length ++ beBytes 4 ruleBytes.length ++ ruleBytes

/-- The header byte: `MAJOR`, `MINOR`, and `FLAG_NO_SELECTOR` when the policy is selectorless. -/
def Policy.header (selectorless : Bool) : UInt8 :=
  UInt8.ofNat (MAJOR * 2 ^ MAJOR_SHIFT + MINOR * 2 ^ MINOR_SHIFT + if selectorless then FLAG_NO_SELECTOR else 0)

/-- The blob: `header | selector (SELECTOR_SIZE) | descLength (2) | desc | groupCount (1) | groups`. The selector slot
is zero when selectorless. -/
def CompiledPolicy.write (policy : CompiledPolicy) : Bytes :=
  Policy.header policy.selector.isNone :: beBytes Policy.SELECTOR_SIZE ((policy.selector.map UInt32.toNat).getD 0) ++
    beBytes 2 policy.desc.length ++ policy.desc ++ UInt8.ofNat policy.groups.length :: policy.groups.flatMap writeGroup

end Callcium

import Callcium.Wire.Format
import Callcium.Descriptor.Validate

/-!
# Wire validation

`Policy.parse` reads a blob into a `CompiledPolicy` and checks every storage-time invariant (PWF) on the way. It checks
the header's `major` and `minor`, and a zero selector slot when the blob is selectorless. It checks that the descriptor
is well-formed, and that framing and sizes fill exactly at every level. It checks known `scope`, `quantifier`, `source`
and `comparison` values, and hint headers and hops without reserved state. It checks the operand data length that the
operand type's width determines. It checks an ascending `IN` set, and that context sources appear only on `EQ`, `GT`,
`LT`, `GTE` and `LTE`. It checks that context property IDs are defined, and that a comparison family matches the target
type. It checks that no reserved path-step marker appears, and that path depth stays within `MAX_PATH_DEPTH` across the
loop. It checks a nonempty root path, and a nonempty body without loops. `Policy.validate` is whether it succeeds. Hint
recompilation and the canonical order are build-time and builder concerns, outside it.
-/

namespace Callcium

/-! ## Readers -/

/-- A reader of a byte string's prefix: the value read and the bytes after it, or none. -/
abbrev Reader := StateT Bytes Option

namespace Reader

/-- One byte. -/
def byte : Reader UInt8 := fun bytes =>
  match bytes with
  | first :: rest => some (first, rest)
  | [] => none

/-- The next `count` bytes. -/
def take (count : Nat) : Reader Bytes := fun bytes =>
  if count ≤ bytes.length then some (bytes.take count, bytes.drop count) else none

/-- A big-endian field of `size` bytes. -/
def field (size : Nat) : Reader Nat :=
  beNat <$> take size

/-- Fails unless `condition` holds. -/
def require (condition : Bool) : Reader Unit :=
  if condition then pure () else failure

/-- The value of an option. It fails on `none`. -/
def some? {Item : Type} (option : Option Item) : Reader Item :=
  match option with
  | some item => pure item
  | none => failure

/-- `count` values, one after another. -/
def many {Item : Type} (reader : Reader Item) : Nat → Reader (List Item)
  | 0 => pure []
  | count + 1 => do
    let item ← reader
    let items ← many reader count
    pure (item :: items)

/-- Runs `reader` over the next `size` bytes, which it must consume exactly. -/
def framed {Item : Type} (size : Nat) (reader : Reader Item) : Reader Item := do
  let region ← take size
  match reader region with
  | some (item, []) => pure item
  | _ => failure

end Reader

open Reader

/-! ## Hints -/

/-- A hop. A plain hop carries meta 0. An element hop carries delta 0, a fixed index below `PATH_MARKER_BASE` and a meta
word without reserved bits. Indices from `PATH_MARKER_BASE` up to `HINT_NO_INDEX` are reserved. -/
def Hop.read : Reader Hop := do
  let delta ← field 4
  let index ← field 2
  let metaWord ← field 2
  if index = HINT_NO_INDEX then
    require (metaWord = 0)
    pure (.plain delta)
  else
    require (index < PATH_MARKER_BASE && delta = 0)
    let array ← some? (ArrayMeta.ofWord? metaWord)
    pure (.element index array)

/-- A hint header with its `kind` bits zero, then its hops. -/
def readHops : Reader (List Hop) := do
  let header ← byte
  require (header.toNat ≤ MAX_HOP_COUNT)
  many Hop.read header.toNat

/-- A test's hint. `targetMeta` describes a dynamic array and is zero for every other type code. -/
def TestHint.read : Reader TestHint := do
  let hops ← readHops
  let targetDelta ← field 4
  let metaWord ← field 2
  let typeCode ← byte
  if typeCode = TypeCode.DYNAMIC_ARRAY then
    let array ← some? (ArrayMeta.ofWord? metaWord)
    pure ⟨hops, targetDelta, some array, typeCode⟩
  else
    require (metaWord = 0)
    pure ⟨hops, targetDelta, none, typeCode⟩

/-- A loop's hint. -/
def FrameHint.read : Reader FrameHint := do
  let hops ← readHops
  let arrayDelta ← field 4
  let count ← field 2
  let array ← some? (ArrayMeta.ofWord? (← field 2))
  pure ⟨hops, arrayDelta, count, array⟩

/-! ## Rules -/

/-- A path whose steps are all indices: the marker range is reserved. -/
def readPath : Reader Path := do
  let depth ← byte
  let path ← many (field 2) depth.toNat
  require (Path.indicesOnly path)
  pure path

/-- An operator against a target of type code `code`. Its comparison applies to the type (`operandType`). Constants
fill `dataLength` at the operand type's width, as many as the comparison takes, and an `IN` set ascends strictly as
loaded words compared unsigned. A context source applies to `EQ`, `GT`, `LT`, `GTE` and `LTE` only, and it
names a defined property. -/
def Operator.read (code : UInt8) : Reader Operator := do
  let opCode := (← byte).toNat
  let negated := decide (opCode / NOT_FLAG = 1)
  let source := opCode % NOT_FLAG / 2 ^ SOURCE_SHIFT
  let comparison ← some? (Comparison.ofCode? (opCode % 2 ^ SOURCE_SHIFT))
  let wordType ← some? (operandType comparison code)
  let dataLength ← field 2
  if source = SOURCE_CONSTANT then
    let count := dataLength / wordType.width
    require (dataLength = count * wordType.width && (comparison.arity.map (· == count)).getD (decide (0 < count)))
    let values := (← many (take wordType.width) count).map wordType.load
    require (comparison != .in_ || (values.zip values.tail).all fun (lower, upper) => lower.ult upper)
    pure ⟨negated, comparison, .constant values⟩
  else if source = SOURCE_CONTEXT then
    require (comparison.swap?.isSome && dataLength = 2)
    let property ← field 2
    require (property ≤ CTX_MAX)
    pure ⟨negated, comparison, .context property⟩
  else failure

/-- A test or a context test after its `scope` byte, `outerDepth` path steps below the arguments. At the root, a calldata
test's path is nonempty. A context test's path is one step, its property ID. -/
def CompiledTest.readScoped (root : Bool) (outerDepth : Nat) (scope : UInt8) : Reader CompiledTest := do
  if scope = SCOPE_CONTEXT then
    require ((← byte) = 1)
    let property ← field 2
    require (property ≤ CTX_MAX)
    let operator ← Operator.read (contextPropertyType property).code
    pure (.contextTest property operator)
  else if scope = SCOPE_CALLDATA then
    let path ← readPath
    require ((!root || !path.isEmpty) && outerDepth + path.length ≤ MAX_PATH_DEPTH)
    let hint ← TestHint.read
    let operator ← Operator.read hint.typeCode
    pure (.test path hint operator)
  else failure

/-- A rule's content, its size given by `ruleSize`, which counts itself. -/
def readFramed {Item : Type} (reader : Reader Item) : Reader Item := do
  let ruleSize ← field 2
  framed (ruleSize - Policy.RULE_SIZE_SIZE) reader

/-- A body test, `outerDepth` path steps below the arguments. A loop in a body is rejected. -/
def CompiledTest.read (outerDepth : Nat) : Reader CompiledTest :=
  readFramed do CompiledTest.readScoped false outerDepth (← byte)

/-- A root rule. A loop's array path is nonempty and its body one or more tests that fill the rule. -/
def CompiledRule.read : Reader CompiledRule := readFramed do
  let scope ← byte
  if scope = SCOPE_LOOP then
    let quantifier ← some? (Quantifier.ofCode? (← byte))
    let arrayPath ← readPath
    require (!arrayPath.isEmpty && arrayPath.length ≤ MAX_PATH_DEPTH)
    let hint ← FrameHint.read
    let ruleCount ← field 2
    require (0 < ruleCount)
    let body ← many (CompiledTest.read arrayPath.length) ruleCount
    pure (.loop quantifier arrayPath hint body)
  else .test <$> CompiledTest.readScoped true 0 scope

/-- A root group: one or more rules that fill `groupSize`. -/
def readGroup : Reader (List CompiledRule) := do
  let ruleCount ← field 2
  let groupSize ← field 4
  require (0 < ruleCount)
  framed groupSize (many CompiledRule.read ruleCount)

/-! ## Policies -/

/-- The policy a blob carries. The header's `major` is `MAJOR` and its `minor` is `MINOR`. A selectorless blob's
selector slot is zero. The descriptor is well-formed (PWF-7), and one or more groups fill the rest. -/
def Policy.read : Reader CompiledPolicy := do
  let header := (← byte).toNat
  require (header >>> MAJOR_SHIFT = MAJOR && (header >>> MINOR_SHIFT) &&& MINOR_MASK = MINOR)
  let selectorless := header &&& FLAG_NO_SELECTOR = FLAG_NO_SELECTOR
  let selector ← field SELECTOR_SIZE
  require (!selectorless || selector = 0)
  let desc ← take (← field 2)
  require (Descriptor.wellFormed desc)
  let groupCount := (← byte).toNat
  require (0 < groupCount)
  let groups ← many readGroup groupCount
  pure ⟨if selectorless then none else some (UInt32.ofNat selector), desc, groups⟩

/-- The policy the blob carries, read to its last byte, or none unless the blob passes storage validation. -/
def Policy.parse (blob : Bytes) : Option CompiledPolicy :=
  match Policy.read blob with
  | some (policy, []) => some policy
  | _ => none

/-- Whether the blob passes storage validation. -/
def Policy.validate (blob : Bytes) : Bool :=
  (Policy.parse blob).isSome

end Callcium

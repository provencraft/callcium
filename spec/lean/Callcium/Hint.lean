import Callcium.Abi.DecodeSolc

/-!
# Hints

A hint addresses a value in calldata without the descriptor. It is a chain of hops, each crossing one dynamic boundary,
then a fixed delta. `AbiType.compile?` compiles a path within a type into a test's hint, and `AbiType.compileLoop?` an
array path into a loop's hint. `Hint.resolve`, `LoopHint.resolveArray` and `LoopHint.resolveElement` follow them through
calldata from where the starting point's encoding starts. Positions add modulo 2^256, as the enforcer's unchecked
arithmetic does. A word read must lie within the calldata. An offset word must not carry its base past the end.
-/

namespace Callcium

/-! ## Hints -/

/-- An array node as a hop or a loop reads it: the hint's meta word. -/
structure ArrayMeta where
  /-- Whether the array is dynamic, its elements after a length word. -/
  dynamicArray : Bool
  /-- Whether the elements are dynamic, each behind an offset word. -/
  elementDynamic : Bool
  /-- An element's head size in words. -/
  strideWords : Nat
  deriving Repr, DecidableEq

/-- The meta word of an array of `element`. -/
def ArrayMeta.of (element : AbiType) (dynamicArray : Bool) : ArrayMeta :=
  ⟨dynamicArray, element.isDynamic, if element.isDynamic then 1 else element.staticWords⟩

/-- One dynamic boundary a chain crosses. -/
inductive Hop where
  /-- Enters the node whose offset word lies `delta` bytes past the base. -/
  | plain (delta : Nat)
  /-- Moves to element `index` of the array whose encoding starts at the base. -/
  | element (index : Nat) (array : ArrayMeta)
  deriving Repr, DecidableEq

/-- A test's hint: the hops from the starting point, then the target `targetDelta` bytes past the last base. -/
structure Hint where
  /-- The hops, in order. -/
  hops : List Hop
  /-- The target's offset from the last base. -/
  targetDelta : Nat
  /-- The target's type. -/
  target : AbiType
  deriving Repr

/-- A loop's hint: the hops from the starting point, then the array `arrayDelta` bytes past the last base. -/
structure LoopHint where
  /-- The hops, in order. -/
  hops : List Hop
  /-- The array's offset from the last base. -/
  arrayDelta : Nat
  /-- A static array's declared length, or 0 for a dynamic array. -/
  count : Nat
  /-- The array's meta word. -/
  array : ArrayMeta
  /-- The element type, which the body's paths start from. -/
  element : AbiType
  deriving Repr

/-! ## Compilation -/

/-- The hop entering the node whose offset word lies `delta` past the base when `needed`, and the delta after it. -/
def enter (needed : Bool) (delta : Nat) : List Hop × Nat :=
  if needed then ([.plain delta], 0) else ([], delta)

/-- Walks `path` within a value of the type. It yields the hops it emits, the delta past their last base, whether the
chain ends inside the node reached, and that node's type. `delta` and `entered` describe the type's own node on arrival.
When `entered` is true, its encoding starts at the base. Otherwise its head lies `delta` past the base. None when a step
leaves the type or passes a static array's length. -/
def AbiType.walk : AbiType → Path → Nat → Bool → Option (List Hop × Nat × Bool × AbiType)
  | abiType, [], delta, entered => some ([], delta, entered, abiType)
  | abiType@(.tuple fields), step :: steps, delta, entered =>
    match fields[step]? with
    | some field =>
      let (entry, delta) := enter (abiType.isDynamic && !entered) delta
      (field.walk steps (delta + ((fields.take step).map headSize).sum) false).map
        fun (hops, rest) => (entry ++ hops, rest)
    | none => none
  | abiType@(.staticArray element length), step :: steps, delta, entered =>
    if step < length then
      if abiType.isDynamic then
        let (entry, _) := enter (!entered) delta
        (element.walk steps 0 element.isDynamic).map
          fun (hops, rest) => (entry ++ .element step (.of element false) :: hops, rest)
      else element.walk steps (delta + step * element.headSize) false
    else none
  | .dynamicArray element, step :: steps, delta, entered =>
    let (entry, _) := enter (!entered) delta
    (element.walk steps 0 element.isDynamic).map
      fun (hops, rest) => (entry ++ .element step (.of element true) :: hops, rest)
  | _, _ :: _, _, _ => none

/-- The hint of a test at `path` within a value of the type. A dynamic target is entered, so the hint ends at the start
of the target's encoding. -/
def AbiType.compile? (abiType : AbiType) (path : Path) : Option Hint :=
  (abiType.walk path 0 true).map fun (hops, delta, entered, target) =>
    let (entry, delta) := enter (target.isDynamic && !entered) delta
    ⟨hops ++ entry, delta, target⟩

/-- The hint of a loop over the array at `arrayPath` within a value of the type. The result is none unless the path
reaches an array. A static array's `count` is its declared length. A `count` of 0 states a dynamic array. So a static
array of no elements has no hint. -/
def AbiType.compileLoop? (abiType : AbiType) (arrayPath : Path) : Option LoopHint :=
  match abiType.walk arrayPath 0 true with
  | some (hops, delta, entered, array@(.staticArray element length)) =>
    if 0 < length then
      let (entry, delta) := enter (array.isDynamic && !entered) delta
      some ⟨hops ++ entry, delta, length, .of element false, element⟩
    else none
  | some (hops, delta, entered, .dynamicArray element) =>
    let (entry, delta) := enter (!entered) delta
    some ⟨hops ++ entry, delta, 0, .of element true, element⟩
  | _ => none

/-! ## Resolution -/

/-- Why resolution stops. -/
inductive Fault where
  /-- A word read, or an offset, past the end of the calldata (`CALLDATA_OUT_OF_BOUNDS`). -/
  | calldataOutOfBounds
  /-- A fixed index at or past a dynamic array's length (`ARRAY_INDEX_OUT_OF_BOUNDS`). -/
  | arrayIndexOutOfBounds
  deriving Repr, DecidableEq

/-- The word at `position`, or a fault when it does not lie within `data`. -/
def loadWord (data : Bytes) (position : Nat) : Except Fault Word :=
  if position + WORD_SIZE ≤ data.length then .ok (readWord data position) else .error .calldataOutOfBounds

/-- `base` advanced by the offset word at `head`. A fault when that passes the end of `data`. -/
def follow (data : Bytes) (base head : Nat) : Except Fault Nat := do
  let offset := (← loadWord data head).toNat
  if base + offset ≤ data.length then pure (advance base offset) else throw .calldataOutOfBounds

/-- Where element `index` of the array starts, its elements starting at `elements`. Its head lies `index` strides past
`elements`. For a dynamic element, the element starts where the offset word in that head points. -/
def ArrayMeta.elementAt (array : ArrayMeta) (data : Bytes) (elements index : Nat) : Except Fault Nat :=
  let slot := advance elements (index * (WORD_SIZE * array.strideWords))
  if array.elementDynamic then follow data elements slot else pure slot

/-- The base after the hop from `base`. An element hop on a dynamic array checks the index against its length. -/
def Hop.apply (data : Bytes) (base : Nat) : Hop → Except Fault Nat
  | .plain delta => follow data base (advance base delta)
  | .element index array =>
    if array.dynamicArray then do
      let length := (← loadWord data base).toNat
      if index < length then array.elementAt data (advance base WORD_SIZE) index
      else throw .arrayIndexOutOfBounds
    else array.elementAt data base index

/-- The base after the hops from `start`. -/
def resolveHops (data : Bytes) (hops : List Hop) (start : Nat) : Except Fault Nat :=
  hops.foldlM (Hop.apply data) start

/-- Where the test's target starts, from a starting point whose encoding starts at `start`. -/
def Hint.resolve (hint : Hint) (data : Bytes) (start : Nat) : Except Fault Nat :=
  (resolveHops data hint.hops start).map (advance · hint.targetDelta)

/-- Where the loop's elements start and how many there are, from a starting point whose encoding starts at `start`. A
dynamic array's length precedes its elements. -/
def LoopHint.resolveArray (hint : LoopHint) (data : Bytes) (start : Nat) : Except Fault (Nat × Nat) := do
  let array := advance (← resolveHops data hint.hops start) hint.arrayDelta
  if hint.count = 0 then
    let count := (← loadWord data array).toNat
    pure (advance array WORD_SIZE, count)
  else pure (array, hint.count)

/-- Where element `position` of the loop's array starts, its elements starting at `elements`. -/
def LoopHint.resolveElement (hint : LoopHint) (data : Bytes) (elements position : Nat) : Except Fault Nat :=
  hint.array.elementAt data elements position

end Callcium

import Callcium.Abi.Value

/-!
# ABI encoder

`AbiType.encode` writes a value of a type in the canonical ABI encoding. The encoding of a word type is one word. The
encoding of `bytes` and `string` is a length word and the bytes zero-padded to whole words. The encoding of a tuple or
an array is its components' heads followed by their tails. A static component's head is its encoding. A dynamic
component's head is the offset of its encoding, placed among the tails, from the start of the heads. A dynamic array
starts with its length.
-/

namespace Callcium

/-- The number of zero bytes that pad `length` bytes to whole words. -/
def paddingLength (length : Nat) : Nat := (WORD_SIZE - length % WORD_SIZE) % WORD_SIZE

/-- The head length of a component given as whether it is dynamic and its encoding. -/
def headLength : Bool × Bytes → Nat
  | (dynamic, encoding) => if dynamic then WORD_SIZE else encoding.length

/-- The heads and the tails of the components, the first tail at `tailOffset` from the start of the heads. -/
def headsAndTails : List (Bool × Bytes) → Nat → Bytes × Bytes
  | [], _ => ([], [])
  | (dynamic, encoding) :: components, tailOffset =>
    if dynamic then
      let parts := headsAndTails components (tailOffset + encoding.length)
      (beBytes WORD_SIZE tailOffset ++ parts.1, encoding ++ parts.2)
    else
      let parts := headsAndTails components tailOffset
      (encoding ++ parts.1, parts.2)

/-- The components' heads followed by their tails. -/
def joinComponents (components : List (Bool × Bytes)) : Bytes :=
  let parts := headsAndTails components (components.map headLength).sum
  parts.1 ++ parts.2

mutual
  /-- The encoding of `value` as a value of the type. -/
  def AbiType.encode : AbiType → Value → Bytes
    | .word _, .word bits _ => beBytes WORD_SIZE bits.toNat
    | .bytes, .bytes data | .string, .bytes data =>
      beBytes WORD_SIZE data.length ++ data ++ List.replicate (paddingLength data.length) 0
    | .staticArray element length, .list items =>
      joinComponents (AbiType.encodeComponents (List.replicate length element) items)
    | .dynamicArray element, .list items =>
      beBytes WORD_SIZE items.length ++
        joinComponents (AbiType.encodeComponents (List.replicate items.length element) items)
    | .tuple fields, .list items => joinComponents (AbiType.encodeComponents fields items)
    | _, _ => []

  /-- Each value paired with its type: whether the type is dynamic, and the value's encoding. -/
  def AbiType.encodeComponents : List AbiType → List Value → List (Bool × Bytes)
    | abiType :: types, value :: values =>
      (abiType.isDynamic, abiType.encode value) :: AbiType.encodeComponents types values
    | _, _ => []
end

end Callcium

import Callcium.Abi.Type

/-!
# ABI values

Decoded values, with types erased except for the signedness comparisons need, and paths into them.
`AbiType.admits` decides whether a value is a value of a type.
-/

namespace Callcium

/-- A sequence of field and element indices. -/
abbrev Path := List Nat

/-- A decoded value, with types erased except for the signedness comparisons need. -/
inductive Value where
  /-- A static elementary value as its 32-byte word. `signed` orders it as two's complement. -/
  | word (bits : Word) (signed : Bool)
  /-- A `bytes` or `string` value. -/
  | bytes (data : List UInt8)
  /-- A tuple or an array: its fields or elements in order. -/
  | list (items : List Value)
  deriving Repr, BEq

/-- The value at `path`, or `none` when a step leaves the value. -/
def Value.at : Value → Path → Option Value
  | value, [] => some value
  | .list items, step :: steps => items[step]?.bind (·.at steps)
  | _, _ :: _ => none

/-- The element count of an array or tuple, or the byte length of `bytes` and `string`. -/
def Value.length? : Value → Option Nat
  | .word _ _ => none
  | .bytes data => some data.length
  | .list items => some items.length


/-- Whether the type orders its values as two's complement. -/
def WordType.signed : WordType → Bool
  | .int _ => true
  | _ => false

mutual
  /-- Whether `value` is a value of the type: words canonical and of the type's signedness, components one for one, and
  every length below 2^256. -/
  def AbiType.admits : AbiType → Value → Bool
    | .word wordType, .word bits signed => wordType.isCanonical bits && signed == wordType.signed
    | .bytes, .bytes data | .string, .bytes data => data.length < 2 ^ 256
    | .staticArray element length, .list items => AbiType.admitsAll (List.replicate length element) items
    | .dynamicArray element, .list items =>
      items.length < 2 ^ 256 && AbiType.admitsAll (List.replicate items.length element) items
    | .tuple fields, .list items => AbiType.admitsAll fields items
    | _, _ => false

  /-- Whether the values are, one for one, values of the types. -/
  def AbiType.admitsAll : List AbiType → List Value → Bool
    | [], [] => true
    | abiType :: types, value :: values => abiType.admits value && AbiType.admitsAll types values
    | _, _ => false
end

end Callcium

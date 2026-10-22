import Callcium.Word

/-!
# ABI types

The ABI type language: word types, `bytes`, `string`, static and dynamic arrays, and tuples. `AbiType.staticWords` is
a type's head size in words when it is static, 0 when it is dynamic; `AbiType.headSize` is its head size in bytes.
-/

namespace Callcium

/-- An ABI type. -/
inductive AbiType where
  /-- A static elementary type. -/
  | word (wordType : WordType)
  /-- `bytes`. -/
  | bytes
  /-- `string`. -/
  | string
  /-- `T[length]`. -/
  | staticArray (element : AbiType) (length : Nat)
  /-- `T[]`. -/
  | dynamicArray (element : AbiType)
  /-- `(T₁, …, Tₙ)`. -/
  | tuple (fields : List AbiType)
  deriving Repr, BEq

/-- Induction over types, with a hypothesis for every field of a tuple. -/
@[induction_eliminator]
theorem AbiType.induction {motive : AbiType → Prop}
    (word : ∀ wordType, motive (.word wordType))
    (bytes : motive .bytes)
    (string : motive .string)
    (staticArray : ∀ element length, motive element → motive (.staticArray element length))
    (dynamicArray : ∀ element, motive element → motive (.dynamicArray element))
    (tuple : ∀ fields, (∀ field ∈ fields, motive field) → motive (.tuple fields)) :
    ∀ abiType, motive abiType
  | .word wordType => word wordType
  | .bytes => bytes
  | .string => string
  | .staticArray element length =>
    staticArray element length (AbiType.induction word bytes string staticArray dynamicArray tuple element)
  | .dynamicArray element =>
    dynamicArray element (AbiType.induction word bytes string staticArray dynamicArray tuple element)
  | .tuple fields => tuple fields fun field _fieldIsMember =>
      AbiType.induction word bytes string staticArray dynamicArray tuple field
termination_by abiType => sizeOf abiType
decreasing_by
  all_goals simp_wf
  all_goals try omega
  have := List.sizeOf_lt_of_mem _fieldIsMember
  omega

mutual
  /-- Whether the type is dynamic: `bytes`, `string`, a dynamic array, or a static array or tuple holding a dynamic
  type. -/
  def AbiType.isDynamic : AbiType → Bool
    | .word _ => false
    | .bytes | .string | .dynamicArray _ => true
    | .staticArray element _ => element.isDynamic
    | .tuple fields => AbiType.anyDynamic fields

  /-- Whether some type is dynamic. -/
  def AbiType.anyDynamic : List AbiType → Bool
    | [] => false
    | field :: fields => field.isDynamic || AbiType.anyDynamic fields
end

mutual
  /-- The type's head size in words when it is static, 0 when it is dynamic. -/
  def AbiType.staticWords : AbiType → Nat
    | .word _ => 1
    | .bytes | .string | .dynamicArray _ => 0
    | .staticArray element length => if element.isDynamic then 0 else length * element.staticWords
    | .tuple fields => if AbiType.anyDynamic fields then 0 else AbiType.sumStaticWords fields

  /-- The head sizes summed. -/
  def AbiType.sumStaticWords : List AbiType → Nat
    | [] => 0
    | field :: fields => field.staticWords + AbiType.sumStaticWords fields
end

/-- The type's head size in bytes: one word when it is dynamic, `staticWords` words when it is static. -/
def AbiType.headSize (abiType : AbiType) : Nat :=
  if abiType.isDynamic then WORD_SIZE else WORD_SIZE * abiType.staticWords

end Callcium

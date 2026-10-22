import Callcium.Abi.Value

/-!
# Solidity's ABI decoder

`AbiType.decodeSolc` models Solidity 0.8.30's ABI decoder, eager into `memory` and lazy from `calldata`: positions add
modulo 2^256, words and bytes past the end of the data read as zero, a dynamic component starts at its base plus the
offset in its head, and a word reads as it is. It is total, so it accepts every input Solidity accepts; that it returns
the values Solidity reads wherever Solidity accepts is the trusted assumption the F1 differential checks. Where
Solidity's two `calldata` reads differ, element access adding word positions modulo 2^256 and a `calldatacopy` of a
static block not wrapping, `decodeSolc` follows element access.
-/

namespace Callcium

/-- `count` bytes of `data` from `position`, zero past its end. -/
def readBytes (data : Bytes) (position count : Nat) : Bytes :=
  (data.drop position).take count ++ List.replicate (count - (data.length - position)) 0

/-- The word at `position`, zero past the end of `data`. -/
def readWord (data : Bytes) (position : Nat) : Word :=
  BitVec.ofNat 256 (beNat (readBytes data position WORD_SIZE))

/-- `position + offset` modulo 2^256. -/
def advance (position offset : Nat) : Nat := (position + offset) % 2 ^ 256

/-- Where the encoding of a component whose head is at `head` starts: at `head` when the type is static; when it is
dynamic, at `base` plus the offset the head holds. -/
def AbiType.componentStart (abiType : AbiType) (data : Bytes) (base head : Nat) : Nat :=
  if abiType.isDynamic then advance base (readWord data head).toNat else head

/-- `count` elements whose heads follow one another from `head`, dynamic ones placed from `base`, each read by
`decodeElement` from where it starts. -/
def decodeElements (decodeElement : Nat → Value) (element : AbiType) (data : Bytes) (base : Nat) :
    Nat → Nat → List Value
  | _, 0 => []
  | head, count + 1 =>
    decodeElement (element.componentStart data base head) ::
      decodeElements decodeElement element data base (advance head element.headSize) count

mutual
  /-- The value of the type whose encoding starts at `start`. -/
  def AbiType.decodeSolc : AbiType → Bytes → Nat → Value
    | .word wordType, data, start => .word (readWord data start) wordType.signed
    | .bytes, data, start | .string, data, start =>
      .bytes (readBytes data (advance start WORD_SIZE) (readWord data start).toNat)
    | .staticArray element length, data, start =>
      .list (decodeElements (element.decodeSolc data) element data start start length)
    | .dynamicArray element, data, start =>
      let base := advance start WORD_SIZE
      .list (decodeElements (element.decodeSolc data) element data base base (readWord data start).toNat)
    | .tuple fields, data, start => .list (AbiType.decodeFields fields data start start)

  /-- The values of the fields whose heads follow one another from `head`, dynamic ones placed from `base`. -/
  def AbiType.decodeFields : List AbiType → Bytes → Nat → Nat → List Value
    | [], _, _, _ => []
    | field :: fields, data, base, head =>
      field.decodeSolc data (field.componentStart data base head) ::
        AbiType.decodeFields fields data base (advance head field.headSize)
end

/-- The type at `path` within a value of the type whose encoding starts at `start`, and where its encoding starts; none
when a step leaves the type or passes an array's length. -/
def AbiType.locate : AbiType → Bytes → Nat → Path → Option (AbiType × Nat)
  | abiType, _, start, [] => some (abiType, start)
  | .staticArray element length, data, start, step :: steps =>
    if step < length then
      element.locate data (element.componentStart data start (advance start (step * element.headSize))) steps
    else none
  | .dynamicArray element, data, start, step :: steps =>
    let base := advance start WORD_SIZE
    if step < (readWord data start).toNat then
      element.locate data (element.componentStart data base (advance base (step * element.headSize))) steps
    else none
  | .tuple fields, data, start, step :: steps =>
    match fields[step]? with
    | some field =>
      field.locate data (field.componentStart data start (advance start ((fields.take step).map headSize).sum)) steps
    | none => none
  | _, _, _, _ :: _ => none

end Callcium

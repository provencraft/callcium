import Callcium.Descriptor.Format

/-!
# Descriptor codec

`Descriptor.encode` writes a type list as a descriptor. `Descriptor.decode` reads one back by walking each node's
children, and rejects a composite node whose metadata disagrees with what the walk finds: a `nodeLength` other than
its span (DV-1) or a `staticWords` other than its type's (DV-2).
-/

namespace Callcium

open Descriptor

/-! ## Encoding -/

/-- The code and metadata opening a composite node. -/
def AbiType.compositeHeader (code : UInt8) (abiType : AbiType) : Bytes :=
  code :: compositeMeta abiType.staticWords abiType.nodeLength

mutual
  /-- The type's node. -/
  def AbiType.encodeNode : AbiType → Bytes
    | .word wordType => [wordType.code]
    | .bytes => [TypeCode.BYTES]
    | .string => [TypeCode.STRING]
    | abiType@(.staticArray element length) =>
      abiType.compositeHeader TypeCode.STATIC_ARRAY ++ element.encodeNode ++ be16 length
    | abiType@(.dynamicArray element) => abiType.compositeHeader TypeCode.DYNAMIC_ARRAY ++ element.encodeNode
    | abiType@(.tuple fields) =>
      abiType.compositeHeader TypeCode.TUPLE ++ be16 fields.length ++ AbiType.encodeNodes fields

  /-- The types' nodes, back to back. -/
  def AbiType.encodeNodes : List AbiType → Bytes
    | [] => []
    | field :: fields => field.encodeNode ++ AbiType.encodeNodes fields
end

/-- The descriptor of a parameter list. -/
def Descriptor.encode (types : List AbiType) : Bytes :=
  VERSION :: UInt8.ofNat types.length :: AbiType.encodeNodes types

/-! ## Decoding -/

/-- A decoded composite node, kept when its metadata bytes hold its type's `staticWords` and its span. -/
def Descriptor.checkMeta (abiType : AbiType) (span : Nat) (high middle low : UInt8) : Option (AbiType × Nat) :=
  if metaFields high middle low = (abiType.staticWords, span) then some (abiType, span) else none

mutual
  /-- The type of the node opening `bytes` and the node's span, walking its children; none for an unknown code, a
  node cut short, or metadata that disagrees with the walk. -/
  def Descriptor.decodeNode : Bytes → Option (AbiType × Nat)
    | [] => none
    | code :: rest =>
      match WordType.ofCode? code with
      | some wordType => some (.word wordType, 1)
      | none =>
        if code = TypeCode.BYTES then some (.bytes, 1)
        else if code = TypeCode.STRING then some (.string, 1)
        else
          match rest with
          | high :: middle :: low :: body =>
            if code = TypeCode.TUPLE then
              match body with
              | countHigh :: countLow :: fieldBytes =>
                match decodeNodes (readBe16 countHigh countLow) fieldBytes with
                | some (fields, fieldsSpan) =>
                  checkMeta (.tuple fields) (TUPLE_HEADER_SIZE + fieldsSpan) high middle low
                | none => none
              | _ => none
            else if code = TypeCode.STATIC_ARRAY then
              match decodeNode body with
              | some (element, elementSpan) =>
                match body.drop elementSpan with
                | lengthHigh :: lengthLow :: _ =>
                  checkMeta (.staticArray element (readBe16 lengthHigh lengthLow))
                    (ARRAY_HEADER_SIZE + elementSpan + ARRAY_LENGTH_SIZE) high middle low
                | _ => none
              | none => none
            else if code = TypeCode.DYNAMIC_ARRAY then
              match decodeNode body with
              | some (element, elementSpan) =>
                checkMeta (.dynamicArray element) (ARRAY_HEADER_SIZE + elementSpan) high middle low
              | none => none
            else none
          | _ => none
  termination_by bytes => (bytes.length, 0)

  /-- The types of `count` consecutive nodes and their total span. -/
  def Descriptor.decodeNodes : Nat → Bytes → Option (List AbiType × Nat)
    | 0, _ => some ([], 0)
    | count + 1, bytes =>
      match decodeNode bytes with
      | some (abiType, span) =>
        match decodeNodes count (bytes.drop span) with
        | some (types, restSpan) => some (abiType :: types, span + restSpan)
        | none => none
      | none => none
  termination_by count bytes => (bytes.length, count + 1)
  decreasing_by
    · exact Prod.Lex.right _ (by omega)
    · rw [List.length_drop]
      rcases Nat.lt_or_eq_of_le (Nat.sub_le bytes.length span) with shorter | same
      · exact Prod.Lex.left _ _ shorter
      · rw [same]
        exact Prod.Lex.right _ (by omega)
end

/-- The parameter types a descriptor describes; none unless its version is `VERSION` and its body is exactly
`paramCount` nodes. -/
def Descriptor.decode : Bytes → Option (List AbiType)
  | version :: count :: body =>
    if version = VERSION then
      match decodeNodes count.toNat body with
      | some (types, span) => if span = body.length then some types else none
      | none => none
    else none
  | _ => none

end Callcium

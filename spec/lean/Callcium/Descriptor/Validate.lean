import Callcium.Descriptor.Codec

/-!
# Descriptor validation

`Descriptor.wellFormed` is well-formedness (DWF-1 to DWF-8). It reads nodes by `nodeLength`: a node's span is its
`nodeLength`, each sibling starts where the previous node's `nodeLength` ends, and a static array's length suffix
follows its element's `nodeLength`. `Descriptor.valid` adds validity (DV-1, DV-2): the descriptor decodes, so
every composite node's metadata agrees with the walk of its children. `Descriptor.encode?` is the builder: it rejects a
type list outside the limits instead of encoding it.
-/

namespace Callcium

open Descriptor

namespace Descriptor

/-- Whether the code names an elementary type. -/
def isElementary (code : UInt8) : Bool :=
  (WordType.ofCode? code).isSome || code == TypeCode.BYTES || code == TypeCode.STRING

/-- Whether the code names a composite type. -/
def isComposite (code : UInt8) : Bool :=
  code == TypeCode.TUPLE || code == TypeCode.STATIC_ARRAY || code == TypeCode.DYNAMIC_ARRAY

/-- The header size of a composite node with the code. -/
def headerSize (code : UInt8) : Nat :=
  if code = TypeCode.TUPLE then TUPLE_HEADER_SIZE else ARRAY_HEADER_SIZE

/-- The span of the node opening `bytes` by its `nodeLength`, one byte for an elementary node; none for an unknown code
(DWF-3) or a composite whose metadata is cut short, whose `nodeLength` is below its header, or whose span leaves
`bytes` (DWF-4). -/
def skipNode : Bytes → Option Nat
  | [] => none
  | code :: rest =>
    if isElementary code then some 1
    else if isComposite code then
      match rest with
      | high :: middle :: low :: _ =>
        let nodeLength := (metaFields high middle low).2
        if headerSize code ≤ nodeLength ∧ nodeLength ≤ rest.length + 1 then some nodeLength else none
      | _ => none
    else none

/-- The total span of `count` consecutive nodes opening `bytes`, each skipped by its `nodeLength`. -/
def skipNodes : Nat → Bytes → Option Nat
  | 0, _ => some 0
  | count + 1, bytes => (skipNode bytes).bind fun span => (skipNodes count (bytes.drop span)).map (span + ·)

/-- The span of the node opening `bytes` by structural walk: its header, its children back to back and, for a static
array, the length suffix. -/
def walkNode (bytes : Bytes) : Option Nat :=
  (decodeNode bytes).map (·.2)

mutual
  /-- The span of the well-formed node opening `bytes` at nesting `depth`, by its `nodeLength`. Its children are
  well-formed at `depth + 1`; a tuple has 1 to `MAX_TUPLE_FIELDS` fields (DWF-5), a static array 1 to
  `MAX_STATIC_ARRAY_LENGTH` elements (DWF-6), and a composite node sits at most `MAX_NESTING_DEPTH` deep (DWF-7). -/
  def checkNode (depth : Nat) : Bytes → Option Nat
    | [] => none
    | bytes@(code :: rest) =>
      match skipNode bytes with
      | none => none
      | some span =>
        if code = TypeCode.TUPLE then
          match rest with
          | _ :: _ :: _ :: countHigh :: countLow :: fieldBytes =>
            let count := readBe16 countHigh countLow
            if depth ≤ MAX_NESTING_DEPTH ∧ 0 < count ∧ count ≤ MAX_TUPLE_FIELDS then
              (checkNodes (depth + 1) count fieldBytes).map fun _ => span
            else none
          | _ => none
        else if code = TypeCode.STATIC_ARRAY then
          match rest with
          | _ :: _ :: _ :: body =>
            if depth ≤ MAX_NESTING_DEPTH then
              match checkNode (depth + 1) body with
              | some elementSpan =>
                match body.drop elementSpan with
                | lengthHigh :: lengthLow :: _ =>
                  let length := readBe16 lengthHigh lengthLow
                  if 0 < length ∧ length ≤ MAX_STATIC_ARRAY_LENGTH then some span else none
                | _ => none
              | none => none
            else none
          | _ => none
        else if code = TypeCode.DYNAMIC_ARRAY then
          match rest with
          | _ :: _ :: _ :: body =>
            if depth ≤ MAX_NESTING_DEPTH then (checkNode (depth + 1) body).map fun _ => span else none
          | _ => none
        else some span
  termination_by bytes => (bytes.length, 0)

  /-- The total span of `count` well-formed nodes at nesting `depth`, each starting where the previous node's
  `nodeLength` ends. -/
  def checkNodes (depth : Nat) : Nat → Bytes → Option Nat
    | 0, _ => some 0
    | count + 1, bytes =>
      match checkNode depth bytes with
      | some span => (checkNodes depth count (bytes.drop span)).map (span + ·)
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

/-- Whether the descriptor is well-formed (DWF-1 to DWF-8): version `VERSION`, then exactly `paramCount` well-formed
parameter nodes and nothing after them. -/
def wellFormed : Bytes → Bool
  | version :: count :: body => version == VERSION && checkNodes 1 count.toNat body == some body.length
  | _ => false

/-- Whether the descriptor is valid: well-formed (DWF-1 to DWF-8), and every composite node's `nodeLength` is its span
(DV-1) and its `staticWords` its type's (DV-2). -/
def valid (desc : Bytes) : Bool :=
  wellFormed desc && (decode desc).isSome

/-- The descriptor the builder produces for the types, or none where it rejects them: a node that does not fit, more
than `MAX_PARAMS` parameters, or a descriptor that is not well-formed. -/
def encode? (types : List AbiType) : Option Bytes :=
  if types.length ≤ MAX_PARAMS ∧ types.all (·.fits) ∧ wellFormed (encode types) then some (encode types) else none

/-- The `staticWords` of the node opening `bytes`: 1 for a static elementary node, 0 for `bytes` and `string`, and its
metadata field for a composite node; none for an unknown code or metadata cut short. -/
def nodeStaticWords : Bytes → Option Nat
  | [] => none
  | code :: rest =>
    if (WordType.ofCode? code).isSome then some 1
    else if code = TypeCode.BYTES ∨ code = TypeCode.STRING then some 0
    else if isComposite code then
      match rest with
      | high :: middle :: low :: _ => some (metaFields high middle low).1
      | _ => none
    else none

/-- The structural walk of `desc` reaches a node at `offset`: a parameter, a tuple field, or an array element. -/
inductive NodeAt (desc : Bytes) : Nat → Prop
  /-- Parameter `index`, after the walk of the parameters before it. -/
  | param {version count : UInt8} {body : Bytes} {index : Nat} {types : List AbiType} {span : Nat} :
      desc = version :: count :: body → index < count.toNat → decodeNodes index body = some (types, span) →
      NodeAt desc (2 + span)
  /-- Field `index` of a tuple, after the walk of the fields before it. -/
  | field {offset : Nat} {high middle low countHigh countLow : UInt8} {fieldBytes : Bytes} {index : Nat}
      {types : List AbiType} {span : Nat} :
      NodeAt desc offset →
      desc.drop offset = TypeCode.TUPLE :: high :: middle :: low :: countHigh :: countLow :: fieldBytes →
      index < readBe16 countHigh countLow → decodeNodes index fieldBytes = some (types, span) →
      NodeAt desc (offset + TUPLE_HEADER_SIZE + span)
  /-- The element of an array. -/
  | element {offset : Nat} {code : UInt8} {rest : Bytes} :
      NodeAt desc offset → desc.drop offset = code :: rest →
      (code = TypeCode.STATIC_ARRAY ∨ code = TypeCode.DYNAMIC_ARRAY) → NodeAt desc (offset + ARRAY_HEADER_SIZE)

end Descriptor

end Callcium

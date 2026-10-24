import Callcium.Abi.Type

/-!
# Descriptor format

The byte layout of descriptor v2 as `spec/descriptor-v2.md` defines it. It covers the type codes, the fields of a
composite node, the length of a type's node, and the limits. A descriptor is `version | paramCount | params`. An
elementary node is its type code. A composite node starts with its code and three metadata bytes: `staticWords` in the
high 12 bits and `nodeLength` in the low 12.
-/

namespace Callcium

/-! ## Constants -/

namespace Descriptor

/-- The descriptor format version. -/
def VERSION : UInt8 := 0x02

/-- A tuple node's header: code, metadata and `fieldCount`. -/
def TUPLE_HEADER_SIZE : Nat := 6

/-- An array node's header: code and metadata. -/
def ARRAY_HEADER_SIZE : Nat := 4

/-- A static array node's length suffix. -/
def ARRAY_LENGTH_SIZE : Nat := 2

/-- The largest `nodeLength`, the capacity of its 12-bit field. -/
def MAX_NODE_LENGTH : Nat := 2 ^ 12 - 1

/-- The largest `staticWords`, the capacity of its 12-bit field. -/
def MAX_STATIC_WORDS : Nat := 2 ^ 12 - 1

/-- The longest static array (DWF-6). -/
def MAX_STATIC_ARRAY_LENGTH : Nat := 2 ^ 12 - 1

/-- The most fields a tuple contains (DWF-5): as many one-byte nodes as fit a node of `MAX_NODE_LENGTH` bytes. -/
def MAX_TUPLE_FIELDS : Nat := MAX_NODE_LENGTH - TUPLE_HEADER_SIZE

/-- The deepest a composite node nests, counted from its parameter's node, inclusive (DWF-7). -/
def MAX_NESTING_DEPTH : Nat := 64

/-- The most parameters, the capacity of the one-byte `paramCount`. -/
def MAX_PARAMS : Nat := 2 ^ 8 - 1

end Descriptor

namespace TypeCode

/-- `uint8`. `uintN` is `N / 8`. -/
def UINT8 : UInt8 := 0x01
/-- `int8`. `intN` is `0x20 + N / 8`. -/
def INT8 : UInt8 := 0x21
/-- `address`. -/
def ADDRESS : UInt8 := 0x41
/-- `bool`. -/
def BOOL : UInt8 := 0x42
/-- An external function pointer. -/
def FUNCTION : UInt8 := 0x43
/-- `bytes1`. `bytesN` is `0x4F + N`. -/
def BYTES1 : UInt8 := 0x50
/-- `bytes`. -/
def BYTES : UInt8 := 0x70
/-- `string`. -/
def STRING : UInt8 := 0x71
/-- A static array. -/
def STATIC_ARRAY : UInt8 := 0x80
/-- A dynamic array. -/
def DYNAMIC_ARRAY : UInt8 := 0x81
/-- A tuple. -/
def TUPLE : UInt8 := 0x90

end TypeCode

/-- The type code of a word type. -/
def WordType.code : WordType → UInt8
  | .uint width => UInt8.ofNat (width.bits / 8)
  | .int width => UInt8.ofNat (0x20 + width.bits / 8)
  | .address => TypeCode.ADDRESS
  | .bool => TypeCode.BOOL
  | .function => TypeCode.FUNCTION
  | .fixedBytes width => UInt8.ofNat (0x4F + width.bits / 8)

/-- The word type a code names, or none for a code outside the word types. -/
def WordType.ofCode? (code : UInt8) : Option WordType :=
  if fits : 0x01 ≤ code.toNat ∧ code.toNat ≤ 0x20 then some (.uint ⟨⟨code.toNat - 0x01, by omega⟩⟩)
  else if fits : 0x21 ≤ code.toNat ∧ code.toNat ≤ 0x40 then some (.int ⟨⟨code.toNat - 0x21, by omega⟩⟩)
  else if code = TypeCode.ADDRESS then some .address
  else if code = TypeCode.BOOL then some .bool
  else if code = TypeCode.FUNCTION then some .function
  else if fits : 0x50 ≤ code.toNat ∧ code.toNat ≤ 0x6F then some (.fixedBytes ⟨⟨code.toNat - 0x50, by omega⟩⟩)
  else none

/-! ## Fields -/

/-- A composite node's three metadata bytes. -/
def Descriptor.compositeMeta (staticWords nodeLength : Nat) : Bytes :=
  let metaValue := staticWords * 2 ^ 12 + nodeLength
  [UInt8.ofNat (metaValue / 2 ^ 16), UInt8.ofNat (metaValue / 2 ^ 8), UInt8.ofNat metaValue]

/-- `staticWords` and `nodeLength` from a composite node's three metadata bytes. -/
def Descriptor.metaFields (high middle low : UInt8) : Nat × Nat :=
  let metaValue := high.toNat * 2 ^ 16 + middle.toNat * 2 ^ 8 + low.toNat
  (metaValue / 2 ^ 12, metaValue % 2 ^ 12)

/-- A big-endian 16-bit field. -/
def Descriptor.be16 (value : Nat) : Bytes :=
  [UInt8.ofNat (value / 2 ^ 8), UInt8.ofNat value]

/-- The value of a big-endian 16-bit field. -/
def Descriptor.readBe16 (high low : UInt8) : Nat :=
  high.toNat * 2 ^ 8 + low.toNat

/-! ## Node length and limits -/

open Descriptor

mutual
  /-- The length of the type's node in bytes. -/
  def AbiType.nodeLength : AbiType → Nat
    | .word _ | .bytes | .string => 1
    | .staticArray element _ => ARRAY_HEADER_SIZE + element.nodeLength + ARRAY_LENGTH_SIZE
    | .dynamicArray element => ARRAY_HEADER_SIZE + element.nodeLength
    | .tuple fields => TUPLE_HEADER_SIZE + AbiType.sumNodeLength fields

  /-- The node lengths summed. -/
  def AbiType.sumNodeLength : List AbiType → Nat
    | [] => 0
    | field :: fields => field.nodeLength + AbiType.sumNodeLength fields
end

/-- Whether the type's node fits its metadata fields. -/
def AbiType.metaFits (abiType : AbiType) : Bool :=
  abiType.nodeLength ≤ MAX_NODE_LENGTH && abiType.staticWords ≤ MAX_STATIC_WORDS

mutual
  /-- Whether every node of the type fits. A tuple has 1 to `MAX_TUPLE_FIELDS` fields (DWF-5), a static array 1 to
  `MAX_STATIC_ARRAY_LENGTH` elements (DWF-6), and every composite node fits its metadata fields. -/
  def AbiType.fits : AbiType → Bool
    | .word _ | .bytes | .string => true
    | abiType@(.staticArray element length) =>
      0 < length && length ≤ MAX_STATIC_ARRAY_LENGTH && abiType.metaFits && element.fits
    | abiType@(.dynamicArray element) => abiType.metaFits && element.fits
    | abiType@(.tuple fields) =>
      0 < fields.length && fields.length ≤ MAX_TUPLE_FIELDS && abiType.metaFits && AbiType.allFit fields

  /-- Whether every type fits. -/
  def AbiType.allFit : List AbiType → Bool
    | [] => true
    | field :: fields => field.fits && AbiType.allFit fields
end

mutual
  /-- Whether no composite node of the type nests deeper than `MAX_NESTING_DEPTH`, its own node at `depth` (DWF-7). -/
  def AbiType.withinDepth (depth : Nat) : AbiType → Bool
    | .word _ | .bytes | .string => true
    | .staticArray element _ | .dynamicArray element =>
      depth ≤ MAX_NESTING_DEPTH && element.withinDepth (depth + 1)
    | .tuple fields => depth ≤ MAX_NESTING_DEPTH && AbiType.allWithinDepth (depth + 1) fields

  /-- Whether every type is within depth, its node at `depth`. -/
  def AbiType.allWithinDepth (depth : Nat) : List AbiType → Bool
    | [] => true
    | field :: fields => field.withinDepth depth && AbiType.allWithinDepth depth fields
end

/-- Whether a descriptor can describe the types: at most `MAX_PARAMS` of them, each fitting and within depth counted
from the node of its parameter. -/
def Descriptor.withinLimits (types : List AbiType) : Bool :=
  types.length ≤ MAX_PARAMS && types.all fun abiType => abiType.fits && abiType.withinDepth 1

end Callcium

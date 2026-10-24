import Callcium
import Lean

-- Every declaration of the `Callcium` library rests on Lean's three standard axioms only. No declaration uses
-- `sorry` or `native_decide`.
open Lean Elab Command in
run_cmd do
  let env ← getEnv
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let mut offenders := #[]
  for (name, _) in env.constants.map₁.toList do
    let some moduleIdx := env.getModuleIdxFor? name | continue
    unless (`Callcium).isPrefixOf env.header.moduleNames[moduleIdx.toNat]! do continue
    let extra := (← collectAxioms name).filter (!standard.contains ·)
    unless extra.isEmpty do offenders := offenders.push m!"{name}: {extra.toList}"
  unless offenders.isEmpty do
    throwError m!"non-standard axioms:{indentD (MessageData.joinSep offenders.toList Format.line)}"

/-! ## Canonical form and well-formedness -/

namespace Callcium.Tests

def word (value : Nat) : Word := BitVec.ofNat 256 value

def compare (path : Path) (comparison : Comparison) (values : List Nat) : Rule :=
  .test path ⟨false, comparison, .constant (values.map word)⟩

def wellFormed (formula : Formula) : Bool := decide (Formula.WellFormed formula)

def senderIs (value : Nat) : Rule := .contextTest CTX_MSG_SENDER ⟨false, .eq, .constant [word value]⟩

-- `ALL` loops over one array join. `ANY` loops and loops over other arrays stay apart.
#guard normalize [[.loop .all [0] [compare [0] .eq [1]], .loop .all [0] [compare [1] .eq [2]]]] ==
  [[.loop .all [0] (sortRules [compare [0] .eq [1], compare [1] .eq [2]])]]
#guard ((normalize JointBinding.perRule).head?.map List.length) == some 2
#guard ((normalize [[.loop .all [0] [compare [] .eq [1]], .loop .all [1] [compare [] .eq [1]]]]).head?.map
  List.length) == some 2

-- A rule that both joined bodies contain appears once. A repeated rule or group adds nothing.
#guard normalize [[.loop .all [0] [compare [0] .eq [1], compare [1] .eq [2]],
    .loop .all [0] [compare [0] .eq [1], compare [2] .eq [3]]]] ==
  [[.loop .all [0] (sortRules [compare [0] .eq [1], compare [1] .eq [2], compare [2] .eq [3]])]]
#guard normalize [[compare [0] .eq [1]], [compare [0] .eq [1]]] == [[compare [0] .eq [1]]]
#guard normalize [[.loop .all [0] [compare [] .eq [1], compare [] .eq [1]]]] ==
  [[.loop .all [0] [compare [] .eq [1]]]]

-- Operators order by NOT, then source, then comparison.
#guard sortRules [.test [0] ⟨false, .eq, .context CTX_MSG_VALUE⟩, compare [0] .gt [1]] ==
  [compare [0] .gt [1], .test [0] ⟨false, .eq, .context CTX_MSG_VALUE⟩]

-- NOT stays only where no positive comparison expresses it.
#guard normalize [[.test [0] ⟨true, .gt, .constant [word 5]⟩]] == [[compare [0] .lte [5]]]
#guard normalize [[.test [0] ⟨true, .eq, .constant [word 5]⟩]] == [[.test [0] ⟨true, .eq, .constant [word 5]⟩]]

-- A context test against a context property takes the lower ID as subject.
#guard normalize [[.contextTest CTX_BLOCK_NUMBER ⟨false, .gt, .context CTX_BLOCK_TIMESTAMP⟩]] ==
  [[.contextTest CTX_BLOCK_TIMESTAMP ⟨false, .lt, .context CTX_BLOCK_NUMBER⟩]]

#guard wellFormed JointBinding.joint
#guard wellFormed [[.loop .all [0] [compare [] .gte [1]]]]
#guard wellFormed [[compare [0] .in_ [1, 2]]]

-- A lone range pair fuses, also once loops join and after a NOT rewrite. More than one bound on a side stays.
#guard normalize [[compare [0] .gte [1], compare [0] .lte [9]]] == [[compare [0] .between [1, 9]]]
#guard normalize [[compare [0] .lengthGte [1], compare [0] .lengthLte [9]]] == [[compare [0] .lengthBetween [1, 9]]]
#guard normalize [[.loop .all [0] [compare [] .gte [1]], .loop .all [0] [compare [] .lte [9]]]] ==
  [[.loop .all [0] [compare [] .between [1, 9]]]]
#guard normalize [[.test [0] ⟨true, .lt, .constant [word 1]⟩, compare [0] .lte [9]]] == [[compare [0] .between [1, 9]]]
#guard normalize [[compare [0] .gte [1], compare [0] .gte [2], compare [0] .lte [9]]] ==
  [sortRules [compare [0] .gte [1], compare [0] .gte [2], compare [0] .lte [9]]]
#guard wellFormed [[compare [0] .gte [1], compare [0] .lte [9]]]

-- A one-member set is an equality, NOT kept.
#guard normalize [[compare [0] .in_ [5]]] == [[compare [0] .eq [5]]]
#guard normalize [[.test [0] ⟨true, .in_, .constant [word 5]⟩]] == [[.test [0] ⟨true, .eq, .constant [word 5]⟩]]
#guard wellFormed [[compare [0] .in_ [1]]]

-- A context test in an `ANY` body moves to the root, where a root test on the same property fuses with it. Under `ALL`,
-- context tests stay in the body beside a test. A body of context tests alone is rejected under either quantifier.
#guard normalize [[.loop .any [0] [senderIs 1, compare [] .eq [1]]]] ==
  [sortRules [senderIs 1, .loop .any [0] [compare [] .eq [1]]]]
#guard normalize [[.contextTest CTX_MSG_VALUE ⟨false, .gte, .constant [word 5]⟩,
    .loop .any [0] [.contextTest CTX_MSG_VALUE ⟨false, .lte, .constant [word 10]⟩, compare [] .eq [1]]]] ==
  [sortRules [.contextTest CTX_MSG_VALUE ⟨false, .between, .constant [word 5, word 10]⟩,
    .loop .any [0] [compare [] .eq [1]]]]
#guard normalize [[.loop .all [0] [senderIs 1, compare [] .eq [1]]]] ==
  [[.loop .all [0] (sortRules [senderIs 1, compare [] .eq [1]])]]
#guard wellFormed [[.loop .any [0] [senderIs 1, compare [] .eq [1]]]]
#guard wellFormed [[.loop .all [0] [senderIs 1, compare [] .eq [1]]]]
#guard !wellFormed [[.loop .all [0] [senderIs 1]]]
#guard !wellFormed [[.loop .any [0] [senderIs 1]]]

-- Shape: sorted sets, defined context properties, root paths, body shape, cumulative path depth.
#guard !wellFormed [[compare [0] .in_ [2, 1]]]
#guard !wellFormed [[.contextTest (CTX_MAX + 1) ⟨false, .eq, .constant [word 1]⟩]]
#guard !wellFormed [[compare [] .eq [1]]]
#guard !wellFormed [[.loop .all [0] [.loop .all [] [compare [] .eq [1]]]]]
#guard wellFormed [[.loop .all [0] [compare (List.replicate (MAX_PATH_DEPTH - 1) 0) .eq [1]]]]
#guard !wellFormed [[.loop .all [0] [compare (List.replicate MAX_PATH_DEPTH 0) .eq [1]]]]

-- Path steps from the marker range are reserved, in tests and in loops.
#guard wellFormed [[compare [0, PATH_MARKER_BASE - 1] .eq [1]]]
#guard !wellFormed [[compare [0, PATH_MARKER_BASE] .eq [1]]]
#guard !wellFormed [[.loop .all [PATH_MARKER_BASE] [compare [] .eq [1]]]]

/-! ## Evaluation -/

-- The tests of an `ANY` body read one element. Read rule by rule, the decoy passes.
#guard JointBinding.joint.evaluateValues JointBinding.noContext JointBinding.decoy == .fail
#guard JointBinding.perRule.evaluateValues JointBinding.noContext JointBinding.decoy == .pass

-- Groups evaluate in list order: an abort ends evaluation before a later group that holds.
def longArray : List Value := List.replicate (MAX_QUANTIFIED_ARRAY_LENGTH + 1) (.word (word 0) false)
def overLimit : Stack := [⟨.list [.list longArray], none⟩]
def failsThenAbortsThenHolds : Formula :=
  [[compare [0] .lengthEq [0]], [.loop .all [0] [compare [] .eq [0]]], [compare [0] .lengthGt [0]]]
#guard failsThenAbortsThenHolds.evaluateValues JointBinding.noContext overLimit == .abort
#guard failsThenAbortsThenHolds.holds JointBinding.noContext overLimit

-- A path past an array's end fails its group. A later group determines the outcome.
def pastEndThenHolds : Formula := [[compare [0, longArray.length] .eq [0]], [compare [0] .lengthGt [0]]]
#guard pastEndThenHolds.evaluateValues JointBinding.noContext overLimit == .pass

/-! ## Words -/

def width (bytes : Nat) (fits : bytes - 1 < 32 := by omega) : ByteWidth := ⟨⟨bytes - 1, fits⟩⟩

-- No bits above a right-aligned value.
#guard (WordType.uint (width 1)).isCanonical 0xff
#guard !(WordType.uint (width 1)).isCanonical 0x100
#guard WordType.address.isCanonical (2 ^ 160 - 1)
#guard !WordType.address.isCanonical (2 ^ 160)
#guard WordType.bool.isCanonical 1
#guard !WordType.bool.isCanonical 2

-- A signed value is its own sign extension: `int8` represents -128 as `0xff…80`, not `0x80`.
#guard (WordType.int (width 1)).isCanonical (BitVec.ofInt 256 (-128))
#guard (WordType.int (width 1)).isCanonical 0x7f
#guard !(WordType.int (width 1)).isCanonical 0x80

-- No bits below a left-aligned value. A function pointer is left-aligned as `bytes24`.
#guard (WordType.fixedBytes (width 1)).isCanonical (0xab <<< 248)
#guard !(WordType.fixedBytes (width 1)).isCanonical 1
#guard WordType.function.isCanonical (BitVec.ofNat 256 (2 ^ 192 - 1) <<< 64)
#guard !WordType.function.isCanonical (BitVec.ofNat 256 (2 ^ 192 - 1))

-- A full-width type takes every word.
#guard [WordType.uint (width 32), .int (width 32), .fixedBytes (width 32)].all fun wordType =>
  [0, 1, 0x80, BitVec.allOnes 256].all wordType.isCanonical

/-! ## Descriptors -/

def uint256 : AbiType := .word (.uint (width 32))

def address : AbiType := .word .address

/-- Dynamic arrays nested `levels` deep around `uint256`. -/
def nested (levels : Nat) : AbiType := (List.range levels).foldl (fun element _ => .dynamicArray element) uint256

-- The encoder writes the descriptor vectors' blobs, and decoding returns the types.
#guard Descriptor.encode [] == [0x02, 0x00]
#guard Descriptor.encode [.staticArray uint256 4] == [0x02, 0x01, 0x80, 0x00, 0x40, 0x07, 0x20, 0x00, 0x04]
#guard Descriptor.encode [.dynamicArray address] == [0x02, 0x01, 0x81, 0x00, 0x00, 0x05, 0x41]
#guard Descriptor.encode [.tuple [address, uint256]] == [0x02, 0x01, 0x90, 0x00, 0x20, 0x08, 0x00, 0x02, 0x41, 0x20]
#guard Descriptor.encode [.tuple [address, .bytes]] == [0x02, 0x01, 0x90, 0x00, 0x00, 0x08, 0x00, 0x02, 0x41, 0x70]
#guard Descriptor.encode [.staticArray (.staticArray uint256 2) 3] ==
  [0x02, 0x01, 0x80, 0x00, 0x60, 0x0D, 0x80, 0x00, 0x20, 0x07, 0x20, 0x00, 0x02, 0x00, 0x03]
#guard Descriptor.decode (Descriptor.encode [.tuple [address, .dynamicArray (.staticArray .bytes 3)], .string]) ==
  some [.tuple [address, .dynamicArray (.staticArray .bytes 3)], .string]

-- Well-formed but invalid: a `nodeLength` one past the node's span (DV-1), a wrong `staticWords` (DV-2).
#guard Descriptor.wellFormed [0x02, 0x01, 0x81, 0x00, 0x00, 0x06, 0x41, 0x41]
#guard !Descriptor.valid [0x02, 0x01, 0x81, 0x00, 0x00, 0x06, 0x41, 0x41]
#guard Descriptor.wellFormed [0x02, 0x01, 0x80, 0x00, 0x50, 0x07, 0x20, 0x00, 0x04]
#guard !Descriptor.valid [0x02, 0x01, 0x80, 0x00, 0x50, 0x07, 0x20, 0x00, 0x04]

-- The builder rejects a composite nested past `MAX_NESTING_DEPTH`, a static array outside its length range, and a
-- static footprint past `MAX_STATIC_WORDS`.
#guard (Descriptor.encode? [nested Descriptor.MAX_NESTING_DEPTH]).isSome
#guard (Descriptor.encode? [nested (Descriptor.MAX_NESTING_DEPTH + 1)]).isNone
#guard (Descriptor.encode? [.staticArray uint256 Descriptor.MAX_STATIC_ARRAY_LENGTH]).isSome
#guard (Descriptor.encode? [.staticArray uint256 (Descriptor.MAX_STATIC_ARRAY_LENGTH + 1)]).isNone
#guard (Descriptor.encode? [.staticArray uint256 0]).isNone
#guard (Descriptor.encode? [.staticArray (.staticArray uint256 2) Descriptor.MAX_STATIC_ARRAY_LENGTH]).isNone

/-! ## ABI -/

/-- A hex digit's value. -/
def nibble (char : Char) : Nat :=
  if char.isDigit then char.toNat - '0'.toNat else char.toLower.toNat - 'a'.toNat + 10

/-- The bytes a string of hex digits spells, two digits per byte. -/
def hex (digits : String) : Bytes :=
  let rec pairs : List Char → Bytes
    | high :: low :: rest => UInt8.ofNat (nibble high * 16 + nibble low) :: pairs rest
    | _ => []
  pairs digits.toList

/-- A word holding `value`, read as unsigned. -/
def unsigned (value : Nat) : Value := .word (word value) false

def uint8 : AbiType := .word (.uint (width 1))

def selector : Bytes := [0, 0, 0, 0]

-- Encodings from `cast abi-encode`. `f(uint256,uint32[],bytes10,bytes)` on `(0x123, [0x456, 0x789], "1234567890",
-- "Hello, world!")`, the example of the Solidity ABI specification.
def fTypes : List AbiType := [uint256, .dynamicArray (.word (.uint (width 4))), .word (.fixedBytes (width 10)), .bytes]
def fArgs : Value := .list [unsigned 0x123, .list [unsigned 0x456, unsigned 0x789],
  unsigned (0x31323334353637383930 * 2 ^ 176), .bytes "Hello, world!".toUTF8.toList]
def fEncoding : Bytes := hex (
  "0000000000000000000000000000000000000000000000000000000000000123" ++
  "0000000000000000000000000000000000000000000000000000000000000080" ++
  "3132333435363738393000000000000000000000000000000000000000000000" ++
  "00000000000000000000000000000000000000000000000000000000000000e0" ++
  "0000000000000000000000000000000000000000000000000000000000000002" ++
  "0000000000000000000000000000000000000000000000000000000000000456" ++
  "0000000000000000000000000000000000000000000000000000000000000789" ++
  "000000000000000000000000000000000000000000000000000000000000000d" ++
  "48656c6c6f2c20776f726c642100000000000000000000000000000000000000")
#guard (AbiType.tuple fTypes).encode fArgs == fEncoding
#guard (AbiType.tuple fTypes).decodeStrict (selector ++ fEncoding) 4 == some fArgs

-- Bytes after the encoding, such as the 20-byte sender an ERC-2771 forwarder appends, keep it canonical.
#guard (AbiType.tuple fTypes).decodeStrict (selector ++ fEncoding ++ List.replicate 20 1) 4 == some fArgs

-- `g(uint256[][],string[])` on `([[1, 2], [3]], ["one", "two", "three"])`: offsets inside nested tails count from the
-- start of each tail's elements.
def gTypes : List AbiType := [.dynamicArray (.dynamicArray uint256), .dynamicArray .string]
def gArgs : Value := .list [.list [.list [unsigned 1, unsigned 2], .list [unsigned 3]],
  .list (["one", "two", "three"].map fun text => .bytes text.toUTF8.toList)]
def gEncoding : Bytes := hex (
  "0000000000000000000000000000000000000000000000000000000000000040" ++
  "0000000000000000000000000000000000000000000000000000000000000140" ++
  "0000000000000000000000000000000000000000000000000000000000000002" ++
  "0000000000000000000000000000000000000000000000000000000000000040" ++
  "00000000000000000000000000000000000000000000000000000000000000a0" ++
  "0000000000000000000000000000000000000000000000000000000000000002" ++
  "0000000000000000000000000000000000000000000000000000000000000001" ++
  "0000000000000000000000000000000000000000000000000000000000000002" ++
  "0000000000000000000000000000000000000000000000000000000000000001" ++
  "0000000000000000000000000000000000000000000000000000000000000003" ++
  "0000000000000000000000000000000000000000000000000000000000000003" ++
  "0000000000000000000000000000000000000000000000000000000000000060" ++
  "00000000000000000000000000000000000000000000000000000000000000a0" ++
  "00000000000000000000000000000000000000000000000000000000000000e0" ++
  "0000000000000000000000000000000000000000000000000000000000000003" ++
  "6f6e650000000000000000000000000000000000000000000000000000000000" ++
  "0000000000000000000000000000000000000000000000000000000000000003" ++
  "74776f0000000000000000000000000000000000000000000000000000000000" ++
  "0000000000000000000000000000000000000000000000000000000000000005" ++
  "7468726565000000000000000000000000000000000000000000000000000000")
#guard (AbiType.tuple gTypes).encode gArgs == gEncoding
#guard (AbiType.tuple gTypes).decodeStrict gEncoding 0 == some gArgs

-- `h((int8,address,bool),bytes2[2],(uint256,bytes))` on `((-1, address(1), true), [0x0102, 0x0304], (7, 0xaabb))`: a
-- static tuple and a static array sit in the head, and `int8` reads as signed.
def hTypes : List AbiType :=
  [.tuple [.word (.int (width 1)), address, .word .bool], .staticArray (.word (.fixedBytes (width 2))) 2,
    .tuple [uint256, .bytes]]
def hArgs : Value := .list [.list [.word (BitVec.allOnes 256) true, unsigned 1, unsigned 1],
  .list [unsigned (0x0102 * 2 ^ 240), unsigned (0x0304 * 2 ^ 240)], .list [unsigned 7, .bytes [0xaa, 0xbb]]]
def hEncoding : Bytes := hex (
  "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" ++
  "0000000000000000000000000000000000000000000000000000000000000001" ++
  "0000000000000000000000000000000000000000000000000000000000000001" ++
  "0102000000000000000000000000000000000000000000000000000000000000" ++
  "0304000000000000000000000000000000000000000000000000000000000000" ++
  "00000000000000000000000000000000000000000000000000000000000000c0" ++
  "0000000000000000000000000000000000000000000000000000000000000007" ++
  "0000000000000000000000000000000000000000000000000000000000000040" ++
  "0000000000000000000000000000000000000000000000000000000000000002" ++
  "aabb000000000000000000000000000000000000000000000000000000000000")
#guard (AbiType.tuple hTypes).encode hArgs == hEncoding
#guard (AbiType.tuple hTypes).decodeStrict hEncoding 0 == some hArgs
#guard (hTypes.map AbiType.headSize) == [96, 64, 32]

-- `k(string[2],bytes[2][])` on `(["one", "three"], [[0xaa, 0xbbcc]])`: a static array of dynamic elements is dynamic,
-- and its elements' offsets count from its own start.
def kTypes : List AbiType := [.staticArray .string 2, .dynamicArray (.staticArray .bytes 2)]
def kArgs : Value := .list [.list [.bytes "one".toUTF8.toList, .bytes "three".toUTF8.toList],
  .list [.list [.bytes [0xaa], .bytes [0xbb, 0xcc]]]]
def kEncoding : Bytes := hex (
  "0000000000000000000000000000000000000000000000000000000000000040" ++
  "0000000000000000000000000000000000000000000000000000000000000100" ++
  "0000000000000000000000000000000000000000000000000000000000000040" ++
  "0000000000000000000000000000000000000000000000000000000000000080" ++
  "0000000000000000000000000000000000000000000000000000000000000003" ++
  "6f6e650000000000000000000000000000000000000000000000000000000000" ++
  "0000000000000000000000000000000000000000000000000000000000000005" ++
  "7468726565000000000000000000000000000000000000000000000000000000" ++
  "0000000000000000000000000000000000000000000000000000000000000001" ++
  "0000000000000000000000000000000000000000000000000000000000000020" ++
  "0000000000000000000000000000000000000000000000000000000000000040" ++
  "0000000000000000000000000000000000000000000000000000000000000080" ++
  "0000000000000000000000000000000000000000000000000000000000000001" ++
  "aa00000000000000000000000000000000000000000000000000000000000000" ++
  "0000000000000000000000000000000000000000000000000000000000000002" ++
  "bbcc000000000000000000000000000000000000000000000000000000000000")
#guard (AbiType.tuple kTypes).encode kArgs == kEncoding
#guard (AbiType.tuple kTypes).decodeStrict kEncoding 0 == some kArgs

-- Only `intN` reads as signed.
#guard [WordType.uint (width 32), .address, .bool, .function, .fixedBytes (width 32)].all (!·.signed)

-- No arguments: the selector alone. Data shorter than the selector is not canonical.
#guard (AbiType.tuple []).decodeStrict selector 4 == some (.list [])
#guard (AbiType.tuple []).decodeStrict [0, 0] 4 == none

-- A dirty word, nonzero padding after `bytes`, and a gap before a tail read as they are and are not canonical.
def dirty : Bytes := beBytes WORD_SIZE 0x1ff
#guard (AbiType.tuple [uint8]).decodeSolc dirty 0 == .list [unsigned 0x1ff]
#guard (AbiType.tuple [uint8]).decodeStrict dirty 0 == none
def dirtyPadding : Bytes := beBytes WORD_SIZE 0x20 ++ beBytes WORD_SIZE 1 ++ 0xaa :: List.replicate 30 0 ++ [1]
#guard (AbiType.tuple [.bytes]).decodeSolc dirtyPadding 0 == .list [.bytes [0xaa]]
#guard (AbiType.tuple [.bytes]).decodeStrict dirtyPadding 0 == none
def gap : Bytes := beBytes WORD_SIZE 0x40 ++ beBytes WORD_SIZE 0 ++ beBytes WORD_SIZE 1 ++ 0xaa :: List.replicate 31 0
#guard (AbiType.tuple [.bytes]).decodeSolc gap 0 == .list [.bytes [0xaa]]
#guard (AbiType.tuple [.bytes]).decodeStrict gap 0 == none

-- A read that crosses the end of the data pads with zeros: a word, and `bytes` longer than what remains.
#guard (AbiType.tuple [uint256]).decodeSolc [1] 0 == .list [unsigned (2 ^ 248)]
#guard (AbiType.tuple [.bytes]).decodeSolc (beBytes WORD_SIZE 0x20 ++ beBytes WORD_SIZE 3 ++ [0xaa]) 0 ==
  .list [.bytes [0xaa, 0, 0]]

-- `f(bytes[] calldata a)` returning `a[0]`, the onchain table of the SolidCore wrap design: `a`'s tail at 132, one
-- element whose offset word sits at 164, the end of the calldata at 196. An offset of 2^256 - 128 wraps to 36 and reads
-- `0xaabb`. An offset of 2^255 lands past the end and reads empty. A forward offset of 0x20 reads the bytes appended at
-- the end of the calldata.
def wrapping (offset : Nat) : Bytes :=
  selector ++ beBytes WORD_SIZE 0x80 ++ beBytes WORD_SIZE 2 ++ 0xaa :: 0xbb :: List.replicate 30 0 ++
    beBytes WORD_SIZE 0 ++ beBytes WORD_SIZE 1 ++ beBytes WORD_SIZE offset
#guard (wrapping 0).length == 196
#guard (AbiType.tuple [.dynamicArray .bytes]).decodeSolc (wrapping (2 ^ 256 - 128)) 4 ==
  .list [.list [.bytes [0xaa, 0xbb]]]
#guard (AbiType.tuple [.dynamicArray .bytes]).decodeSolc (wrapping (2 ^ 255)) 4 == .list [.list [.bytes []]]
#guard (AbiType.tuple [.dynamicArray .bytes]).decodeSolc
  (wrapping 0x20 ++ beBytes WORD_SIZE 2 ++ 0xaa :: 0xbb :: List.replicate 30 0) 4 == .list [.list [.bytes [0xaa, 0xbb]]]
#guard (AbiType.tuple [.dynamicArray .bytes]).decodeStrict (wrapping (2 ^ 256 - 128)) 4 == none

/-! ## Hints -/

/-- Where the compiled hint of `path` within the arguments resolves from `start`. -/
def resolves (types : List AbiType) (data : Bytes) (start : Nat) (path : Path) : Option Nat :=
  ((AbiType.tuple types).compile? path).bind fun hint => (hint.resolve data start).toOption

/-- The fault that stops the compiled hint of `path` within the arguments. -/
def faults (types : List AbiType) (data : Bytes) (start : Nat) (path : Path) : Option Fault :=
  ((AbiType.tuple types).compile? path).bind fun hint =>
    match hint.resolve data start with
    | .error fault => some fault
    | .ok _ => none

/-- Where `decodeSolc` places the value at `path` within the arguments. -/
def located (types : List AbiType) (data : Bytes) (start : Nat) (path : Path) : Option Nat :=
  ((AbiType.tuple types).locate data start path).map (·.2)

/-- Where each element of the loop over `arrayPath` starts. -/
def elementStarts (types : List AbiType) (data : Bytes) (start : Nat) (arrayPath : Path) : Option (List Nat) :=
  ((AbiType.tuple types).compileLoop? arrayPath).bind fun loop =>
    match loop.resolveArray data start with
    | .ok (elements, count) =>
      (List.range count).mapM fun position => (loop.resolveElement data elements position).toOption
    | .error _ => none

-- One hop per dynamic boundary: `bytes` behind its offset word, an element of `uint32[]` behind the array's, and a
-- static array in the head reached by its delta alone.
#guard ((AbiType.tuple fTypes).compile? [3]).map (·.hops) == some [.plain 96]
#guard ((AbiType.tuple fTypes).compile? [1, 1]).map (·.hops) ==
  some [.plain 32, .element 1 ⟨true, false, 1⟩]
#guard (((AbiType.tuple hTypes).compile? [1, 1]).map fun hint => (hint.hops, hint.targetDelta)) == some ([], 128)

-- On canonical calldata every hint resolves where `decodeSolc` places the value.
#guard [[0], [1], [1, 0], [1, 1], [2], [3]].all fun path =>
  resolves fTypes (selector ++ fEncoding) 4 path == located fTypes (selector ++ fEncoding) 4 path &&
    (resolves fTypes (selector ++ fEncoding) 4 path).isSome
#guard resolves fTypes (selector ++ fEncoding) 4 [3] == some (4 + 0xe0)
#guard [[0, 0, 1], [0, 1, 0], [1, 2]].all fun path =>
  resolves gTypes gEncoding 0 path == located gTypes gEncoding 0 path && (resolves gTypes gEncoding 0 path).isSome
#guard [[0, 0], [0, 2], [1, 1], [2, 1]].all fun path =>
  resolves hTypes hEncoding 0 path == located hTypes hEncoding 0 path && (resolves hTypes hEncoding 0 path).isSome
#guard [[0, 1], [1, 0, 1]].all fun path =>
  resolves kTypes kEncoding 0 path == located kTypes kEncoding 0 path && (resolves kTypes kEncoding 0 path).isSome

-- Two offset words sharing one tail resolve to it, as `decodeSolc` reads them.
def shared : Bytes :=
  beBytes WORD_SIZE 0x40 ++ beBytes WORD_SIZE 0x40 ++ beBytes WORD_SIZE 1 ++ 0xaa :: List.replicate 31 0
#guard resolves [.bytes, .bytes] shared 0 [0] == some 0x40 && resolves [.bytes, .bytes] shared 0 [1] == some 0x40

-- A fixed index past a dynamic array's length fails the group. Past a static array's length, the path does not compile.
#guard faults fTypes (selector ++ fEncoding) 4 [1, 2] == some .arrayIndexOutOfBounds
#guard ((AbiType.tuple hTypes).compile? [1, 2]).isNone

-- A word read past the end of the calldata, or an offset that passes it, aborts. In these cases `decodeSolc` wraps to
-- the start of `bytes` or reads past the end of the calldata.
#guard faults fTypes ((selector ++ fEncoding).take 100) 4 [3] == some .calldataOutOfBounds
#guard faults [.dynamicArray .bytes] (wrapping (2 ^ 256 - 128)) 4 [0, 0] == some .calldataOutOfBounds
#guard faults [.dynamicArray .bytes] (wrapping (2 ^ 255)) 4 [0, 0] == some .calldataOutOfBounds
#guard resolves [.dynamicArray .bytes] (wrapping 0x20 ++ beBytes WORD_SIZE 2 ++ 0xaa :: 0xbb :: List.replicate 30 0) 4
  [0, 0] == some 196

-- A loop's hint yields each element where `decodeSolc` places it: a dynamic array, a static array in the head, and a
-- static array of dynamic elements.
#guard elementStarts fTypes (selector ++ fEncoding) 4 [1] ==
  [[1, 0], [1, 1]].mapM (located fTypes (selector ++ fEncoding) 4)
#guard elementStarts hTypes hEncoding 0 [1] == some [96, 128]
#guard elementStarts kTypes kEncoding 0 [0] == [[0, 0], [0, 1]].mapM (located kTypes kEncoding 0)
#guard elementStarts gTypes gEncoding 0 [0, 1] == some [0x120]

-- A body test's hint, compiled from the loop's element type, resolves from each element where `decodeSolc` places
-- the value it names: the first entry of each `uint256[]` in `uint256[][]`.
#guard (((AbiType.tuple gTypes).compileLoop? [0]).bind fun loop =>
    (loop.element.compile? [0]).bind fun hint =>
      (elementStarts gTypes gEncoding 0 [0]).bind fun starts =>
        starts.mapM fun elementStart => (hint.resolve gEncoding elementStart).toOption) ==
  [[0, 0, 0], [0, 1, 0]].mapM (located gTypes gEncoding 0)

-- A loop's frame states its array: the declared `count`, 0 for a dynamic array, and the meta word.
#guard (((AbiType.tuple fTypes).compileLoop? [1]).map fun loop => (loop.count, loop.array)) ==
  some (0, ⟨true, false, 1⟩)
#guard (((AbiType.tuple hTypes).compileLoop? [1]).map fun loop => (loop.count, loop.array)) ==
  some (2, ⟨false, false, 1⟩)
#guard (((AbiType.tuple kTypes).compileLoop? [0]).map fun loop => (loop.count, loop.array)) ==
  some (2, ⟨false, true, 1⟩)

-- A static array of no elements has no loop hint, since a `count` of 0 states a dynamic array. A value that is not an
-- array has no loop hint either.
#guard ((AbiType.tuple [.staticArray uint256 0]).compileLoop? [0]).isNone
#guard ((AbiType.tuple fTypes).compileLoop? [3]).isNone

/-! ## Wire -/

def treasurySignature : Signature := ⟨some 0x5d1e0f3a, [.dynamicArray (.tuple [address, uint256])]⟩

def compiledPolicy (signature : Signature) (formula : Formula) : CompiledPolicy :=
  (CompiledPolicy.compile signature (normalize formula)).getD ⟨none, [], []⟩

-- The treasury policy encodes, passes storage, and decodes to its normal form. Its loop rule takes 112 bytes: a 24-byte
-- loop header, a 2-byte body `ruleCount`, and tests of 37 and 49 bytes.
#guard decide (Policy.WellFormed treasurySignature JointBinding.joint)
#guard Policy.validate (Policy.encode treasurySignature JointBinding.joint)
#guard Policy.decode (Policy.encode treasurySignature JointBinding.joint) == some (normalize JointBinding.joint)
#guard (compiledPolicy treasurySignature JointBinding.joint).groups.map (·.map (·.write.length)) == [[112]]
#guard (compiledPolicy treasurySignature JointBinding.joint).groups.map
    (·.map fun | .loop _ _ _ body => body.map (·.write.length) | .test _ => []) == [[[37, 49]]]

-- A blob over `f(uint256)` with one group of the given rule bytes, selector slot zero and flag clear.
def oneWordDesc : Bytes := Descriptor.encode [uint256]
def blobOf (groupCount : Nat) (groups : Bytes) : Bytes :=
  Policy.header false :: beBytes 4 0 ++ beBytes 2 oneWordDesc.length ++ oneWordDesc ++ UInt8.ofNat groupCount :: groups
def groupOf (ruleCount : Nat) (rules : Bytes) : Bytes := beBytes 2 ruleCount ++ beBytes 4 rules.length ++ rules
def oneRule (content : Bytes) : Bytes := blobOf 1 (groupOf 1 (frameRule content))

def wordHint : TestHint := ⟨[], 0, none, uint256.code⟩
def eqOne : Operator := ⟨false, .eq, .constant [word 1]⟩
def calldataTest (path : Path) (hint : TestHint) (operator : Operator) : Bytes :=
  (CompiledTest.test path hint operator).sizeFree
def withOperator (path : Path) (hint : TestHint) (operatorBytes : Bytes) : Bytes :=
  SCOPE_CALLDATA :: writePath path ++ hint.write ++ operatorBytes
def stores (content : Bytes) : Bool := Policy.validate (oneRule content)

-- Constants are as wide as their operand type: a length 4 bytes, `msg.sender` an address, any other property a word.
#guard (⟨false, .lengthEq, .constant [word 1]⟩ : Operator).data TypeCode.BYTES == beBytes 4 1
#guard (CompiledTest.contextTest CTX_MSG_SENDER eqOne).sizeFree.length + 12 ==
  (CompiledTest.contextTest CTX_MSG_VALUE eqOne).sizeFree.length

-- The hand-assembled blob is the writer's.
#guard oneRule (calldataTest [0] wordHint eqOne) ==
  CompiledPolicy.write ⟨some 0, oneWordDesc, [[.test (.test [0] wordHint eqOne)]]⟩
#guard stores (calldataTest [0] wordHint eqOne)

-- Header: major `MAJOR`, minor `MINOR`, a zero selector slot when selectorless. A trailing byte is not valid.
#guard !Policy.validate ((oneRule (calldataTest [0] wordHint eqOne)).set 0
  (UInt8.ofNat ((Policy.MAJOR + 1) * 2 ^ Policy.MAJOR_SHIFT)))
#guard !Policy.validate ((oneRule (calldataTest [0] wordHint eqOne)).set 0
  (UInt8.ofNat (Policy.MAJOR * 2 ^ Policy.MAJOR_SHIFT + (Policy.MINOR + 1) * 2 ^ Policy.MINOR_SHIFT)))
#guard Policy.validate ((oneRule (calldataTest [0] wordHint eqOne)).set 0 (Policy.header true))
#guard !Policy.validate (((oneRule (calldataTest [0] wordHint eqOne)).set 0 (Policy.header true)).set 4 1)
#guard !Policy.validate (oneRule (calldataTest [0] wordHint eqOne) ++ [0])

-- The descriptor is well-formed. Groups are one or more, each one or more rules that fill `groupSize` exactly. Each
-- rule fills its `ruleSize` exactly.
#guard !Policy.validate (Policy.header false :: beBytes 4 0 ++ beBytes 2 2 ++ [Descriptor.VERSION, 1] ++ 1 ::
  groupOf 1 (frameRule (calldataTest [0] wordHint eqOne)))
#guard !Policy.validate (blobOf 0 [])
#guard !Policy.validate (blobOf 1 (groupOf 0 []))
def oneTestRule : Bytes := frameRule (calldataTest [0] wordHint eqOne)
#guard !Policy.validate (blobOf 1 (beBytes 2 1 ++ beBytes 4 (oneTestRule.length + 1) ++ oneTestRule ++ [0]))
#guard !stores (calldataTest [0] wordHint eqOne ++ [0])

-- Scopes: `0x03` and up are reserved. A context test's path is one step naming a defined property.
#guard !stores (3 :: (calldataTest [0] wordHint eqOne).tail)
#guard stores (CompiledTest.contextTest CTX_MAX eqOne).sizeFree
#guard !stores (CompiledTest.contextTest (CTX_MAX + 1) eqOne).sizeFree
#guard !stores (((CompiledTest.contextTest CTX_MAX eqOne).sizeFree).set 1 2)

-- Paths: no reserved marker, nonempty at the root, within `MAX_PATH_DEPTH`.
#guard stores (calldataTest [PATH_MARKER_BASE - 1] wordHint eqOne)
#guard !stores (calldataTest [PATH_MARKER_BASE] wordHint eqOne)
#guard !stores (calldataTest [] wordHint eqOne)
#guard stores (calldataTest (List.replicate MAX_PATH_DEPTH 0) wordHint eqOne)
#guard !stores (calldataTest (List.replicate (MAX_PATH_DEPTH + 1) 0) wordHint eqOne)

-- Hints: `kind` bits zero, no reserved hop index, a plain hop's meta and an element hop's delta zero, no reserved meta
-- bit, and a target meta word only on a dynamic array.
def elementHop : Hop := .element 0 ⟨true, false, 1⟩
#guard stores (calldataTest [0] ⟨[.plain 0, elementHop], 0, none, uint256.code⟩ eqOne)
#guard !stores (calldataTest [0] ⟨List.replicate (MAX_HOP_COUNT + 1) (.plain 0), 0, none, uint256.code⟩ eqOne)
#guard !stores (calldataTest [0] ⟨[.element PATH_MARKER_BASE ⟨true, false, 1⟩], 0, none, uint256.code⟩ eqOne)
def oneHop (delta index metaWord : Nat) : Bytes :=
  SCOPE_CALLDATA :: writePath [0] ++ (1 :: beBytes 4 delta ++ beBytes 2 index ++ beBytes 2 metaWord) ++ beBytes 4 0 ++
    beBytes 2 0 ++ [uint256.code] ++ eqOne.write uint256.code
#guard stores (oneHop 0 HINT_NO_INDEX 0) && stores (oneHop 0 0 (ArrayMeta.word ⟨true, false, 1⟩))
#guard !stores (oneHop 0 HINT_NO_INDEX 1)
#guard !stores (oneHop 1 0 (ArrayMeta.word ⟨true, false, 1⟩))
#guard !stores (calldataTest [0] ⟨[.element 0 ⟨true, false, META_STRIDE_LIMIT⟩], 0, none, uint256.code⟩ eqOne)
#guard !stores (calldataTest [0] ⟨[], 0, some ⟨true, false, 1⟩, uint256.code⟩ eqOne)

-- Operators: known `comparison` and `source`, a family matching the target type, constants filling `dataLength` at
-- the operand width and as many as the comparison takes, an ascending `IN` set, and a context source only on `EQ`,
-- `GT`, `LT`, `GTE` and `LTE`, two bytes naming a defined property.
#guard !stores (withOperator [0] wordHint (0x00 :: (eqOne.write uint256.code).tail))
#guard !stores (withOperator [0] wordHint (0x08 :: (eqOne.write uint256.code).tail))
#guard !stores (withOperator [0] wordHint (UInt8.ofNat (2 * 2 ^ SOURCE_SHIFT + 1) :: (eqOne.write uint256.code).tail))
#guard !stores (calldataTest [0] wordHint ⟨false, .lengthEq, .constant [word 1]⟩)
#guard !stores (calldataTest [0] ⟨[.plain 0], 0, none, TypeCode.BYTES⟩ eqOne)
#guard stores (calldataTest [0] ⟨[.plain 0], 0, none, TypeCode.BYTES⟩ ⟨false, .lengthEq, .constant [word 1]⟩)
#guard !stores (calldataTest [0] ⟨[], 0, none, TypeCode.TUPLE⟩ eqOne)
#guard !stores (calldataTest [0] wordHint ⟨false, .eq, .constant [word 1, word 2]⟩)
#guard !stores (withOperator [0] wordHint (eqOne.opCode :: beBytes 2 33 ++ eqOne.data uint256.code ++ [0]))
#guard stores (calldataTest [0] wordHint ⟨false, .in_, .constant [word 1]⟩)
#guard stores (calldataTest [0] wordHint ⟨false, .in_, .constant [word 1, word 2]⟩)
#guard !stores (calldataTest [0] wordHint ⟨false, .in_, .constant [word 2, word 1]⟩)
#guard !stores (calldataTest [0] wordHint ⟨false, .in_, .constant [word 1, word 1]⟩)
#guard stores (calldataTest [0] wordHint ⟨false, .lte, .context CTX_MAX⟩)
#guard !stores (calldataTest [0] wordHint ⟨false, .between, .context CTX_MAX⟩)
#guard !stores (calldataTest [0] wordHint ⟨false, .lte, .context (CTX_MAX + 1)⟩)
#guard !stores (withOperator [0] wordHint
  ((⟨false, Comparison.lte, Operand.context CTX_MAX⟩ : Operator).opCode :: beBytes 2 3 ++ beBytes 3 CTX_MAX))

-- Build-time checks are not storage checks: a hint that is not its path's compilation, a `bool` constant above 1, a
-- bitmask on `bool`, and a context operand of another type than the target are stored.
#guard stores (calldataTest [0] ⟨[], WORD_SIZE, none, uint256.code⟩ eqOne)
#guard stores (calldataTest [0] ⟨[], 0, none, WordType.bool.code⟩ ⟨false, .eq, .constant [word 2]⟩)
#guard stores (calldataTest [0] ⟨[], 0, none, WordType.bool.code⟩ ⟨false, .bitmaskAll, .constant [word 1]⟩)
#guard stores (calldataTest [0] ⟨[], 0, none, WordType.address.code⟩ ⟨false, .eq, .context CTX_MSG_VALUE⟩)

-- Loops: a known quantifier, a nonempty array path, a nonempty body, and no loop in a body. A body test's path accepts
-- the empty path, and counts toward `MAX_PATH_DEPTH` with the array path.
def frame : FrameHint := ⟨[.plain 0], 0, 0, ⟨true, false, 1⟩⟩
def bodyTest (path : Path) : CompiledTest := .test path wordHint eqOne
def loopRule (quantifier : Quantifier) (arrayPath : Path) (body : List CompiledTest) : Bytes :=
  (CompiledRule.loop quantifier arrayPath frame body).content CompiledTest.write
#guard stores (loopRule .all [0] [bodyTest []])
#guard !stores ((loopRule .all [0] [bodyTest []]).set 1 0)
#guard !stores ((loopRule .all [0] [bodyTest []]).set 1 3)
#guard !stores (loopRule .all [] [bodyTest []])
#guard !stores (loopRule .any [0] [])
#guard stores (loopRule .any [0] [bodyTest (List.replicate (MAX_PATH_DEPTH - 1) 0)])
#guard !stores (loopRule .any [0] [bodyTest (List.replicate MAX_PATH_DEPTH 0)])
#guard !stores ((CompiledRule.loop .all [0] frame [bodyTest []]).content fun _ =>
  frameRule (loopRule .all [0] [bodyTest []]))

-- The encoder arranges rules, groups and loop bodies in ascending size-free byte order. A policy with any of them
-- reordered is not in that order.
def orderedFormula : Formula :=
  [[.loop .all [0] [compare [1] .gte [7], compare [0] .eq [3]], senderIs 5], [compare [0, 1, 1] .lte [9]],
    [.loop .any [0] [compare [1] .eq [2]]]]
#guard decide (Policy.WellFormed treasurySignature orderedFormula)
#guard (compiledPolicy treasurySignature orderedFormula).ordered
#guard !{ compiledPolicy treasurySignature orderedFormula with
  groups := (compiledPolicy treasurySignature orderedFormula).groups.reverse }.ordered
#guard !{ compiledPolicy treasurySignature orderedFormula with
  groups := (compiledPolicy treasurySignature orderedFormula).groups.map List.reverse }.ordered

/-! ## Enforcement -/

def treasuryArgs (transfers : List (Word × Nat)) : Value :=
  ((JointBinding.call transfers).map (·.value)).headD (.list [])
def treasuryCall (transfers : List (Word × Nat)) : Bytes :=
  beBytes Policy.SELECTOR_SIZE ((treasurySignature.selector.map UInt32.toNat).getD 0) ++
    (AbiType.tuple treasurySignature.params).encode (treasuryArgs transfers)
def treasuryBlob : Bytes := Policy.encode treasurySignature JointBinding.joint
def treasuryOutcome (data : Bytes) : Outcome := Policy.outcome treasuryBlob data JointBinding.noContext
def paying : List (Word × Nat) := [(JointBinding.recipient, 5), (JointBinding.treasury, 1000)]

-- The enforcer reads the blob storage accepts as storage does, and checks none of storage's invariants: it reads an
-- `IN` set storage rejects as unsorted.
#guard Policy.load treasuryBlob == Policy.parse treasuryBlob
#guard (Policy.load (oneRule (calldataTest [0] wordHint ⟨false, .in_, .constant [word 2, word 1]⟩))).isSome &&
  !stores (calldataTest [0] wordHint ⟨false, .in_, .constant [word 2, word 1]⟩)

-- The treasury policy on canonical calldata: a payment passes, the decoy and an empty array fail, bytes after the
-- encoding are not read.
#guard treasurySignature.decodeStrict (treasuryCall paying) == some (treasuryArgs paying)
#guard treasuryOutcome (treasuryCall paying) == .pass
#guard treasuryOutcome (treasuryCall [(JointBinding.treasury, 0), (JointBinding.recipient, 1000)]) == .fail
#guard treasuryOutcome (treasuryCall []) == .fail
#guard treasuryOutcome (treasuryCall paying ++ [1, 2, 3]) == .pass

-- Each abort names its reason: calldata shorter than the selector, another selector, a read past the end, a
-- non-canonical `to` word, and an array past the iteration limit.
#guard treasuryOutcome ((treasuryCall paying).take (Policy.SELECTOR_SIZE - 1)) == .abort .missingSelector
#guard treasuryOutcome ((treasuryCall paying).set 0 0) == .abort .selectorMismatch
#guard treasuryOutcome ((treasuryCall paying).take 100) == .abort .calldataOutOfBounds
#guard treasuryOutcome ((treasuryCall paying).set (Policy.SELECTOR_SIZE + 2 * WORD_SIZE) 1) ==
  .abort .nonCanonicalValue
#guard treasuryOutcome
    (treasuryCall (List.replicate (MAX_QUANTIFIED_ARRAY_LENGTH + 1) (JointBinding.treasury, 1000))) ==
  .abort .quantifierLimitExceeded

-- A declared length whose payload passes the end of the calldata aborts, where `decodeSolc` reads zero padding.
def bytesSignature : Signature := ⟨none, [.bytes]⟩
def longerThanOne : Formula := [[compare [0] .lengthGt [1]]]
def declaredLength (length : Nat) (payload : Bytes) : Bytes :=
  beBytes WORD_SIZE WORD_SIZE ++ beBytes WORD_SIZE length ++ payload
#guard Policy.outcome (Policy.encode bytesSignature longerThanOne) (declaredLength 2 (List.replicate WORD_SIZE 0))
  JointBinding.noContext == .pass
#guard Policy.outcome (Policy.encode bytesSignature longerThanOne) (declaredLength 2 []) JointBinding.noContext ==
  .abort .calldataOutOfBounds

-- A dynamic array's declared length counts its element heads: two `uint256` heads do not fit in one word.
def arraySignature : Signature := ⟨none, [.dynamicArray uint256]⟩
#guard Policy.outcome (Policy.encode arraySignature longerThanOne) (declaredLength 2 (List.replicate WORD_SIZE 0))
  JointBinding.noContext == .abort .calldataOutOfBounds

-- A fixed index past a dynamic array's end fails its group. A later group determines the outcome. The faulting group
-- sorts first, so it is evaluated first.
def twoArrays : Signature := ⟨none, [.dynamicArray uint256, .dynamicArray uint256]⟩
def pastEndThenPasses : Formula := [[compare [0, 1] .eq [0]], [compare [1, 1] .eq [2]]]
#guard (normalize pastEndThenPasses).head? == some [compare [0, 1] .eq [0]]
#guard Policy.outcome (Policy.encode twoArrays pastEndThenPasses)
  ((AbiType.tuple twoArrays.params).encode (.list [.list [unsigned 7], .list [unsigned 1, unsigned 2]]))
  JointBinding.noContext == .pass

-- An absent context property fails its group.
def contextSignature : Signature := ⟨none, []⟩
#guard Policy.outcome (Policy.encode contextSignature [[senderIs 1]]) [] JointBinding.noContext == .fail
#guard Policy.outcome (Policy.encode contextSignature [[senderIs 1]]) [] (fun _ => some (word 1)) == .pass

-- A newer minor and a value outside every defined one are not evaluated.
#guard Policy.outcome (treasuryBlob.set 0 (UInt8.ofNat (Policy.MAJOR * 2 ^ Policy.MAJOR_SHIFT +
    (Policy.MINOR + 1) * 2 ^ Policy.MINOR_SHIFT))) (treasuryCall paying) JointBinding.noContext ==
  .abort .unsupportedPolicy
#guard Policy.outcome (oneRule (3 :: (calldataTest [0] wordHint eqOne).tail)) [] JointBinding.noContext ==
  .abort .unsupportedPolicy

-- A run counts the tests it evaluates, within the policy's bound: the loop, then one test on the first element and two
-- on the second.
#guard (Policy.run treasuryBlob (treasuryCall paying) JointBinding.noContext).steps == 4
#guard (Policy.load treasuryBlob).map CompiledPolicy.workBound == some (1 + MAX_QUANTIFIED_ARRAY_LENGTH * 2)

end Callcium.Tests

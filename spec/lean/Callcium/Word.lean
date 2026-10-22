/-!
# Words

A 256-bit EVM word, byte strings with their big-endian numbers and hex spelling, and the types whose value is one
word. Two checks decide whether a word is a value of such a type: `WordType.isCanonical`, the enforcer's, and
`WordType.solcAcceptsWord`, the one Solidity 0.8.30's ABI decoder applies. Theorem 4 states they agree.
-/

namespace Callcium

/-- A 256-bit EVM word. -/
abbrev Word := BitVec 256

/-- A byte string. -/
abbrev Bytes := List UInt8

/-- The size of a word in bytes. -/
def WORD_SIZE : Nat := 32

/-- `value` modulo `256 ^ count` as `count` big-endian bytes. -/
def beBytes : Nat → Nat → Bytes
  | 0, _ => []
  | count + 1, value => beBytes count (value / 256) ++ [UInt8.ofNat value]

/-- The number big-endian `bytes` denote. -/
def beNat (bytes : Bytes) : Nat :=
  bytes.foldl (fun number byte => number * 256 + byte.toNat) 0

/-- The value of a lowercase hex digit. -/
def hexDigit? (char : Char) : Option Nat :=
  if '0' ≤ char ∧ char ≤ '9' then some (char.toNat - '0'.toNat)
  else if 'a' ≤ char ∧ char ≤ 'f' then some (char.toNat - 'a'.toNat + 10)
  else none

/-- The bytes a `0x`-prefixed hex string spells. -/
def parseHex (text : String) : Option Bytes :=
  let rec go : List Char → Option Bytes
    | [] => some []
    | high :: low :: rest => do
      let byte := (← hexDigit? high) * 16 + (← hexDigit? low)
      return UInt8.ofNat byte :: (← go rest)
    | [_] => none
  match text.toList with
  | '0' :: 'x' :: digits => go digits
  | _ => none

/-- A width of 1 to 32 bytes: `index + 1` bytes. -/
structure ByteWidth where
  /-- The width in bytes, less one. -/
  index : Fin 32
  deriving Repr, DecidableEq

/-- The width in bits. -/
def ByteWidth.bits (width : ByteWidth) : Nat := 8 * (width.index.val + 1)

/-- A type whose value is one word: the static elementary ABI types. -/
inductive WordType where
  /-- `uintN`. -/
  | uint (width : ByteWidth)
  /-- `intN`, two's complement. -/
  | int (width : ByteWidth)
  /-- `address`. -/
  | address
  /-- `bool`. -/
  | bool
  /-- An external function pointer: an address and a selector, laid out as `bytes24`. -/
  | function
  /-- `bytesN`. -/
  | fixedBytes (width : ByteWidth)
  deriving Repr, DecidableEq

/-- The EVM's `SIGNEXTEND` from byte `width.index`: the low `width.bits` bits read as two's complement. -/
def Word.signExtendFrom (width : ByteWidth) (word : Word) : Word :=
  (word.setWidth width.bits).signExtend 256

/-- Whether `word` is the canonical encoding of a value of the type: no bits above a right-aligned value, none below a
left-aligned one, and a signed value equal to its sign extension. -/
def WordType.isCanonical : WordType → Word → Bool
  | .uint width, word => word >>> width.bits == 0
  | .int width, word => word.signExtendFrom width == word
  | .address, word => word >>> 160 == 0
  | .bool, word => word >>> 1 == 0
  | .function, word => word <<< 192 == 0
  | .fixedBytes width, word => word <<< width.bits == 0

/-- Solidity's cleanup of a word to the type, `cleanup_t_<type>`: a low mask for unsigned integers and addresses, a high
mask for fixed bytes and function pointers, sign extension for signed integers, and `iszero(iszero(word))` for `bool`.
-/
def WordType.cleanup : WordType → Word → Word
  | .uint width, word => word &&& BitVec.ofNat 256 (2 ^ width.bits - 1)
  | .int width, word => word.signExtendFrom width
  | .address, word => word &&& BitVec.ofNat 256 (2 ^ 160 - 1)
  | .bool, word => if word == 0 then 0 else 1
  | .function, word => word &&& (BitVec.allOnes 256 <<< 64)
  | .fixedBytes width, word => word &&& (BitVec.allOnes 256 <<< (256 - width.bits))

/-- Whether Solidity's ABI decoder accepts `word` as a value of the type, `validator_revert_t_<type>`: the word equals
its cleanup. -/
def WordType.solcAcceptsWord (wordType : WordType) (word : Word) : Bool :=
  wordType.cleanup word == word

end Callcium

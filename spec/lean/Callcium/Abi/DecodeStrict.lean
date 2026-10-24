import Callcium.Abi.Encode
import Callcium.Abi.DecodeSolc

/-!
# Strict ABI decoder

`AbiType.decodeStrict` accepts exactly the canonical encodings. Accepted data is shorter than 2^256 bytes, and the
encoding of a value of the type is a prefix of its bytes from `start` on. Bytes after the encoding are allowed.
-/

namespace Callcium

/-- The value whose canonical encoding starts at `start` in `data`. It is none for any other data. -/
def AbiType.decodeStrict (abiType : AbiType) (data : Bytes) (start : Nat) : Option Value :=
  let value := abiType.decodeSolc data start
  if abiType.admits value ∧ start ≤ data.length ∧ data.length < 2 ^ 256 ∧ abiType.encode value <+: data.drop start then
    some value
  else none

end Callcium

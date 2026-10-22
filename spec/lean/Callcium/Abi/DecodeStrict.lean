import Callcium.Abi.Encode
import Callcium.Abi.DecodeSolc

/-!
# Strict ABI decoder

`AbiType.decodeStrict` accepts exactly the canonical encodings: data shorter than 2^256 bytes whose bytes from `start`
on open with the encoding of a value of the type. Bytes after the encoding are allowed.
-/

namespace Callcium

/-- The value whose canonical encoding `data` holds from `start`; none for any other data. -/
def AbiType.decodeStrict (abiType : AbiType) (data : Bytes) (start : Nat) : Option Value :=
  let value := abiType.decodeSolc data start
  if abiType.admits value ∧ start ≤ data.length ∧ data.length < 2 ^ 256 ∧ abiType.encode value <+: data.drop start then
    some value
  else none

end Callcium

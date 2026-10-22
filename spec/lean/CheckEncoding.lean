import Corpus

/-!
# Encoding differential check

Recomputes `Policy.encode` of the formula on every line of an implementation's encoding corpus, over the signature its
blob embeds, and compares it with the blob the implementation's encoder wrote (`Corpus.check`). From `spec/lean`:

```
lake exe check-encoding <generated corpus> <implementation corpus>
```
-/

open Callcium Callcium.Corpus

/-- The model's encoding of a line's blob. -/
def encodedOf : List String → Option String
  | [blob] => do return hexOf (← reencode (← parseHex blob))
  | _ => none

def main : List String → IO UInt32 := check 3 encodedOf

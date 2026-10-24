import Corpus

/-!
# Storage differential check

Recomputes `Policy.validate` on every line of an implementation's storage corpus and compares it with the verdict the
implementation wrote (`Corpus.check`). Run the executable from the `spec/lean` directory.

```
lake exe check-storage <generated corpus> <implementation corpus>
```
-/

open Callcium Callcium.Corpus

/-- The model's verdict on a line's blob. -/
def verdictOf : List String → Option String
  | [blob] => do return if Policy.validate (← parseHex blob) then "accept" else "reject"
  | _ => none

def main : List String → IO UInt32 := check 3 verdictOf

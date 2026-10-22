import Corpus

/-!
# Enforcement differential check

Recomputes `Policy.outcome` on every line of an implementation's enforcement corpus and compares it with the outcome the
implementation wrote (`Corpus.check`). From `spec/lean`:

```
lake exe check-enforcement <generated corpus> <implementation corpus>
```
-/

open Callcium Callcium.Corpus

/-- The model's outcome on a line's blob, calldata and context. -/
def outcomeOf : List String → Option String
  | [blob, callData, context] => do
    return (Policy.outcome (← parseHex blob) (← parseHex callData) (← parseContext context)).name
  | _ => none

def main : List String → IO UInt32 := check 5 outcomeOf
